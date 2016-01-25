schem-erl
=========
[![Build Status](https://travis-ci.org/markusn/schem-erl.png?branch=master)](https://travis-ci.org/markusn/schem-erl)

Intepreter for a small subset of Scheme. The eval part of read-eval-print is
implemented as a pure Erlang function.


## Building and running

```bash
make escript
rlwrap ./schem
```


## Running tests

```bash
make check
```


## Features

- Lexical scoping
- Closures (mutable)
- Implemented primitives
  - begin
  - quote
  - set!
  - define
  - lambda
  - car
  - cdr
  - cons
  - length
  - list
  - +, -, *. /
  - <, >, <=, >=, =, equal?
- Implemented types
  - Symbol
  - Number


## Limitations

- Anything missing in `Features`
- Error handling
- Garbage collection (non-primitive procedure calls allocates an environment
  that is never reclaimed).


## Author
Markus Ekholm (markus at botten dot org).


## License
3-clause BSD. For details see `COPYING`.

