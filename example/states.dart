// Lexical states (example/states.ug): words, a code span lexed in state
// CODE, and a skipped comment.
// Run from the package root: dart run example/states.dart
import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';

void main() {
  final parser = GrammarFiles.parse('example/states.ug')
      .flatMap((grammar) => ParserFactory.create(grammar))
      .orElseThrow();
  // example: states
  final result = parser.parse('see `x + 1` here # a comment');

  print(result.tree!.display());
  // end example
}
