# Regular expressions in libugf

libugf follows rule S-L7 of `SEMANTICS.md`: grammar regexes, the `whitespace` pattern and `matches` patterns use a
portable subset of regular expressions, matched over code points. This note records how libugf checks a pattern
against the subset and translates it for Dart's `RegExp`, and the engine findings behind each translation. The
findings were checked on the Dart 3.13.4 VM and hold on dart2js and dart2wasm, which run the corpus too.

## Checking and translating

`Patterns` (`lib/src/patterns.dart`) is a port of unifica's `Patterns` at `8d8c01a`. One scanner reads a pattern,
accepts exactly what Java's accepts and reports anything else as `pattern.subset` with Java's message
(`<what> at offset N (S-L7)`). Instead of Java's form it emits a Dart form, which is compiled with `unicode: true` and
no other flag.

- `Patterns.portable(source)` checks a standalone pattern (`whitespace`, `matches`), which may start with `(?s)`.
- `Patterns.fragment(source)` checks a grammar regex element. It is part of a lexeme's pattern and takes no flag.
- `Patterns.compile(source)` compiles a standalone pattern. A Dart compile error on a pattern the scanner accepted is
  also `pattern.subset`.

A grammar whose regex, `whitespace` or constant `matches` pattern is outside the subset does not compile
(`grammar.invalid`, reported by the corpus as `validation`). A `matches` pattern computed at runtime that is outside the
subset is false, never an error.

## Translation table

The Dart form differs from the source only where Dart means something else than S-L7.

| Source | Dart form | Why |
|---|---|---|
| `.` | `[^\n\r\u0085  ]` | Dart's `.` matches U+0085; S-L7's does not |
| `.` after a leading `(?s)` | `[^]` | Dart has no inline `(?s)` ("Invalid group") |
| leading `(?s)` | removed | applied by the `.` rewrite above |
| `\s`, `\S` | `[ \t\n\x0B\f\r]`, `[^ \t\n\x0B\f\r]` | Dart's `\s` is Unicode and matches U+00A0; S-L7's is ASCII |
| `\s` in a class | its members spliced into the class | as above |
| `[a\S]`, `[^a\S]` | `(?:[a]\|[^ \t\n\x0B\f\r])`, `(?:(?![a])[ \t\n\x0B\f\r])` | a class cannot hold the complement of a set inside it |
| `\!`, `\_` and other escaped ASCII punctuation Dart refuses | the bare character | `unicode: true` rejects identity escapes of non-syntax characters ("Invalid escape") |
| `\-` outside a class | `-` | as above; inside a class `\-` is kept |
| a literal terminal | `RegExp.escape(text)` | its output is valid under `unicode: true` |
| default whitespace (S-L4) | `[ \t\n\x0B\f\r]+` | S-L7 `\s+` |

Unchanged, because Dart already means what S-L7 says:

- `^` and `$`, the start and end of the text matched. Without `multiLine`, Dart's `$` does not match before a final
  newline, which is S-L7's meaning (Java's `$` does, so Java translates it; Dart need not).
- `\d`, `\D`, `\w`, `\W`, `\b`, `\B`, which are ASCII in Dart under `unicode: true` (`\w` does not match `é`, `\d`
  does not match U+0663).
- `\p{C}` and `\P{C}` for the 37 general categories, `\xHH`, `\uHHHH`, `\n`, `\r`, `\t`, `\f`.
- Lazy quantifiers and the counted forms `{n}`, `{n,}`, `{n,m}`.
- Lookahead and lookbehind. Dart allows unbounded lookbehind.
- `.` over a surrogate pair matches one code point under `unicode: true`.

## Matching in the lexer

The lexer matches each lexeme with `pattern.matchAsPrefix(input, position)`. That gives the transparent,
non-anchoring bounds S-L7 asks for: lookbehind and `\b` see the input before the token, and `^` means the start of the
whole input, not of the token. libugf 1.x emulated Java's opaque, anchoring region bounds instead; 2.0 reverses those
decisions, as the cases below show.

## Corpus cases

The synced corpus checks the subset through `lexical-regex-*`, and the ports through their grammars. The Dart-only
cases in `test/corpus/dart/` (bundled into `dart.g.dart` by `tool/bundle_cases.dart`) are the 1.x `regex-*` cases,
rewritten with expectations from S-L7:

| Case | S-L7 reading |
|---|---|
| `regex-absolute-anchors`, `regex-atomic-group`, `regex-class-intersection`, `regex-horizontal-space`, `regex-inline-flag`, `regex-posix-class`, `regex-possessive`, `regex-quote` | outside the subset: the grammar does not compile |
| `regex-caret-anchor` | `^` is the start of the input, so it does not match after a token |
| `regex-word-boundary` | `\b` sees the input before the token |
| `regex-lookbehind` | lookbehind sees the input before the token |
| `regex-whitespace-class`, `regex-whitespace-skip` | `\s` and the default whitespace are ASCII, so U+00A0 is neither |
| `regex-surrogate-dot` | `.` matches one code point |
| `regex-unicode-property` | `\p{L}` includes `é` |
| `regex-alternation-order` | alternation takes the first option that leads to a match, as every engine the subset is portable across does |
| `regex-alternation` | a lexeme's elements form one pattern, so alternation backtracks into the next element |
