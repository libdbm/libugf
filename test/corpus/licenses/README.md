# Port grammar licences

The port grammars in `../ports/` are derived from [antlr/grammars-v4](https://github.com/antlr/grammars-v4) at commit `7df52be9`, as each port's `NOTICE.md` records. Most NOTICE files state the licence but not its text, so this directory holds the text (SPEC D11): for each port, everything before the `grammar` declaration of each source `.g4` file its NOTICE names, copied verbatim apart from `// $antlr-format` lines, and for `toml` the repository's `toml/LICENSE`.

`tool/sync_corpus.dart` does not manage this directory. A port added by a sync needs its files here; `test/corpus/licenses_test.dart` fails until they are.

| Port | Licence | Files |
|---|---|---|
| abnf, arithmetic, c, calculator, csv, dot, golang, inf, java, pascal, prolog, rfc1035, tiny, tinyc, url | BSD 3-clause | the `.g4` headers |
| erlang, turtle | BSD 3-clause | the `.g4` headers; the warranty disclaimer ends mid-sentence in the source file itself |
| sexpression | MIT | the `.g4` header, with the full permission notice |
| bnf, lua | MIT | the `bnfParser.g4` and `LuaParser.g4` headers, which name the licence and author but carry no copyright line or permission text; `bnfLexer.g4` and `LuaLexer.g4` have no header |
| json5 | Public domain | the `.g4` header |
| toml | Apache 2.0 | the `.g4` headers and `LICENSE` |

The gaps (bnf and lua without the MIT text, erlang and turtle with a truncated disclaimer) are in the sources and are raised upstream (SPEC section 8). Four ports with no confirmed licence (`clojure`, `json`, `properties`, `smalltalk`) are not synced at all; see `../SOURCE`.
