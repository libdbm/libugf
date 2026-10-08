import 'package:libugf/libugf.dart';
import 'package:libugf/src/parser/session.dart' show collectors;
import 'package:test/test.dart';

const on = Options(limits: Limits.none, diagnostics: true);

Parser parser(String source, [Options options = on, Predicates? predicates]) =>
    Parser.of(
      Compiler.compile(
        GrammarLoader.unvalidated(source).orElseThrow(),
        predicates ?? Predicates.standard(),
      ).orElseThrow(),
      options,
    );

Structure number(String value) => Structure.of({'num': StringConstant(value)});

/// Ported from Java `ParseDiagnosticsTests`, the diagnostics scenarios of
/// `ParserScenarioTests` and the diagnostics tests of `OptionsTests` at
/// unifica 8d8c01a. Java's `record...` methods with positional details take
/// the record objects here.
void main() {
  group('records', () {
    late ParseDiagnostics diagnostics;

    setUp(() => diagnostics = ParseDiagnostics());

    test('testInitialState', () {
      expect(diagnostics.hasFailures, isFalse);
      expect(diagnostics.constraints, isEmpty);
      expect(diagnostics.tokenizations, isEmpty);
      expect(diagnostics.issues, isEmpty);
      expect(diagnostics.unifications, isEmpty);
    });

    test('testRecordsConstraintFailures', () {
      diagnostics
        ..recordConstraint(
          const ConstraintFailure('rule1', 'test()', 'mismatch', 5),
        )
        ..recordConstraint(
          const ConstraintFailure(
            'rule2',
            'soft()',
            'preference',
            10,
            hard: false,
          ),
        );

      expect(diagnostics.hasFailures, isTrue);
      final hard = diagnostics.constraints.first;
      expect(
        (hard.rule, hard.expression, hard.reason, hard.position, hard.hard),
        ('rule1', 'test()', 'mismatch', 5, true),
      );
      expect(hard.span, isNull);
      expect(diagnostics.constraints.last.hard, isFalse);
    });

    test('testRecordsTokenizationAndIssues', () {
      diagnostics
        ..recordTokenization(const TokenizationError(15, '@#\$', 'identifier'))
        ..recordIssue(const ParsingIssue('unexpected end of input', 100));

      final error = diagnostics.tokenizations.single;
      expect(
        (error.position, error.input, error.expected),
        (15, '@#\$', 'identifier'),
      );
      final issue = diagnostics.issues.single;
      expect((issue.message, issue.position), ('unexpected end of input', 100));
    });

    test('testRecordsUnificationFailures', () {
      final span = const Span(1, 4, 7);
      diagnostics
        ..recordUnification(
          UnificationFailure(
            'NP',
            number('sg'),
            number('pl'),
            number('sg'),
            'conflict',
            5,
            span,
          ),
        )
        ..recordUnification(
          UnificationFailure(
            'VP',
            Structure.empty,
            Structure.empty,
            Structure.empty,
            'r',
            2,
          ),
        );

      final failure = diagnostics.unifications.first;
      expect(failure.symbol, 'NP');
      expect(failure.waiting, number('sg'));
      expect(failure.completed, number('pl'));
      expect(failure.expected, number('sg'));
      expect(failure.span, span);
      expect(diagnostics.unifications, hasLength(2));
    });

    test('testListsAreUnmodifiable', () {
      diagnostics.recordIssue(const ParsingIssue('test', 0));

      expect(() => diagnostics.issues.clear(), throwsUnsupportedError);
    });
  });

  group('report', () {
    late ParseDiagnostics diagnostics;

    setUp(() => diagnostics = ParseDiagnostics());

    test('testEmptyReport', () {
      expect(diagnostics.report(), contains('No failures recorded'));
    });

    test('testConstraintReport', () {
      diagnostics
        ..recordConstraint(
          const ConstraintFailure('np', 'eq()', 'number mismatch', 5),
        )
        ..recordConstraint(
          const ConstraintFailure('vp', 'prefer()', 'style', 10, hard: false),
        )
        ..recordConstraint(
          const ConstraintFailure('r', 'eq()', 'why', 2, span: Span(2, 7, 12)),
        );

      final report = diagnostics.report();
      expect(report, contains('Constraint Failures'));
      expect(report, contains('[HARD]'));
      expect(report, contains('[SOFT]'));
      expect(report, contains('number mismatch'));
      expect(report, contains('chars 7..12'));
    });

    test('testComprehensiveReport', () {
      diagnostics
        ..recordConstraint(
          const ConstraintFailure('r1', 'test()', 'reason1', 1),
        )
        ..recordTokenization(const TokenizationError(2, 'bad', 'good'))
        ..recordIssue(const ParsingIssue('ambiguous parse', 25))
        ..recordUnification(
          UnificationFailure(
            'S',
            number('sg'),
            number('pl'),
            number('sg'),
            "Feature 'num' incompatible",
            6,
          ),
        );

      final report = diagnostics.report();
      for (final text in [
        'Constraint Failures',
        'Tokenization Errors',
        'bad',
        'good',
        'Parsing Issues',
        'ambiguous parse',
        '25',
        'Feature Unification Failures',
        "Feature 'num' incompatible",
        'Expected:',
        'Waiting:',
        'Completed:',
      ]) {
        expect(report, contains(text));
      }
      expect(report, isNot(contains('No failures recorded')));
    });

    test('testLatticeRecordedAndRendered', () {
      const span = Span(1, 4, 7);
      const item = LatticeItem('S → NP • VP', 1, 0, 0, ItemState.active, '{}');
      final lattice = Lattice(
        [
          Column(1, span, [item], ['VP'], [
            const PathFailure(
              item,
              span,
              'blocked waiting for VP',
              Cause.deadEnd,
            ),
          ]),
        ],
        1,
        span,
      );

      diagnostics.lattice = lattice;

      expect(diagnostics.lattice, same(lattice));
      expect(lattice.failures, hasLength(1));
      expect(diagnostics.hasFailures, isTrue);
      final rendered = lattice.render();
      expect(rendered, contains('=== Parse Lattice ==='));
      expect(rendered, contains('Furthest progress: column 1'));
      expect(rendered, contains('expected: VP'));
      expect(rendered, contains('[DEAD_END]'));
      expect(rendered, contains('chars 4..7'));
      expect(diagnostics.report(), contains('=== Parse Lattice ==='));
    });
  });

  group('parsing', () {
    test('testDiagnosticsOffByDefault', () {
      final before = collectors;

      final result = parser(
        "start S; S --> N{num: \$X} V{num: \$X}; N{num: sg} --> 'dog'; V{num: pl} --> 'run';",
        const Options(),
      ).parse('dog run');

      expect(result.diagnostics, isNull);
      expect(collectors, before);
    });

    test('testRecordsConstraintFailures', () {
      var called = false;
      final predicates = Predicates.builder().builtins().add(
        'always_fails',
        0,
        0,
        Phase.syntactic,
        (environment, args) {
          called = true;
          return false;
        },
      ).build();

      final result = parser(
        "start S; WORD --> 'test'; S --> WORD where always_fails();",
        on,
        predicates,
      ).parse('test');

      expect(called, isTrue);
      expect(result.success, isFalse);
      expect(result.hasConstraintFailures, isTrue);
      final failure = result.diagnostics!.constraints.first;
      expect(failure.rule, 'S');
      expect(failure.hard, isTrue);
      expect(failure.reason, contains('always_fails()'));
      expect(result.toString(), contains('Constraint Failures'));
      expect(
        result.diagnostics!.lattice!.failures.any(
          (path) => path.cause == Cause.constraint,
        ),
        isTrue,
      );
    });

    test('testRecordsUnificationFailure', () {
      final result = parser(
        "start S; S --> NP{num: \$N} VP{num: \$N}; NP{num: sg} --> 'cat'; VP{num: pl} --> 'run';",
      ).parse('cat run');

      expect(result.success, isFalse);
      final failure = result.diagnostics!.unifications.first;
      expect(failure.reason, contains('num'));
      // 'run' spans characters 4 to 7.
      expect((failure.span!.start, failure.span!.end), (4, 7));
      expect(
        result.diagnostics!.report(),
        contains('Feature Unification Failures'),
      );
    });

    test('testRecordsTokenizationErrors', () {
      final result = parser("start S; S --> 'a' 'b';").parse('a#b');

      final error = result.diagnostics!.tokenizations.single;
      expect((error.input, error.position), ('#', 1));
    });

    test('testDeadEndInLattice', () {
      final result = parser("start S; S --> 'a' 'b' 'c';").parse('a b');

      final lattice = result.diagnostics!.lattice!;
      final dead = [
        for (final path in lattice.failures)
          if (path.cause == Cause.deadEnd) path,
      ];
      expect(dead, isNotEmpty);
      expect(dead.first.reason, contains("'c'"));
      expect(lattice.furthest, 2);
      expect(lattice.position, isNotNull);
      final report = result.diagnostics!.report();
      expect(report, contains('=== Parse Lattice ==='));
      expect(report, contains('Furthest progress'));
    });

    test('testSuccessHasNoLattice', () {
      final result = parser("start S; S --> 'a';").parse('a');

      expect(result.success, isTrue);
      expect(result.diagnostics!.lattice, isNull);
      expect(result.diagnostics!.ambiguities, isEmpty);
    });

    test('testDiagnosticsNameTheTie', () {
      final result = parser(
        "start s; s --> y 'z'; y --> x x; x --> 'a'; x --> 'a' 'a';",
      ).parse('a a a z');

      final ambiguities = result.diagnostics!.ambiguities;
      expect(ambiguities, isNotEmpty);
      expect(ambiguities.first.symbol, 'y');
      expect(result.diagnostics!.report(), contains('=== Ambiguities ==='));
    });

    test('testDiagnosticsCapped', () {
      final result = parser(
        "start S; S --> N{num: \$X} V{num: \$X}; N{num: sg} --> 'dog'; V{num: pl} --> 'run';",
        Options(limits: Limits.none.copy(diagnostics: 1), diagnostics: true),
      ).parse('dog run dog run');

      final diagnostics = result.diagnostics!;
      expect(
        diagnostics.unifications.length +
            diagnostics.issues.length +
            diagnostics.tokenizations.length,
        1,
      );
    });

    test('testLatticeBounded', () {
      final result = parser(
        "start S; S --> S S; S --> A; A --> 'a'; B --> 'b';",
        Options(limits: Limits.none.copy(diagnostics: 5), diagnostics: true),
      ).parse('${List.filled(20, 'a').join(' ')} b');

      expect(result.outcome, Outcome.rejected);
      final lattice = result.diagnostics!.lattice!;
      final items = lattice.columns.fold(
        0,
        (sum, column) => sum + column.items.length,
      );
      expect(items, lessThanOrEqualTo(5));
      expect(lattice.truncated, isTrue);
      expect(lattice.render(), contains('truncated'));
    });

    test('testLatticePenaltyNotClamped', () {
      final result = parser(
        "start S; S --> A B; A --> X @3000000000; X --> 'a'; B --> 'b';",
      ).parse('a');

      expect(result.outcome, Outcome.rejected);
      expect(
        result.diagnostics!.lattice!.columns.any(
          (column) => column.items.any((item) => item.penalty == 3000000000),
        ),
        isTrue,
      );
    });
  });
}
