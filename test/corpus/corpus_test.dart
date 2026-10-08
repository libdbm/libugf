import 'dart:convert';

import 'package:test/test.dart';

import 'adapter.dart';
import 'corpus.g.dart';
import 'dart.g.dart';
import 'pending.dart';
import 'runner.dart';

/// Cases whose grammar cannot load where integers are doubles (dart2js),
/// as SPEC D5 documents: the result there is a `syntax` load error.
const doubles = {
  // Its weight 2^63 - 1 is beyond 2^53 - 1.
  'constraint-penalty-overflow',
};

/// Runs the conformance corpus (SPEC section 4), from the generated
/// `corpus.g.dart` so it runs on every platform.
void main() {
  final waiting = entries(pending);

  group('corpus', () {
    for (final MapEntry(key: name, value: files) in cases.entries) {
      test(name, () {
        if (identical(0, 0.0) && doubles.contains(name)) {
          expect(actual(files)['grammar'], {'ok': false, 'error': 'syntax'});
          return;
        }
        switch (verdict(check(files, actual), waiting[name])) {
          case Passed():
            break;
          case Failed(:final message):
            fail(message);
          case Skipped(:final reason):
            markTestSkipped(reason);
        }
      });
    }
  });

  // The Dart-only cases (D12), written from SEMANTICS.md; none is pending.
  group('dart', () {
    for (final MapEntry(key: name, value: files) in dartCases.entries) {
      test(name, () {
        switch (verdict(check(files, actual), null)) {
          case Passed():
            break;
          case Failed(:final message):
            fail(message);
          case Skipped(:final reason):
            markTestSkipped(reason);
        }
      });
    }
  });

  test('testPendingEntriesNameExistingCases', () {
    expect(waiting.keys.where((name) => !cases.containsKey(name)), isEmpty);
  });

  /// Every rule in SEMANTICS.md is exercised by a case or exempted with a
  /// reason (Java SEM-4).
  test('testEveryRuleCovered', () {
    final defined = rules(semantics);
    final covered = {
      ...entries(exempt).keys,
      for (final files in cases.values)
        for (final rule
            in (jsonDecode(files['case.json']!)
                    as Map<String, Object?>)['rules']
                as List<Object?>)
          rule as String,
    };
    expect(
      defined.difference(covered),
      isEmpty,
      reason: 'rules without a case or exemption',
    );
    expect(
      covered.difference(defined),
      isEmpty,
      reason: 'cases or exemptions naming unknown rules',
    );
  });
}
