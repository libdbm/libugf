# libugf

An Earley chart parser for unification grammars with weighted constraints, in pure Dart. It runs on the Dart VM
and on the web (dart2js and dart2wasm).

libugf conforms to Unifica SEMANTICS 2.0. It is the Dart port of the Java library
[Unifica](https://github.com/libdbm/unifica) 2.1; both follow the same written semantics,
[SEMANTICS.md](https://github.com/libdbm/unifica/blob/main/docs/SEMANTICS.md), and pass the same conformance corpus,
so a grammar parses the same way in either.

## Overview

libugf parses text against context-free grammars whose symbols carry feature structures. Productions can state
required constraints, which reject a derivation, and soft constraints, which add a penalty. When the input is
ambiguous, the parser returns the derivation with the lowest total penalty and reports whether others tied with it.

- **Earley parsing** over a token graph. Left recursion, empty productions and arbitrary context-free grammars work
  unchanged, and ambiguity is packed, so even highly ambiguous grammars parse in polynomial time.
- **Feature structures and variables.** Features on symbols unify, and variables shared within a production express
  agreement. Unification includes the occurs check.
- **Required and soft constraints.** Constraints are Boolean expressions over labelled constituents and variables. A
  soft constraint carries an integer weight, and each production can declare a cost.
- **Grammar-driven lexer.** Lexical productions in the same grammar define the tokens. The lexer takes the longest
  match, keeps every category of that length as an alternative, and supports lexical states. Tokens can also come
  from an external tagger.
- **Generation.** The generator produces sentences for a symbol and requested features, and every sentence it returns
  parses back to that symbol with those features.

## Installation

```bash
dart pub add libugf
```

`package:libugf/libugf.dart` is the whole library and reads no files, so it works on every platform.
`package:libugf/io.dart` adds loading grammars and their imports from files, on the VM.

## Quick start

A grammar file, `arithmetic.ug`:

<!-- example: arithmetic.ug -->
```
# Arithmetic with the usual precedence. Left recursion makes + - * / left associative.
start Expr;

Expr --> Expr ('+' | '-') Term | Term;
Term --> Term ('*' | '/') Factor | Factor;
Factor --> Number | '(' Expr ')';

Number --> [0-9]+ (?:[.][0-9]+)?;
```

Load it, compile it and parse:

<!-- example: quickstart -->
```dart
final parser = GrammarFiles.parse('example/arithmetic.ug')
    .flatMap((grammar) => ParserFactory.create(grammar))
    .orElseThrow();
final result = parser.parse('2 * (3 + 4)');

if (result.success) {
  print(result.tree!.display());
}
```

`GrammarFiles.parse` and `ParserFactory.create` return a `Result`, which is either a `Success` holding the value or a
`Failure` holding `ErrorDetails` (a code, a message and the individual issues). Grammars with syntax errors, unknown
predicates or undefined symbols fail here, before any input is parsed. Expected failures are always values;
libugf throws only for programming errors, such as an invalid argument.

The examples in this README are the programs in [example/](example/), which run from the package root, for example
`dart run example/example.dart`.

## Grammar syntax

### Statements

| Statement | Meaning |
|---|---|
| `start S;` | The start symbol. |
| `A --> ...;` | A production. |
| `skip A, B;` | Discard tokens of lexical categories `A` and `B` between other tokens (comments, for example). |
| `whitespace [ \t]+;` | What counts as whitespace between tokens. The default is `\s+`. `whitespace none;` disables it. |
| `module a.b;` | Name this grammar as a module. |
| `import a.b;`, `import a.b {X, Y};`, `import a.b.*;`, `import "file.ug";` | Import productions from another grammar. |
| `export X, Y;`, `export *;` | Symbols other grammars may import. |

Comments start with `#` and run to the end of the line.

### Productions

```
A --> B C;                 # a sequence
A --> B | C D | ;          # three productions: B, C D, and the empty production
A --> B (C | D E)? F*;     # groups, alternation inside a group, and ? * + repetition
A --> 'if' Expr 'then';    # quoted literals
Id --> [a-z_][a-z0-9_]*;   # a regular expression, written without delimiters
```

Literals use single or double quotes, with backslash escapes. Regular expressions are written inline in a portable
subset (see [Regular expressions](#regular-expressions)). An element can be labelled with `:name` so that constraints
can refer to it. `{TOKEN}` matches any single token.

### Lexical and syntactic productions

Every production is classified once, when the grammar is loaded:

- A production is **lexical** if its right-hand side is a single literal, or contains a regex, a state annotation or
  a state transition, and contains no nonterminal. A lexical production matches one token, whose category is the
  production's left-hand side, and its parts are never visible separately.
- Every other production is **syntactic**, including a sequence of plain literals such as `'end' 'if'`, which matches
  two tokens.
- A literal or regex written inside a syntactic production defines an anonymous token category for exactly that text
  or pattern.

At each position the lexer finds the longest match among the lexical productions that apply. Every category that
matches with that length becomes an alternative edge in the token graph, so `if` can be both a keyword and an
identifier, and the parser decides. Whitespace and `skip` categories are discarded between tokens. A character that
no production matches becomes a one-character `error` token, which only a production naming `error` can accept.

### Features and variables

<!-- example: agreement.ug -->
```
# Subject and verb agree in number through the shared variable $N.
start S;

S{num: $N} --> NP{num: $N} VP{num: $N};
NP{num: $N} --> Det{num: $N} Noun{num: $N};
VP{num: $N} --> Verb{num: $N};

Det{num: sg} --> 'a';
Det --> 'the';
Noun{num: sg} --> 'dog';
Noun{num: pl} --> 'dogs';
Verb{num: sg} --> 'barks';
Verb{num: pl} --> 'bark';
```

Features are written in braces after a symbol. A value prefixed with `$`, such as `$N`, is a variable; any other
identifier is an atom, whatever its case. Each use of a production has its own variables: the features written on a
right-hand side element must unify with the features of the constituent that fills it, and the resulting bindings
hold for the rest of that production, including its constraints. Features are never copied implicitly from a child
to its parent; a parent sees a child's features only through shared variables, as `$N` above.

`{TOKEN}` takes features the same way, which is how a grammar reads the features of caller tokens, such as POS-tagged
words, without giving each tag a category of its own:

```
Noun{lemma: $L, num: $N} --> {TOKEN}{cat: noun, lemma: $L, num: $N};
```

A token whose features conflict with those written on `{TOKEN}` does not fill it, and a feature the token does not
have leaves its variable unbound.

### Constraints and costs

<!-- example: greeting.ug -->
```
# The name must be capitalized (required). A name that does not end in a
# vowel costs 2 (a soft group). Leaving out the comma costs 1 (a production cost).
start Greeting;

Greeting --> 'hello' ',' Name:n where is_capitalized(n), matches(n, '.*[aeiou]'):2;
Greeting --> 'hello' Name:n where is_capitalized(n) @1;

Name --> [A-Za-z]+;
```

A `where` clause holds a Boolean expression. `,` is and, `|` is or, `!` is not, and parentheses group. Arguments are
quoted strings, variables such as `$N`, labels and feature paths such as `subject.num` or `$N.num`. A bare name is a
label or a symbol, never a variable. A label stands for its constituent: string predicates use the constituent's
text, and feature predicates use its features.

An unweighted top-level conjunct is **required**: if it is false, the derivation is rejected. A weighted one, written
`pred(...):w` or `(...):w`, is a **soft group**: if it is false, its weight is added to the derivation's penalty.

| Constraint | Meaning |
|---|---|
| `p(a)` | Required. |
| `p(a):3` | A soft group: adds 3 when false. |
| `(p(a), q(b)):3` | One soft group: adds 3 once, however many of its parts are false. |
| `p(a):3, q(b):4` | Two soft groups: adds 3, 4 or 7. |
| `r(c), (p(a):3, q(b):4)` | An unweighted group is flattened: one required expression and two soft groups. |
| `(p(a):3 \| q(b)):5` | A weight inside a soft group is ignored (the linter warns): adds 5 when false. |
| `p(a):3 \| q(b)`, `!p(a):3` | A compile error: a soft group must be a top-level conjunct. |

A production can also declare a cost, written `@N` at its end, which is added every time the production is used. A
cost says "prefer the other readings" without inventing a predicate that is always false.

The total penalty of a derivation is the sum of its edge costs, production costs and false soft groups, as a 64-bit
integer (see [Platforms](#platforms) for the web). The parser returns the derivation with the lowest total. Ties are
broken by declaration order: the derivation whose first differing production was declared earlier wins, so
reordering productions changes only which of the equally good readings is chosen. `ParseResult.ambiguous` is true
when more than one derivation reached the lowest penalty, and `ParseResult.tied` when only declaration order chose
between them.

### Lexical states

<!-- example: states.ug -->
```
# Words, and code spans in backquotes. Inside a code span the lexer is in
# state CODE, where any run of non-space characters is one Token.
# Comments run from '#' to the end of the line and are skipped.
start Text;
skip Comment;

Text --> (Word | Code)*;
Code --> Open Token* Close;

Word --> [a-z]+;
Open --> '`' ==> CODE;
Token --> {CODE} [^`\s]+;
Close --> {CODE} '`' ==> _;
Comment --> '#' [^\n]*;
```

A lexical production can require a state with `{STATE}` and change the state stack after it matches: `==> S` pushes
`S`, `==> _` pops, `==> !S` resets the stack to `S`, and `==> ^S` replaces the top with `S`. A lexical production with
no state annotation applies in every state. Lexical predicates such as `in_state(S)` can also test the state stack.

<!-- example: states -->
```dart
final result = parser.parse('see `x + 1` here # a comment');

print(result.tree!.display());
```

## Parsing in steps

`ParserFactory` combines three steps that can also be called separately: load the grammar, compile it against a
predicate registry, and create a parser with options.

<!-- example: pipeline -->
```dart
final loaded = GrammarFiles.parseWithImports('example/agreement.ug');
final compiled = loaded.flatMap(
  (grammar) => Compiler.compile(grammar, Predicates.standard()),
);

switch (compiled) {
  case Success(:final value):
    final options = Options(
      limits: Limits.defaults.copy(states: 100000),
      diagnostics: true,
    );
    final result = Parser.of(value, options).parse('the dogs bark');
    switch (result.outcome) {
      case Outcome.accepted:
        print(result.tree!.display());
      case Outcome.rejected:
        print(result.diagnostics!.report());
      case Outcome.limit || Outcome.cancelled:
        print('stopped: ${result.stop}');
    }
  case Failure(:final error):
    print(error);
}
```

A parse ends with one of four outcomes:

| Outcome | Meaning |
|---|---|
| `Outcome.accepted` | A derivation covers the input. `tree`, `penalty`, `ambiguous` and `tied` describe the best one. |
| `Outcome.rejected` | No derivation covers the input. With diagnostics enabled, `diagnostics` lists the furthest position reached, what was expected there, and the constraints that failed. |
| `Outcome.limit` | A limit in `Limits` was reached, a penalty overflowed, or the input could not be lexed. `stop` names the resource and what was exceeded. |
| `Outcome.cancelled` | `Options.cancel` returned true; `stop` says so. |

In the tree, a syntactic constituent is a `Node` with its symbol, label, features and children. A token of a named
category is a node with one `Leaf` child holding the text and offsets, and a token of an anonymous category is a
leaf. Productions introduced for groups and repetition do not appear; their children are spliced into the parent.

## Trust and limits

A grammar is trusted code. Its regexes run on Dart's regex engine, its imports read the `Sources` it is loaded from,
and its predicates run with the caller's privileges; none of them is sandboxed. Load grammars only from sources you
would accept code from.

Input text and caller token graphs are untrusted. A caller's `Graph` is validated when it is built (vertex ids,
forward edges, non-negative costs), `TokenSource.of` and `TokenSource.alternatives` refuse overlapping or misordered
tokens, and every parse runs within its `Limits`.

`Limits` bounds every stage of a parse: token graph vertices and lexical state depth while lexing, chart states
(including replacements), agenda entries and packed derivations while parsing, the size of the selected tree, the
diagnostic records kept, and the total time. Default options use `Limits.defaults`, which leaves wide headroom over
every sample grammar in the corpus (ten million chart states, one million graph vertices, one minute); a parse that
reaches a limit ends with `Outcome.limit` and a `stop` that names it. Adjust a limit with, for example,
`Limits.defaults.copy(states: 100000)`, or opt out with `Limits.none`, where zero means unlimited.
`result.statistics` reports the graph size, chart states, unifications and predicate calls of the parse.

Dart runs a parse synchronously, so a long parse is stopped from inside: the deadline in `Limits`, and
`Options.cancel`, a function the parser calls between steps, end it with `Outcome.limit` or `Outcome.cancelled`.
A `Compiled` grammar and a `Parser` are immutable, and each `parse` works on its own state. The parser does not catch
exceptions from callbacks: an exception thrown by a predicate, the enhancer or the observer ends the parse and
propagates out of `parse`.

## Custom predicates

Predicates live in a `Predicates` registry. A predicate has a name, an arity range, a phase and a check. The check
receives the environment, which resolves variables, labels and feature paths, and returns true or false.

<!-- example: predicates -->
```dart
final predicates = Predicates.builder().lexical().builtins().add(
  'known',
  1,
  1,
  Phase.syntactic,
  (environment, args) {
    final value = environment.resolve(args.first);
    return value != null && names.contains(value.text);
  },
).build();
final grammar = GrammarLoader.parse('''
art S;
--> 'hello' Name:n where known(n);
me --> [A-Z][a-z]+;
');
final parser = grammar
    .flatMap((source) => ParserFactory.create(source, predicates))
    .orElseThrow();
```

Syntactic predicates are evaluated when a constituent completes, and must be pure functions of their arguments,
because the parser caches their results within a parse. Positional predicates also read where the constituent starts
and ends and what follows it (`Environment.origin`, `Environment.end`, `Environment.next`), and lexical predicates read
the lexer's state stack and character position; neither is cached. A grammar that uses a predicate the registry does
not contain, or calls it with the wrong number of arguments, fails to compile.

## Tokens from outside

The lexer produces a token graph, and a parser can also parse a graph supplied by the caller, such as the output of
a part-of-speech tagger. Given a parser for this grammar:

<!-- example: tagged.ug -->
```
# Noun and Verb are filled by an external tagger. Their patterns are used
# only when the parser lexes text itself.
start S;

S --> Noun{num: $N} Verb{num: $N};

Noun --> [a-z]+;
Verb --> [a-z]+;
```

each position can carry several tagged alternatives, and the token's features unify with the features in the grammar:

<!-- example: tokens -->
```dart
final plural = Structure.of({'num': const StringConstant('pl')});
final tokens = [
  [Token('dogs', plural, 0, 4, 'Noun')],
  [Token('bark', plural, 5, 9, 'Verb'), Token('bark', plural, 5, 9, 'Noun')],
];

final graph = TokenSource.alternatives(tokens).tokenize('dogs bark');
final result = graph.flatMap(parser.parseGraph).orElseThrow();
```

`TokenSource.of(tokens)` builds a graph from a plain list. Tokens that overlap or are out of order, and alternatives
with different spans, make `tokenize` return a `Failure`; a hand-built `Graph` or `Edge` that breaks the graph
invariants is refused with an `ArgumentError`. `Parser.tokenize(input)` returns the graph the parser's own lexer
produces.

Pass the input as well, `parser.parseGraph(graph, input: 'dogs bark')`, and constraints see each constituent's text
as the input it spans (S-C9). Without the input, a constituent's text is its token texts joined by single spaces.
`parseGraph` returns a `Failure` with code `graph.tokens` if a token lies past the end of the input.

## Generation

<!-- example: generation -->
```dart
final generator = GrammarGenerator.builder(grammar)
    .random(Random(42))
    .policy(Policy.defaults.copy(depth: 10))
    .build()
    .orElseThrow();

final plural = Structure.of({'num': const StringConstant('pl')});
final sentences = generator.generate('S', plural, 5);
```

`generate(symbol, features, count)` returns up to `count` sentences, or a `Failure` explaining why none could be
produced. Before a sentence is returned it is parsed back with the same grammar, and it is kept only if the parse is
accepted and the root features unify with the requested ones, so required constraints, agreement and lexing all hold.
`batch(symbol, features, count)` returns a `Generation` with the sentences produced, the number requested, and how
many times each failure reason occurred. The verifying parse uses the builder's `limits` (`Limits.defaults` unless
set); a sentence whose parse reaches a limit is not returned, and the failure names the limit.

`Policy` sets the expansion depth, the attempts per sentence, how many times a repetition repeats, the output length
and step limits, and the `Joiner` that puts tokens together (`Joiner.spaced` follows normal punctuation spacing).
Literal terminals generate themselves. Regex terminals use a registered `TerminalGenerator` or a `Vocabulary`, chosen
by the builder's `terminal` and `vocabulary` methods. Generation is deterministic for a seeded `Random`.

## Built-in predicates

<!-- builtins -->
| Predicate | True when |
|---|---|
| `equals(a, b)` | `a` and `b` are equal values. A label and a string compare by the label's text. |
| `not_equals(a, b)` | `a` and `b` are not equal, or `a` is unbound. |
| `lt(a, b)` | `a` < `b` as numbers. |
| `le(a, b)` | `a` <= `b` as numbers. |
| `gt(a, b)` | `a` > `b` as numbers. |
| `ge(a, b)` | `a` >= `b` as numbers. |
| `starts_with(s, prefix)` | The text of `s` starts with `prefix`. |
| `ends_with(s, suffix)` | The text of `s` ends with `suffix`. |
| `contains(s, part)` | The text of `s` contains `part`. |
| `matches(s, regex)` | The whole text of `s` matches `regex`. |
| `not_empty(s)` | The text of `s` is not empty. |
| `is_upper(s)` | The text of `s` is not empty and all upper case. |
| `is_lower(s)` | The text of `s` is not empty and all lower case. |
| `is_capitalized(s)` | The text of `s` starts with an upper case letter. |
| `is_string(v)` | `v` is a string. |
| `is_number(v)` | `v` is a number. |
| `is_structure(v)` | `v` is a feature structure. |
| `is_bound(v)` | `v` resolves to a value that is not a variable: a constant, or a variable or feature path whose value is not an unbound variable (S-C11). |
| `agree(a, b)` | The features of `a` and `b` unify. |
| `unify(a, b)` | The same as `agree`. |
| `has_feature(s, name)` | The features of `s` include `name`. |
| `get_feature(s, name, value)` | Feature `name` of `s` equals `value`. |
| `feature_eq(s, name, t, other)` | Feature `name` of `s` equals feature `other` of `t`. |
| `at_start()` | The constituent starts after 0 tokens; in a lexical production, the token starts at character 0. |
| `at_position(n)` | The constituent starts after `n` tokens on some path; in a lexical production, the token starts at character `n`. |
| `at_end()` | The constituent ends at the end of the input, ignoring trailing skipped text. Also works in a lexical production. |
| `before(C, ...)` | A token of one of the categories `C` follows the constituent. Always false in a lexical production, and the linter warns about it. |
| `in_state(S, ...)` | The current lexical state is one of the arguments. Lexical. |
| `state_depth(n)` | The lexical state stack holds at most `n` states. Lexical. |
| `state_contains(S, ...)` | The lexical state stack contains one of the arguments. Lexical. |
| `at_char_start()` | Matching starts at character 0. Lexical. |
| `at_char_position(n)` | Matching starts at character `n`. Lexical. |
<!-- /builtins -->

## Regular expressions

Grammar regexes, `whitespace` patterns and `matches` patterns use a portable subset that every Unifica
implementation reads the same way (S-L7): character classes, `\p{..}` Unicode categories, `(?:...)` groups,
lookahead and lookbehind, `.`, `^` and `$`, greedy and lazy quantifiers including `{n,m}`, and a leading `(?s)` in a
`matches` pattern. Backreferences, named groups, possessive quantifiers, nested classes, `(?i)` and other flags make a
grammar invalid (`grammar.invalid`); a `matches` pattern built at runtime outside the subset is false.

Patterns match over code points. `\s`, `\d`, `\w` and `\b` are ASCII, so U+00A0 is not whitespace and `é` is not a
word character, while `\p{L}` includes `é`. `.` matches any code point except `\n`, `\r`, U+0085, U+2028 and
U+2029, or every code point after `(?s)`. `^` and `$` are the start and end of the whole input, and lookbehind and
`\b` see the input before a token. libugf checks each pattern against the subset and translates it to a Dart
`RegExp` with `unicode: true` where Dart's meaning differs, for example rewriting `\s` as `[ \t\n\x0B\f\r]`.
`Patterns.compile` exposes the same check and translation.

## Platforms

The VM and dart2wasm have 64-bit integers, so penalties, weights and integer literals are exact up to 2^63 - 1, and a
penalty sum past that ends the parse with `Outcome.limit` and `Stop.penalty`. Under dart2js integers are doubles,
exact only up to 2^53 - 1: a penalty sum past that limit also ends with `Outcome.limit`, and a grammar with a weight,
cost or integer literal past it fails to load. Grammars whose numbers stay below 2^53 behave the same everywhere.

`package:libugf/io.dart` uses `dart:io` and is not available on the web; use `Sources.memory` with
`GrammarLoader.parseWithImports` to load grammars with imports there.

## Debugging

`Options` takes a `ParseObserver`, which receives a `ParseEvent` for each prediction, scan, completion, unification
and constraint evaluation; with `ParseObserver.none`, the default, no event is built. `LoggingObserver` keeps the
events and can write each as a line to a sink. `Options(diagnostics: true)` records why a parse failed, in
`ParseResult.diagnostics`. `GrammarLinter` reports unreachable and undefined symbols, unbound labels, misplaced state
transitions, ignored weights, `before` in a lexical production, and lexical rules for one symbol written with the same
pattern but different features, whose ties only declaration order can break (S-P3), and suggests a production cost
where a weight is attached to a predicate that is not registered.

## Coming from Java

The Dart API follows Unifica 2.1. Every public Java type has a Dart counterpart; types not listed here have the same
name and shape in both.

### General

| Java | Dart |
|---|---|
| `Result<T, ErrorDetails>`, `ErrorDetails` | Same names; `Success` and `Failure` are the `Result` subclasses |
| Checked and unchecked exceptions for expected failures | A `Result` failure with an error code, such as `GrammarLoader.syntax` |
| `Foo.Builder` nested classes (`Grammar.builder()`, `Structure.builder()`, `Predicates.builder()`) | Same factory methods; the builders are top-level classes (`GrammarBuilder`, `StructureBuilder`, `PredicatesBuilder`) |
| Per-field copy methods (`limits.states(n)`, `policy.depth(n)`) | One `copy(...)` with named parameters (`Limits.copy`, `Policy.copy`) |
| `UPPER_CASE` constants (`Limits.NONE`, `Limits.DEFAULTS`, `Phase.SYNTACTIC`) | `lowerCamelCase` (`Limits.none`, `Limits.defaults`, `Phase.syntactic`) |
| Nested enums and records (`Predicates.Phase`, `ParseDiagnostics.FailureKind`) | Top-level types (`Phase`, `Cause`) |

### Grammar loading

| Java | Dart |
|---|---|
| `UnificationGrammarParserFactory.parse(String)`, `unvalidated(String)` | `GrammarLoader.parse`, `GrammarLoader.unvalidated` |
| `UnificationGrammarParserFactory.parse(Path)`, `unvalidated(Path)`, `parseWithImports(Path, ...)` | `GrammarFiles.parse`, `unvalidated`, `parseWithImports` (`io.dart`) |
| Imports resolved from the file system | `GrammarLoader.parseWithImports(Sources, path)` over any `Sources`: `Sources.memory` everywhere, `FileSources` from `io.dart` |
| `UnificationGrammarVisitorImpl` | Not exported (the hand-written loader replaces ANTLR) |
| `ModuleResolver` (package `grammar.loader`) | `ModuleResolver`, taking a `Sources` |

### Lexer and parser

| Java | Dart |
|---|---|
| `lexer.Node` | `Vertex` (`Node` is the parse tree's interior node) |
| `Parser.parse(input)`, `parse(input, symbol, features)` | `Parser.parse(input, {symbol, features})` |
| `Parser.parse(Graph)`, `parse(Graph, input)` | `Parser.parseGraph(graph, {input})`, returning `Result<ParseResult, ErrorDetails>` |
| Thread interrupt | `Options.cancel`, a cooperative check; reported as `Outcome.cancelled` with `Stop.interrupt` |
| `Limits.deadline` measured with `System.nanoTime` | A `Duration` measured with a `Stopwatch` |
| `ParseResult` with a warning logged when declaration order alone chose the tree | `ParseResult.tied` |

### Diagnostics and observers

| Java | Dart |
|---|---|
| `ParseDiagnostics.ParseLattice` | `Lattice` |
| `ParseDiagnostics.FailureKind` | `Cause` (`Failure` is the `Result` subclass) |
| `generateReport()` | `report()` |
| `record...` methods with positional details | `record...` methods taking record objects |
| `ParseObserver` with nine `on...` callbacks | `ParseObserver.observe(ParseEvent)` over a sealed `ParseEvent` |
| `ParseObserver.NOOP` | `ParseObserver.none`; with it no event is built |
| `ParseEvents` records | `Started`, `Ended`, `Predicted`, `Scanned`, `Completed`, `Unified` (`Unification`), `Evaluated` (`ConstraintEval`), `Finished` (`Position`), `Unexpected` |
| `LoggingObserver` writing to SLF4J, filtered by `Type` | `LoggingObserver` with an optional line `sink`, filtered by event class |

### Generator

| Java | Dart |
|---|---|
| `Vocabulary.Entry` | `Word` (`Entry` is the predicate registry's) |
| `RegexTerminalGenerator.forNumbers` | `RegexTerminalGenerator.numbers` |
| A lambda as a `TerminalGenerator` | `TerminalGenerator(fn)` |
| `java.util.Random(seed)` | `dart:math` `Random(seed)`; generation is deterministic for a seed, but the random sequence is not Java's |

### Extension points

`TokenEnhancer`, `ParseObserver` and `TerminalGenerator` are
`abstract base class`: extend them (each has a default or a function
factory) rather than implement them. `Sources`, `TokenSource` and
`TokenMatchGenerator` are `abstract interface class`, to implement. Every
other exported class is `final`, `sealed` or `abstract final`.

## License

BSD 3-Clause License. See [LICENSE](LICENSE) for details.
