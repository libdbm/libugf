@TestOn('browser')
library;

import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

/// Compiling this for the web fails if `package:libugf/libugf.dart` imports
/// `dart:io`, directly or through any library it exports (SPEC D8).
void main() {
  test('testCoreLoadsWithoutFiles', () {
    final grammar = GrammarLoader.parseWithImports(
      Sources.memory({
        'main.ug': 'import "x.ug"; start S; S --> X;',
        'x.ug': "X --> 'x';",
      }),
      'main.ug',
    ).orElseThrow();

    expect(grammar.rulesFor('X'), isNotEmpty);
  });
}
