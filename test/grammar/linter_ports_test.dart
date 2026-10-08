@TestOn('vm')
library;

import 'dart:io';

import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

/// The linter reports no errors on any port grammar, loaded with its
/// imports but not validated.
void main() {
  test('testNoErrorsOnPortGrammars', () {
    final ports = Directory('test/corpus/ports')
        .listSync()
        .whereType<Directory>();
    for (final port in ports) {
      final loaded = GrammarFiles.unvalidated('${port.path}/grammar.ug')
          .flatMap(
            (grammar) => ModuleResolver(const FileSources(), [
              port.path,
            ]).resolve(grammar, port.path),
          );

      expect(
        GrammarLinter().lint(loaded.orElseThrow()).errors,
        isEmpty,
        reason: port.path,
      );
    }
    expect(ports, hasLength(22));
  });
}
