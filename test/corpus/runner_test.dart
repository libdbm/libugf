import 'package:test/test.dart';

import 'runner.dart';

void main() {
  group('inputs', () {
    test('testOneInputPerLineWithoutTrailingEmptyLine', () {
      expect(inputs('a\nb\n'), ['a', 'b']);
    });

    test('testEmptyLinesInsideAreInputs', () {
      expect(inputs('a\n\nb\n'), ['a', '', 'b']);
      expect(inputs('\n'), ['']);
      expect(inputs(''), <String>[]);
    });

    test('testEscapes', () {
      expect(
        inputs(
          r'a\nb\tc\rd\\e\qf'
          '\n',
        ),
        ['a\nb\tc\rd\\e\\qf'],
      );
    });

    test('testTrailingBackslashKept', () {
      expect(inputs('a\\\n'), ['a\\']);
    });
  });

  group('entries', () {
    test('testNamesAndOwnersWithComments', () {
      expect(
        entries(
          '# heading\ncase-a Task 17\n\ncase-b   # comment\n  case-c x y\n',
        ),
        {'case-a': 'Task 17', 'case-b': 'unassigned', 'case-c': 'x y'},
      );
    });
  });

  group('rules', () {
    test('testRuleIdsFromSemantics', () {
      const text = '''
- **S-G1.** A rule.
- **S-L2a.** Another.
  - **S-X9.** Indented, not a rule.
Text - **S-P1.** inline, not a rule.
- **S-C10.** Ten.
''';
      expect(rules(text), {'S-G1', 'S-L2a', 'S-C10'});
    });
  });

  group('compare', () {
    test('testMapsMatchByNamedKeys', () {
      expect(compare({'a': 1}, {'a': 1, 'b': 2}), isEmpty);
      expect(compare({'a': 1}, {'b': 2}), [r'$.a: missing']);
    });

    test('testListsMatchByLengthAndElement', () {
      expect(compare([1, 2], [1, 2]), isEmpty);
      expect(compare([1, 2], [1]), [r'$: expected [1,2] but was [1]']);
      expect(
        compare(
          [
            {'a': 1},
          ],
          [
            {'a': 2},
          ],
        ),
        [r'$[0].a: expected 1 but was 2'],
      );
    });

    test('testScalarsAndShapes', () {
      expect(compare('x', 'x'), isEmpty);
      expect(compare(null, null), isEmpty);
      expect(compare(true, false), [r'$: expected true but was false']);
      expect(compare({'a': 1}, [1]), [r'$: expected an object but was [1]']);
    });
  });

  group('check', () {
    Map<String, String> files(String expected) => {
      'grammar.ug': 'start S;',
      'inputs.txt': 'a\nb\n',
      'case.json': '{"rules": ["S-G1"]}',
      'expected.json': expected,
    };

    Map<String, Object?> adapter(Map<String, String> files) => {
      'grammar': {'ok': true},
      'inputs': [
        {'input': 'a', 'outcome': 'accepted', 'penalty': 0},
        {'input': 'b', 'outcome': 'rejected'},
      ],
    };

    test('testMatchingCasePasses', () {
      expect(
        check(
          files(
            '{"grammar": {"ok": true}, "inputs": '
            '[{"outcome": "accepted"}, {"outcome": "rejected"}]}',
          ),
          adapter,
        ),
        isEmpty,
      );
    });

    test('testInputCountMustMatch', () {
      expect(
        check(files('{"inputs": [{"outcome": "accepted"}]}'), adapter),
        contains('expected.json has 1 inputs but inputs.txt has 2'),
      );
    });

    test('testActualIsNormalizedThroughJson', () {
      Map<String, Object?> typed(Map<String, String> files) => {
        'grammar': {'ok': true},
        'inputs': <Object?>[
          {'penalty': 3},
          {'penalty': 4},
        ],
      };
      expect(
        check(files('{"inputs": [{"penalty": 3}, {"penalty": 4}]}'), typed),
        isEmpty,
      );
    });
  });

  group('verdict', () {
    test('testPassingCase', () {
      expect(verdict([], null), isA<Passed>());
    });

    test('testFailingCase', () {
      expect(verdict(['x'], null), isA<Failed>());
    });

    test('testPendingCaseThatFailsIsSkipped', () {
      final result = verdict(['first', 'second'], 'Task 17');
      expect(result, isA<Skipped>());
      expect((result as Skipped).reason, 'Pending on Task 17: first');
    });

    test('testPendingCaseThatPassesFails', () {
      final result = verdict([], 'Task 17');
      expect(result, isA<Failed>());
      expect(
        (result as Failed).message,
        'Pending case now passes; remove it from pending.dart (owner: Task 17)',
      );
    });
  });
}
