@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// The public API (R-PUB-2). The analyzer's `public_member_api_docs` checks
/// the dartdoc; this checks the class modifiers.
void main() {
  test('testEveryClassHasAModifier', () {
    // A class declared with `class` or `abstract class` alone may be
    // extended, implemented and mixed in anywhere.
    final open = RegExp(r'^(abstract )?class ', multiLine: true);
    final found = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          for (final match in open.allMatches(file.readAsStringSync()))
            '${file.path}: ${file.readAsStringSync().substring(match.start).split('\n').first}',
    ];

    expect(found, isEmpty);
  });
}
