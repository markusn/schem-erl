%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Scheme interpreter
%%% @end
%%% @author Markus Ekholm <markus@botten.org>
%%% @copyright 2016 (c) Markus Ekholm <markus@botten.org>
%%% @license Copyright (c) 2016, Markus Ekholm
%%% All rights reserved.
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
%%% @end
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
             , outer = undefined :: env_id()
             }).


%%=============================================================================
%% Types

-type env() :: #env{}.
-type env_id() :: non_neg_integer() | undefined.
-type envs() :: #{env_id() => env()}.

-type ast() :: [symbol_token() | string_token() | number_token() | ast()].
-type token() :: symbol_token()
               | string_token()
               | number_token()
               | open_paren
               | close_paren.

-type symbol_token() :: {string, string()}.
-type string_token() :: {string, string()}.
-type number_token() :: {number, integer() | float()}.

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
  {R, _NextId, _Envs} = eval_string(S, Env#env.id, Env#env.id + 1, Envs),
  R.

-spec interpreter(env_id(), env_id(), envs()) -> ok.
interpreter(EnvId, NextEnvId0, Envs0) ->
  try
    S0 = io:get_line("schem> "),
    case S0 of
      eof -> io:format("#<EOF>~n", []);
      _   ->
        S = string:strip(string:strip(S0, both, 13), both, 10),
        {Res, NextEnvId, Envs} = eval_string(S, EnvId, NextEnvId0, Envs0),
        io:format("~s~n", [pp(Res)]),
        interpreter(EnvId, NextEnvId, Envs)
    end
  catch error:Error ->
      io:format("Error: ~p~n~n", [Error]),
      interpreter(EnvId, NextEnvId0, Envs0)
  end.

%%=============================================================================
%% Internal functions

%%-----------------------------------------------------------------------------
%% Evaluation functions

-spec eval_string(string(), env_id(), env_id(), envs()) ->
                     {any(), env_id(), envs()}.
eval_string(S, EnvId, NextId, Envs) ->
  eval(parse_string(S), EnvId, NextId, Envs).

-spec eval(ast(), env_id(), env_id(), envs()) ->
              {any(), env_id(), envs()}.
eval({symbol, _} = X, EnvId, NextId, Envs) ->
  {env_get(X, EnvId, Envs), NextId, Envs};
eval(X, _EnvId, NextId, Envs) when not is_list(X) ->
  {X, NextId, Envs};
eval([{symbol, "define"}, {symbol, X}, Xs], EnvId, NextId0, Envs0) ->
  {Exp, NextId, Envs1} = eval(Xs, EnvId, NextId0, Envs0),
  #env{inner = Inner0} = Env0 = maps:get(EnvId, Envs1),
  Inner = maps:put(X, Exp, Inner0),
  Env = Env0#env{inner = Inner},
  Envs = maps:put(EnvId, Env, Envs1),
  {{symbol, X}, NextId, Envs};
eval([{symbol, "begin"} | Xs], EnvId, NextId0, Envs0) ->
  lists:foldl(fun(X, {_, NextId, Envs}) -> eval(X, EnvId, NextId, Envs) end,
              {[], NextId0, Envs0},
              Xs);
eval([{symbol, "set!"}, X, Exp], EnvId, NextId0, Envs0) ->
  {Val, NextId, Envs} = eval(Exp, EnvId, NextId0, Envs0),
  {Val, NextId, env_update(X, Val, EnvId, Envs)};
eval([{symbol, "quote"}, Xs], _EnvId, NextId, Envs) ->
  {Xs, NextId, Envs};
eval([{symbol, "lambda"}, Params, Body], EnvId, NextId, Envs) ->
  Lambda = { procedure
           , lists:map(fun({symbol, P}) -> P end, Params)
           , Body
           , EnvId
           },
  {Lambda, NextId, Envs};
eval([{symbol, "if"}, Test, Then, Else], EnvId, NextId0, Envs0) ->
  {Expression, NextId, Envs} =
    case eval(Test, EnvId, NextId0, Envs0) of
      {T, NewNext, NewEnvs} when ?IS_FALSE(T) ->
        {Else, NewNext, NewEnvs};
      {_, NewNext, NewEnvs}                   ->
        {Then, NewNext, NewEnvs}
    end,
  eval(Expression, EnvId, NextId, Envs);
eval([X0 | Xs], EnvId, NextId0, Envs0) ->
  {Proc, NextId1, Envs1} = eval(X0, EnvId, NextId0, Envs0),
  {Args0, NextId, Envs} = lists:foldl(
                            fun(X, {ArgsAcc, NextIdAcc0, EnvsAcc0}) ->
                                {XVal, NextIdAcc, EnvsAcc} =
                                  eval(X, EnvId, NextIdAcc0, EnvsAcc0),
                                {[XVal | ArgsAcc], NextIdAcc, EnvsAcc}
                            end,
                            {[], NextId1, Envs1},
                            Xs),
  Args = lists:reverse(Args0),
  call_procedure(Proc, Args, NextId, Envs).

call_procedure(F, Args, NextId, Envs) when is_function(F) ->
  F(Args, NextId, Envs);
call_procedure({procedure, Params, Body, EnvId}, Args, NextId0, Envs0) ->
  NextId = NextId0 + 1,
  Inner = maps:from_list(lists:zip(Params, Args)),
  Env = #env{id = NextId0, inner = Inner, outer = EnvId},
  Envs = maps:put(NextId0, Env, Envs0),
  eval(Body, NextId0, NextId, Envs).

to_t(true) -> {number, 1};
to_t(false) -> {number, 0}.


%%-----------------------------------------------------------------------------
%% Evaluation environment functions

env_update({symbol, K}, V, EnvId, Envs) ->
  #env{inner=Inner, outer=OuterId} = Env = maps:get(EnvId, Envs),
  case maps:is_key(K, Inner) of
    true  -> maps:put(EnvId, Env#env{inner = maps:put(K, V, Inner)}, Envs);
    false -> env_update({symbol, K}, V, OuterId, Envs)
  end.

env_get({symbol,K}, EnvId, Envs) ->
  #env{inner=Inner, outer=OuterId} = maps:get(EnvId, Envs),
  case maps:is_key(K, Inner) of
    true  -> maps:get(K, Inner);
    false -> env_get({symbol, K}, OuterId, Envs)
  end.

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
  fun(X, NextId, Envs) ->
      {F(X), NextId, Envs}
  end.


%%-----------------------------------------------------------------------------
%% Parser functions

%% @doc
%% Parse using LL(1) grammar:
%% <exp> ::= <sexp>
%% <sexp> ::= <atom> | '(' <list> ')'
%% <list> ::= <sexp> <list>
%% <atom> ::= <symbol> | <number>
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

finalize_token(Token0) ->
  convert_token(lists:reverse(Token0)).

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

list_to_tagged_string([$" | S]) ->
  list_to_tagged_string(S, "").

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

%% @doc
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

-endif.

%%% Inner Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
