@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

import '../corpus/corpus.g.dart';

/// S-N1 as a property, as Java `GrammarGeneratorTests#testRoundTripProperty`:
/// every generated sentence parses, for math.ug, simple.ug and every port
/// that generates.
void main() {
  test('testRoundTripProperty', () {
    final grammars = <String, Grammar>{
      'math.ug': GrammarFiles.parse('test/resources/math.ug').orElseThrow(),
      'simple.ug': GrammarLoader.parse(
        cases['review-simple-tokenization']!['grammar.ug']!,
      ).orElseThrow(),
      for (final port
          in (Directory('test/corpus/ports')
              .listSync()
              .whereType<Directory>()
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path))))
        port.path: GrammarFiles.parseWithImports('${port.path}/grammar.ug')
            .orElseThrow(),
    };
    var generated = 0;
    for (final MapEntry(key: name, value: grammar) in grammars.entries) {
      final parser = ParserFactory.create(grammar).orElseThrow();
      final sentences = GrammarGenerator.builder(grammar)
          .random(Random(11))
          .policy(Policy.defaults.copy(depth: 12))
          .build()
          .orElseThrow()
          .generate(grammar.start, Structure.empty, 20)
          .orElse(const []);
      for (final sentence in sentences) {
        expect(
          parser.parse(sentence).outcome,
          Outcome.accepted,
          reason: '$name: $sentence',
        );
        generated++;
      }
    }
    expect(generated, greaterThan(100));
  });
}
