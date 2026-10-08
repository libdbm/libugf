@TestOn('vm')
library;

import 'dart:io';

import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';
import 'package:libugf/src/parser/parser.dart' show raw;
import 'package:test/test.dart';

/// The port-sample half of Java `IdentityTests#testCanonicalMergingChangesNoResult`:
/// every valid and invalid sample of every port whose grammar compiles
/// parses the same with raw and canonical keys (S-P9).
void main() {
  test('testCanonicalMergingChangesNoPortResult', () {
    var compared = 0;
    final ports =
        Directory('test/corpus/ports')
            .listSync()
            .whereType<Directory>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final port in ports) {
      final compiled = GrammarFiles.parseWithImports(
        '${port.path}/grammar.ug',
      ).flatMap((grammar) => Compiler.compile(grammar, Predicates.standard()));
      if (compiled case Success(value: final grammar)) {
        for (final folder in ['valid', 'invalid']) {
          final directory = Directory('${port.path}/$folder');
          if (!directory.existsSync()) {
            continue;
          }
          final files = directory.listSync().whereType<File>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));
          for (final file in files) {
            final text = file.readAsStringSync();
            final canonical = Parser.of(grammar).parse(text);
            final plain = raw(grammar).parse(text);
            final label = file.path;
            expect(plain.outcome, canonical.outcome, reason: label);
            expect(plain.penalty, canonical.penalty, reason: label);
            expect(plain.ambiguous, canonical.ambiguous, reason: label);
            expect(plain.tree, canonical.tree, reason: label);
            compared++;
          }
        }
      }
    }
    printOnFailure('compared $compared port samples');
    // With the corpus inputs, more than 400, as in Java.
    expect(compared, greaterThanOrEqualTo(361));
  });
}
