import 'dart:convert';

import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

import '../corpus/corpus.g.dart';

/// Every synced grammar loads, or fails with `grammar.syntax`, as its
/// `expected.json` says; and the constraints of every loaded rule convert to
/// a plan unless the case expects a validation error (Java
/// `PlanConversionTests.testEveryResourceGrammarConverts`).
void main() {
  final web = identical(1, 1.0);

  for (final MapEntry(key: name, value: files) in cases.entries) {
    test(name, () {
      final expected =
          (jsonDecode(files['expected.json']!) as Map)['grammar'] as Map;
      final result = GrammarLoader.unvalidated(files['grammar.ug']!);
      if (expected['error'] == 'syntax') {
        expect(
          (result as Failure<Grammar, ErrorDetails>).error.code,
          'grammar.syntax',
        );
        return;
      }
      // On the web an integer literal beyond 2^53 - 1 is a load error (D5).
      if (result case Failure(:final error)
          when web &&
              error.issues.every((issue) => issue.contains('out of range'))) {
        return;
      }
      final grammar = result.orElseThrow();
      if (expected['ok'] == true) {
        for (final rules in grammar.rules.values) {
          for (final rule in rules) {
            expect(
              Plan.of(rule.constraints),
              isA<Success<Plan, ErrorDetails>>(),
              reason: '$rule',
            );
          }
        }
      }
    });
  }
}
