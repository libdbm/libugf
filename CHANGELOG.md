# Changelog

## 2.0.0

The first published release: a pure Dart port of Unifica 2.0, conforming to Unifica SEMANTICS 2.0. It passes the
Unifica conformance corpus on the VM, the web (dart2js) and dart2wasm, and every port grammar's samples on the VM.

- Grammar loading with modules and imports through any `Sources` (`package:libugf/libugf.dart`), or from files
  (`package:libugf/io.dart`).
- Variables are written with a `$` prefix, as in `S{num: $N}` and `agree($N, $M)`; any other identifier in a
  feature value is an atom, whatever its case.
- A compiler to an immutable `Compiled` grammar, checked against a `Predicates` registry; unknown predicates and wrong
  arities are compile errors.
- A grammar-driven lexer producing a token graph with every category of the longest match, lexical states, `skip`
  and `whitespace`; caller token graphs through `TokenSource` and `Parser.parseGraph`.
- An Earley parser with feature unification, required constraints, soft groups, `@N` production costs, 64-bit
  penalties, ambiguity packing, and tie-breaking by declaration order (`ParseResult.tied` reports when it decided).
- `Limits` on every stage of a parse, cooperative cancellation through `Options.cancel`, and `Statistics`.
- `ParseDiagnostics`, `ParseObserver` events and `LoggingObserver`.
- `GrammarLinter`.
- `GrammarGenerator`, whose sentences are all parsed back before they are returned.
- Expected failures are `Result<T, ErrorDetails>` values throughout.

Earlier development versions followed Unifica 1.0.3 and were never published.
