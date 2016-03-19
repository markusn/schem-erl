%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Copyright 2016 (c) Markus Ekholm <markus@botten.org>
%%% All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%%    * Redistributions of source code must retain the above copyright
%%%      notice, this list of conditions and the following disclaimer.
%%%    * Redistributions in binary form must reproduce the above copyright
%%%      notice, this list of conditions and the following disclaimer in the
%%%      documentation and/or other materials provided with the distribution.
%%%    * Neither the name of the author nor the
%%%      names of its contributors may be used to endorse or promote products
%%%      derived from this software without specific prior written permission.
%%%
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
%%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%%% ARE DISCLAIMED. IN NO EVENT SHALL MARKUS EKHOLM BE LIABLE FOR ANY
%%% DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
%%% (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
%%% ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
%%% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
%%% THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%%
%%% @doc Scheme interpreter
%%% @end
%%% @author Markus Ekholm <markus@botten.org>
%%% @copyright 2016 (c) Markus Ekholm <markus@botten.org>
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%=============================================================================
%% Module declaration

-module(schem).


%%=============================================================================
%% Exports

-export([ main/1
        , eval_string/1
        ]).


%%=============================================================================
%% Records

-record(env, { id :: env_id()
             , inner = maps:new() :: #{string() => any()}
             , outer = undefined :: maybe_env_id()
             }).


%%=============================================================================
%% Types

-type env() :: #env{}.
-type env_id() :: non_neg_integer().
-type maybe_env_id() :: env_id() | undefined.
-type envs() :: #{env_id() => env()}.

-type ast() :: [symbol_token() | string_token() | number_token() | ast()].
-type token() :: symbol_token()
               | string_token()
               | number_token()
               | paren_token().

-type symbol_token() :: {symbol, string()}.
-type string_token() :: {string, string()}.
-type number_token() :: {number, integer() | float()}.
-type paren_token() :: open_paren | close_paren.

%%=============================================================================
%% Defines

-define(IS_PAREN(C),
        C =:= $) orelse C =:= $().
-define(IS_FALSE(T),
        T =:= [] orelse T == {number, 0} orelse T == {number, 0.0}).


%%=============================================================================
%% Main

%% @doc
%% Run interpreter until eof is given (Ctrl-d).
%% @end
-spec main(any()) -> ok.
main(_) ->
  io:format("schem intepreter~n", []),
  Env = default_env(),
  Envs = #{Env#env.id => Env},
  interpreter(Env#env.id, Env#env.id + 1, Envs).

%%=============================================================================
%% API functions

%% @doc
%% Evaluate the Scheme expressions and return the result.
%% @end
-spec eval_string(string()) -> any().
eval_string(S) ->
  Env = default_env(),
  Envs = #{Env#env.id => Env},
  {R, _NId, _Envs, _Dirty} = eval_string(S, Env#env.id, Env#env.id + 1, Envs),
  R.


%%=============================================================================
%% Internal functions

%%-----------------------------------------------------------------------------
%% Interpreter functions

-spec interpreter(env_id(), env_id(), envs()) -> ok.
interpreter(EnvId, NextId0, Envs0) ->
  try
    S0 = io:get_line("schem> "),
    case S0 of
      eof -> io:format("#<EOF>~n", []);
      _   ->
        S = string:strip(string:strip(S0, both, 13), both, 10),
        {Res, NextId, Envs1, Dirty} = eval_string(S, EnvId, NextId0, Envs0),
        io:format("~s~n", [pp(Res)]),
        %% Only GC if something dirty happened
        Envs = case Dirty of
                 true  -> gc(EnvId, Envs1);
                 false -> Envs1
               end,
        interpreter(EnvId, NextId, Envs)
    end
  catch error:Error ->
      io:format("Error: ~p~n~n", [Error]),
      interpreter(EnvId, NextId0, Envs0)
  end.


%%-----------------------------------------------------------------------------
%% Evaluation functions

-spec eval_string(string(), env_id(), env_id(), envs()) ->
                     {any(), env_id(), envs(), boolean()}.
%% @private
%% Evaluate Schem expression string in the environment denoted by the
%% environment id.
%% @end
eval_string(S, EnvId, NextId, Envs) ->
  eval(parse_string(S), EnvId, NextId, Envs, false).

-spec eval(ast(), env_id(), env_id(), envs(), boolean()) ->
              {any(), env_id(), envs(), boolean()}.
eval({symbol, _} = X, EnvId, NextId, Envs, Dirty) ->
  {env_get(X, EnvId, Envs), NextId, Envs, Dirty};
eval(X, _EnvId, NextId, Envs, Dirty) when not is_list(X) ->
  {X, NextId, Envs, Dirty};
eval([{symbol, "define"}, {symbol, X}, Xs], EnvId, NextId0, Envs0, Dirty0) ->
  {Exp, NextId, Envs1, _} = eval(Xs, EnvId, NextId0, Envs0, Dirty0),
  #env{inner = Inner0} = Env0 = maps:get(EnvId, Envs1),
  Inner = maps:put(X, Exp, Inner0),
  Env = Env0#env{inner = Inner},
  Envs = maps:put(EnvId, Env, Envs1),
  {{symbol, X}, NextId, Envs, true};
eval([{symbol, "begin"} | Xs], EnvId, NextId0, Envs0, Dirty0) ->
  lists:foldl(
    fun(X, {_, NextId, Envs, Dirty}) -> eval(X, EnvId, NextId, Envs, Dirty) end,
    {[], NextId0, Envs0, Dirty0},
    Xs);
eval([{symbol, "set!"}, X, Exp], EnvId, NextId0, Envs0, Dirty) ->
  {Val, NextId, Envs, _Dirty} = eval(Exp, EnvId, NextId0, Envs0, Dirty),
  {Val, NextId, env_update(X, Val, EnvId, Envs), true};
eval([{symbol, "quote"}, Xs], _EnvId, NextId, Envs, Dirty) ->
  {Xs, NextId, Envs, Dirty};
eval([{symbol, "lambda"}, Params, Body], EnvId, NextId, Envs, Dirty) ->
  Lambda = { procedure
           , lists:map(fun({symbol, P}) -> P end, Params)
           , Body
           , EnvId
           },
  {Lambda, NextId, Envs, Dirty};
eval([{symbol, "if"}, Test, Then, Else], EnvId, NextId0, Envs0, Dirty0) ->
  {Expression, NextId, Envs, Dirty} =
    case eval(Test, EnvId, NextId0, Envs0, Dirty0) of
      {T, NewNext, NewEnvs, NewDirty} when ?IS_FALSE(T) ->
        {Else, NewNext, NewEnvs, NewDirty};
      {_, NewNext, NewEnvs, NewDirty}                   ->
        {Then, NewNext, NewEnvs, NewDirty}
    end,
  eval(Expression, EnvId, NextId, Envs, Dirty);
eval([X0 | Xs], EnvId, NextId0, Envs0, Dirty0) ->
  {Proc, NextId1, Envs1, Dirty1} = eval(X0, EnvId, NextId0, Envs0, Dirty0),
  {Args0, NextId, Envs, Dirty} =
    lists:foldl(
      fun(X, {ArgsAcc, NextIdAcc0, EnvsAcc0, DirtyAcc0}) ->
          {XVal, NextIdAcc, EnvsAcc, DirtyAcc} =
            eval(X, EnvId, NextIdAcc0, EnvsAcc0, DirtyAcc0),
          {[XVal | ArgsAcc], NextIdAcc, EnvsAcc, DirtyAcc}
      end,
      {[], NextId1, Envs1, Dirty1},
      Xs),
  Args = lists:reverse(Args0),
  call_procedure(Proc, Args, NextId, Envs, Dirty).

%% Primitive procedures
call_procedure(F, Args, NextId, Envs, Dirty) when is_function(F) ->
  F(Args, NextId, Envs, Dirty);
%% Schem procedures
call_procedure({procedure, Params, Body, EnvId}, Args, NextId0, Envs0, _) ->
  NextId = NextId0 + 1,
  Inner = maps:from_list(lists:zip(Params, Args)),
  Env = #env{id = NextId0, inner = Inner, outer = EnvId},
  Envs = maps:put(NextId0, Env, Envs0),
  eval(Body, NextId0, NextId, Envs, true).

to_t(true) -> {number, 1};
to_t(false) -> {number, 0}.


%%-----------------------------------------------------------------------------
%% Evaluation environment functions

-spec env_update(symbol_token(), any(), env_id(), envs()) -> envs().
env_update({symbol, K}, V, EnvId, Envs) ->
  #env{inner=Inner, outer=OuterId} = Env = maps:get(EnvId, Envs),
  case maps:is_key(K, Inner) of
    true  -> maps:put(EnvId, Env#env{inner = maps:put(K, V, Inner)}, Envs);
    false -> env_update({symbol, K}, V, OuterId, Envs)
  end.

-spec env_get(symbol_token(), env_id(), envs()) -> any().
env_get({symbol, K}, EnvId, Envs) ->
  #env{inner=Inner, outer=OuterId} = maps:get(EnvId, Envs),
  case maps:is_key(K, Inner) of
    true  -> maps:get(K, Inner);
    false -> env_get({symbol, K}, OuterId, Envs)
  end.

%% @private
%% Recursively remove envs that are not referenced until a fix-point is reached.
%% @end
-spec gc(env_id(), envs()) -> envs().
gc(EnvId, Envs0) ->
  Referenced = sets:add_element(EnvId, get_referenced_transitive(EnvId, Envs0)),
  Envs = maps:filter(fun(K, _) -> sets:is_element(K, Referenced) end, Envs0),
  case Envs =:= Envs0 of
    true  -> Envs;
    false -> gc(EnvId, Envs)
  end.

-spec get_referenced_transitive(env_id(), envs()) -> sets:set(env_id()).
get_referenced_transitive(EnvId, Envs) ->
  {Referenced, _} = get_referenced_transitive(EnvId, Envs, sets:new()),
  Referenced.

-spec get_referenced_transitive(env_id(), envs(), sets:set(env_id())) ->
                                   {sets:set(env_id()), sets:set(env_id())}.
get_referenced_transitive(EnvId, Envs, Processed0) ->
  case sets:is_element(EnvId, Processed0) of
    true ->
      {sets:new(), Processed0};
    false ->
      Env = maps:get(EnvId, Envs),
      Processed = sets:add_element(EnvId, Processed0),
      Refs = get_referenced_non_transitive(Env),
      Fun = fun(RefId, {AccRefs0, AccProcessed0}) ->
                {NewRefs, AccProcessed} =
                  get_referenced_transitive(RefId, Envs, AccProcessed0),
                AccRefs = sets:union(AccRefs0, NewRefs),
                {AccRefs, AccProcessed}
            end,
      sets:fold(Fun, {Refs, Processed}, Refs)
  end.

-spec get_referenced_non_transitive(env()) -> sets:set(env_id()).
get_referenced_non_transitive(Env) ->
  Refs0 = sets:new(),
  #env{inner = Inner, outer = Outer} = Env,
  Refs = case Outer of
           undefined ->
             Refs0;
           _         ->
             sets:add_element(Outer, Refs0)
         end,
  maps:fold(fun(_, {procedure, _, _, ProcEnvId}, AccRefs) ->
                sets:add_element(ProcEnvId, AccRefs);
               (_, _, AccRefs) ->
                AccRefs
            end,
            Refs,
            Inner).

-spec default_env() -> env().
default_env() ->
  #env{ id = 0
      , inner =
         #{ "car" =>
              primitive_procedure(fun([L]) -> hd(L) end)
          , "cdr" =>
              primitive_procedure(fun([L]) -> tl(L) end)
          , "cons" =>
              primitive_procedure(fun([A, B]) -> [A | B] end)
          , "length" =>
              primitive_procedure(fun([L]) -> {number, length(L)} end)
          , "list" =>
              primitive_procedure(fun(L) -> L end)
          , "+" => primitive_procedure(
                     fun([{number, A}, {number, B}]) -> {number, A + B} end)
          , "-" => primitive_procedure(
                     fun([{number, A}, {number, B}]) -> {number, A - B} end)
          , "/" => primitive_procedure(
                     fun([{number, A}, {number, B}]) -> {number, A / B} end)
          , "*" => primitive_procedure(
                     fun([{number, A}, {number, B}]) -> {number, A * B} end)
          , "<=" => primitive_procedure(
                      fun([{number, A}, {number, B}]) -> to_t(A =< B) end)
          , ">=" => primitive_procedure(
                      fun([{number, A}, {number, B}]) -> to_t(A >= B) end)
          , "<" => primitive_procedure(
                     fun([{number, A}, {number, B}]) -> to_t(A < B) end)
          , ">" => primitive_procedure(
                     fun([{number, A}, {number, B}]) -> to_t(A > B) end)
          , "=" => primitive_procedure(
                     fun([{number, A}, {number, B}]) -> to_t(A == B) end)
          , "equal?" =>
              primitive_procedure(fun([A, B]) -> to_t(A =:= B) end)
          }
      }.

primitive_procedure(F) ->
  fun(X, NextId, Envs, Dirty) ->
      {F(X), NextId, Envs, Dirty}
  end.


%%-----------------------------------------------------------------------------
%% Parser functions

%% @private
%% Parse using LL(1) grammar:
%% exp ::= sexp
%% sexp ::= atom | open_paren list end_paren
%% list ::= sexp list
%% atom ::= symbol | number
%% @end
-spec parse_string(string()) -> ast().
parse_string(S) ->
  parse(tokenize(S)).

-spec parse([token()]) -> ast().
parse(Tokens) ->
  {[], Ast} = parse_sexp(Tokens),
  Ast.

parse_sexp([{_, _} = Token | Tokens]) ->
  {Tokens, Token};
parse_sexp([open_paren | Tokens0]) ->
  {[close_paren | Tokens], Ast} = parse_list(Tokens0, []),
  {Tokens, Ast}.

parse_list([close_paren | _] = Tokens, Ast) -> %% lookahead
  {Tokens, lists:reverse(Ast)};
parse_list([] = Tokens, Ast) ->
  {Tokens, lists:reverse(Ast)};
parse_list(Tokens0, Ast) ->
  {Tokens, SexpAst} = parse_sexp(Tokens0),
  parse_list(Tokens, [SexpAst | Ast]).

pp([]) -> "";
pp(X) when is_list(X) ->
  "(" ++ lists:flatten(string:join(lists:map(fun pp/1, X), " ")) ++ ")";
pp({symbol, X}) ->
  X;
pp({string, X}) ->
  "\"" ++ X ++ "\" ";
pp({procedure, _, _, _}) ->
  "#<CLOSURE>";
pp(F) when is_function(F) ->
  "#<PRIMITIVE>";
pp({number, X}) ->
  lists:flatten(io_lib:format("~p", [X])).

%%-----------------------------------------------------------------------------
%% Lexer functions

-spec tokenize(string()) -> [token()].
tokenize(S) ->
  tokenize(S, "", [], false).

-spec tokenize(string(), string(), [token()], boolean()) -> [token()].
%% basecase 1, no token no nothing, assert not inside a string
tokenize("", "", Acc, false) ->
  lists:reverse(Acc);
%% basecase 2, no more string but a token
tokenize("", [_|_] = Token, Acc, InsideStr) ->
  tokenize("", "", [finalize_token(Token) | Acc], InsideStr);
%% start of string
tokenize([$" | S], "", Acc, false) ->
  tokenize(S, "\"", Acc, true);
%% end of string
tokenize([$" | S], Token, Acc, true) ->
  tokenize(S, [$" | Token], Acc, false);
%% whitespace not inside string with token
tokenize([$  | S], [_|_] = Token, Acc, false = InsideStr) ->
  tokenize(S, "", [finalize_token(Token) | Acc], InsideStr);
%% whitespace not inside string with no token
tokenize([$  | S], "", Acc, false = InsideStr) ->
  tokenize(S, "", Acc, InsideStr);
%% paren not inside string with no token
tokenize([C | S], "", Acc, false = InsideStr) when ?IS_PAREN(C) ->
  tokenize(S, "", [paren_to_token(C) | Acc], InsideStr);
%% paren not inside string with token
tokenize([C | S], [_|_] = Token, Acc, false = InsideStr) when ?IS_PAREN(C) ->
  tokenize(S, "", [paren_to_token(C), finalize_token(Token) | Acc], InsideStr);
%% build token
tokenize([C | S], Token, Acc, InsideStr) ->
  tokenize(S, [C | Token], Acc, InsideStr).

-spec finalize_token(string()) -> token().
finalize_token(Token0) ->
  convert_token(lists:reverse(Token0)).

-spec paren_to_token(char()) -> paren_token().
paren_to_token($() -> open_paren;
paren_to_token($)) -> close_paren.

-spec convert_token(string()) -> token().
convert_token(Token0) ->
  Converters = [ fun list_to_tagged_string/1
               , fun(X) -> {number, list_to_integer(X)} end
               , fun(X) -> {number, list_to_float(X)} end
               , fun(X) -> {symbol, X} end
               ],
  Fun = fun(F) ->
            try
              F(Token0)
            catch _:_ ->
                false
            end
        end,
  {[Token | _], _} = lists:partition(fun(X) -> X =/= false end,
                                     lists:map(Fun, Converters)),
  Token.

%% @private
%% Accept strings enclosed with " as string tokens.
%% @end
-spec list_to_tagged_string(string()) -> string_token().
list_to_tagged_string([$" | S]) ->
  list_to_tagged_string(S, "").

-spec list_to_tagged_string(string(), string()) -> string_token().
list_to_tagged_string([$"], Acc) ->
  {string, lists:reverse(Acc)};
list_to_tagged_string([C | S], Acc) ->
  list_to_tagged_string(S, [C | Acc]).


%%=============================================================================
%% Tests

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

%%-----------------------------------------------------------------------------
%% Unit tests

%% @private
%% Most examples taken from Norvigs Lispy article.
%% @end
eval_string_test_() ->
  [ ?_assertEqual(
       {number, 6},
       eval_string("(+ 3 3)"))
  , ?_assertEqual(
       {number, 1},
       eval_string("(- 2 1)"))
  , ?_assertEqual(
       {number, 4},
       eval_string("(+ 3 (- 2 1))"))
  , ?_assertEqual(
       {number, 4},
       eval_string("(begin (define x 3) (define y 1) (+ x y))"))
  , ?_assertEqual(
       {number, 28.26},
       eval_string(
         "(begin "
         "(define pi 3.14)"
         "(define circle-area (lambda (r) (* pi (* r r))))"
         "(circle-area 3))"))
  , ?_assertEqual(
       {number, 3628800},
       eval_string(
         "(begin "
         "(define fact "
         "(lambda (n) (if (<= n 1) 1 (* n (fact (- n 1))))))"
         "(fact 10))"))
  , ?_assertEqual(
       {number, 10},
       eval_string(
         "(begin "
         "(define twice (lambda (x) (* 2 x)))"
         "(twice 5))"))
  , ?_assertEqual(
       {number, 40},
       eval_string(
         "(begin "
         "(define twice (lambda (x) (* 2 x)))"
         "(define repeat (lambda (f) (lambda (x) (f (f x)))))"
         "((repeat twice) 10))"))
  , ?_assertEqual(
       {number, 3},
       eval_string(
         "(begin "
         "(define first car)"
         "(define rest cdr)"
         "(define count "
         "(lambda (item L) (if L (+ (equal? item (first L)) "
         "                         (count item (rest L))) 0)))"
         "(count 0 (list 0 1 2 3 0 0)))"))
  , ?_assertEqual(
       {number, 4},
       eval_string(
         "(begin "
         "(define first car)"
         "(define rest cdr)"
         "(define count "
         "(lambda (item L) (if L (+ (equal? item (first L)) "
         "                         (count item (rest L))) 0)))"
         "(count (quote the) "
         "  (quote (the more the merrier the bigger the better))))"))
  , ?_assertEqual(
       [ {number, 0}
       , {number, 1}
       , {number, 2}
       , {number, 3}
       , {number, 4}
       , {number, 5}
       , {number, 6}
       , {number, 7}
       , {number, 8}
       , {number, 9}
       ],
       eval_string(
         "(begin "
         "(define range "
         "(lambda (a b) (if (= a b) (quote ()) (cons a (range (+ a 1) b)))))"
         "(range 0 10))"))
  , ?_assertEqual(
       {number, 55},
       eval_string(
         "(begin "
         "(define fib "
         "(lambda (n) "
         "(if (< n 2) 1 (+ (fib (- n 1)) (fib (- n 2))))))"
         "(fib 9))"))
  , ?_assertEqual(
       {number, 80.0},
       eval_string(
         "(begin "
         "(define make-account "
         "(lambda (balance) "
         "  (lambda (amt) "
         "    (begin (set! balance (+ balance amt)) balance)))) "
         "(define account1 (make-account 100.00)) "
         "(account1 -20.00))"))
  , ?_assertEqual(
       {number, 60.0},
       eval_string(
         "(begin "
         "(define make-account "
         "(lambda (balance) "
         "  (lambda (amt) "
         "    (begin (set! balance (+ balance amt)) balance)))) "
         "(define account1 (make-account 100.00)) "
         "(account1 -20.00) "
         "(account1 -20.00))"))
  ].

gc_test_() ->
  [ ?_assertEqual([0, 1, 2, 3],
                  maps:keys(
                    gc(
                      0,
                      #{ 0 =>
                           #env{inner = #{"x" => {procedure, ["x"], [], 3}}}
                       , 3 => #env{outer = 2}
                       , 2 => #env{ outer = 0
                                  , inner = #{"y" => {procedure, ["x"], [], 1}}
                                  }
                       , 1 => #env{outer = 0}
                       , 10 => #env{outer = 0}
                       })))
  ].

get_referenced_transitive_test_() ->
  [ ?_assertEqual([],
                 sets:to_list(
                   get_referenced_transitive(0, #{0 => default_env()})))
  , ?_assertEqual([0, 1, 2, 3],
                 lists:usort(
                   sets:to_list(
                     get_referenced_transitive(
                       0,
                       #{ 0 =>
                            #env{inner = #{"x" => {procedure, ["x"], [], 3}}}
                        , 3 => #env{outer = 2}
                        , 2 => #env{ outer = 0
                                   , inner = #{"y" => {procedure, ["x"], [], 1}}
                                   }
                        , 1 => #env{outer = 0}
                        , 10 => #env{outer = 0}
                        }))))
  ].

get_referenced_non_transitive_test() ->
  [ ?_assertEqual([],
                  sets:to_list(get_referenced_non_transitive(#env{})))
  ,  ?_assertEqual([1],
                  sets:to_list(get_referenced_non_transitive(#env{outer = 1})))
  ,  ?_assertEqual([1],
                  sets:to_list(
                    get_referenced_non_transitive(
                      #env{inner = #{ "x" => {procedure, ["x"], [], 2}
                                    , "y" => fun() -> ok end
                                    }
                          })))
  ].

parse_string_test_() ->
  [ ?_assertEqual(
       [ {symbol, "+"}
       , {number, 1}
       , [ {symbol, "-"}
         , {number, 4}
         , {number, 2}
         ]
       ],
       parse_string("(+ 1 (- 4     2))"))
  , ?_assertEqual(
       [ {symbol, "+"}
       , {number, 3}
       , {number, 3}
       ],
       parse_string("(+ 3 3)"))
  , ?_assertEqual(
       [ {symbol, "begin"}
       , [ {symbol, "define"}
         , {symbol, "x"}
         , {number, 3}
         ]
       , [ {symbol, "define"}
         , {symbol, "y"}
         , {number, 1}
         ]
       , [ {symbol, "+"}
         , {symbol, "x"}
         , {symbol, "y"}
         ]
       ],
       parse_string("(begin (define x 3) (define y 1) (+ x y))"))
  ].

pp_test_() ->
  [ ?_assertEqual(
       "(+ 1 (- 4 2))",
       pp([ {symbol, "+"}
              , {number, 1}
              , [ {symbol, "-"}
                , {number, 4}
                , {number, 2}
                ]
              ]))
  , ?_assertEqual(
       "(+ 3 3)",
       pp([{symbol, "+"}, {number, 3}, {number, 3}]))
  , ?_assertEqual(
       "(begin (define x 3) (define y 1) (+ x y))",
       pp([ {symbol, "begin"}
              , [{symbol, "define"}, {symbol, "x"}, {number, 3}]
              , [{symbol, "define"}, {symbol, "y"}, {number, 1}]
              , [{symbol, "+"}, {symbol, "x"}, {symbol, "y"}]
              ]))
  ].

tokenize_test_() ->
  [ ?_assertEqual(
       [ open_paren
       , {symbol, "+"}
       , {number, 1}
       , open_paren
       , {symbol, "-"}
       , {number, 4}
       , {number, 2}
       , close_paren
       , close_paren
       ],
       tokenize("(+ 1 (- 4     2))"))
  , ?_assertEqual(
       [ open_paren
       , {symbol, "print"}
       , {string, "hello world!"}
       , close_paren
       ],
       tokenize("(print \"hello world!\")"))
  , ?_assertEqual(
       [ open_paren
       , {symbol, "print"}
       , {string, "hello (world!))"}
       , close_paren
       ],
       tokenize("(print \"hello (world!))\")"))
  ].

-endif.

%%% Inner Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
