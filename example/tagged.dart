// Tokens from an external tagger (example/tagged.ug).
// Run from the package root: dart run example/tagged.dart
import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';

void main() {
  final parser = GrammarFiles.parse('example/tagged.ug')
      .flatMap((grammar) => ParserFactory.create(grammar))
      .orElseThrow();
  // example: tokens
  final plural = Structure.of({'num': const StringConstant('pl')});
  final tokens = [
    [Token('dogs', plural, 0, 4, 'Noun')],
    [Token('bark', plural, 5, 9, 'Verb'), Token('bark', plural, 5, 9, 'Noun')],
  ];

  final graph = TokenSource.alternatives(tokens).tokenize('dogs bark');
  final result = graph.flatMap(parser.parseGraph).orElseThrow();
  // end example

  print('${result.outcome.name}, ambiguous: ${result.ambiguous}');
}
