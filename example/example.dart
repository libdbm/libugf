// The quick start: load example/arithmetic.ug, compile it and parse.
// Run from the package root: dart run example/example.dart
import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';

void main() {
  // example: quickstart
  final parser = GrammarFiles.parse('example/arithmetic.ug')
      .flatMap((grammar) => ParserFactory.create(grammar))
      .orElseThrow();
  final result = parser.parse('2 * (3 + 4)');

  if (result.success) {
    print(result.tree!.display());
  }
  // end example
}
