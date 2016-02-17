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
- Closures (with mutable environment)
- Naive garbage collection of no longer referenced closure environments
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


## Author
Markus Ekholm (markus at botten dot org).


## License
3-clause BSD. For details see `COPYING`.

