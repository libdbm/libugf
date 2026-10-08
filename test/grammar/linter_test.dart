import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

import '../corpus/corpus.g.dart';

final linter = GrammarLinter();

Grammar grammar(String source) =>
    GrammarLoader.unvalidated(source).orElseThrow();

LintReport lint(String source) => linter.lint(grammar(source));

List<LintIssue> issues(String source, String title, [GrammarLinter? using]) => [
  for (final issue in (using ?? linter).lint(grammar(source)).issues)
    if (issue.title == title) issue,
];

/// Ported from Java `GrammarLinterTests` at unifica 8d8c01a. Grammars Java
/// builds by hand are written as grammar text where the text says the same;
/// the builder remains where only it can (a state annotation or transition
/// on a syntactic rule).
void main() {
  group('reachability', () {
    test('testNoIssuesWithValidGrammar', () {
      final report = lint("start S; S --> 'hello';");

      expect(report.hasErrors, isFalse);
      expect(report.hasWarnings, isFalse);
      expect(report.issues, isEmpty);
    });

    test('testEmptyGrammarLint', () {
      expect(linter.lint(Grammar.builder().build()).issues, isEmpty);
    });

    test('testDetectsUnreachableRule', () {
      final report = lint(
        "start S; S --> 'hello'; X --> Y 'world'; Y --> 'test';",
      );

      expect(report.warnings, hasLength(1));
      expect(report.warnings.single.title, 'Unreachable rule');
      expect(report.warnings.single.message, contains("'X'"));
    });

    test('testReachabilityThroughNonterminals', () {
      final report = lint(
        "start S; S --> NP VP; NP --> 'the' N; N --> 'dog'; VP --> 'barks';"
        " X --> Z 'test'; Z --> 'z';",
      );

      expect(report.warnings, hasLength(1));
      expect(report.warnings.single.message, contains("'X'"));
    });

    test('testReachabilityThroughGroup', () {
      expect(
        issues(
          "start S; S --> ('a' T) 'b'; T --> 'q' 'r';",
          'Unreachable rule',
        ),
        isEmpty,
      );
    });
  });

  group('duplicates', () {
    test('testDuplicateLexicalEntries', () {
      final information = [
        for (final issue in lint(
          "start S; S --> T1 T2; T1 --> 'hello'; T2 --> 'hello';",
        ).issues)
          if (issue.severity == Severity.info) issue,
      ];

      expect(information, hasLength(1));
      expect(information.single.message, contains("'hello'"));
      expect(information.single.message, contains('T1'));
      expect(information.single.message, contains('T2'));
    });

    test('testDuplicateRegexLexicalEntries', () {
      final information = issues(
        'start S; S --> N1 N2; N1 --> [0-9]+; N2 --> [0-9]+;',
        'Duplicate lexical entry',
      );

      expect(information, hasLength(1));
      expect(information.single.message, contains('/[0-9]+/'));
    });
  });

  group('labels', () {
    test('testDetectsUnboundLabelInConstraint', () {
      final report = lint(
        "start S; S --> NP:subj VP where agree(subj, unbound); NP --> 'n'; VP --> 'v';",
      );

      expect(report.errors, hasLength(1));
      expect(report.errors.single.title, 'Unbound label in constraint');
      expect(report.errors.single.message, contains('unbound'));
    });

    test('testConstraintWithBoundLabels', () {
      expect(
        lint(
          "start S; S --> NP:subj VP:pred where agree(subj, pred); NP --> 'n'; VP --> 'v';",
        ).hasErrors,
        isFalse,
      );
    });

    test('testComplexConstraintWithMultipleVariables', () {
      final report = lint(
        "start S; S --> A:a B:b where (equals(a, b) | !equals(a, unbound)), equals(b, 'x');"
        " A --> 'a'; B --> 'b';",
      );

      expect(
        report.errors.any((issue) => issue.message.contains('unbound')),
        isTrue,
      );
    });

    test('testLabelledTokensAreBound', () {
      expect(
        lint("start S; S --> 'hello':h A where equals(h, 'hello'); A --> 'a';")
            .hasErrors,
        isFalse,
      );
      expect(
        lint("start S; S --> [0-9]+:n A where equals(n, '1'); A --> 'a';")
            .hasErrors,
        isFalse,
      );
    });

    test('testImplicitlyBoundNames', () {
      expect(
        lint("start S; S --> A where equals(S, 'a'); A --> 'a';").hasErrors,
        isFalse,
      );
      expect(
        lint("start S; S --> A B where equals(A, B); A --> 'a'; B --> 'b';")
            .hasErrors,
        isFalse,
      );
    });

    test('testFeatureVariablesAreBoundInConstraints', () {
      const title = 'Unbound label in constraint';

      expect(
        issues(
          "start S; S --> N{num: \$X} V{num: \$Y} where equals(\$X, \$Y); N --> 'n'; V --> 'v';",
          title,
        ),
        isEmpty,
      );
      expect(
        issues(
          "start S; S{n: \$Z} --> N where is_bound(\$Z); N --> 'n';",
          title,
        ),
        isEmpty,
      );
      expect(
        issues(
          "start S; S --> (N{m: {k: \$W}})? where is_bound(\$W); N --> 'n';",
          title,
        ),
        isEmpty,
      );
      expect(
        issues(
          "start S; S --> N{num: \$X} where is_bound(\$Q); N --> 'n';",
          title,
        ),
        hasLength(1),
      );
      // A variable is named with its '$' in a constraint; a bare name is a
      // label or symbol.
      expect(
        issues(
          "start S; S --> N{num: \$X} where is_bound(X); N --> 'n';",
          title,
        ),
        hasLength(1),
      );
    });
  });

  group('nonterminals', () {
    test('testDetectsUndefinedNonterminal', () {
      final report = lint('start S; S --> UndefinedSymbol;');

      expect(report.errors, hasLength(1));
      expect(report.errors.single.title, 'Undefined nonterminal');
      expect(report.errors.single.message, contains('UndefinedSymbol'));
    });

    test('testUndefinedNonterminalInGroups', () {
      expect(
        lint("start S; S --> (A | UndefinedB); A --> 'a';").errors
            .any((issue) => issue.message.contains('UndefinedB')),
        isTrue,
      );
      expect(
        lint('start S; S --> UndefinedX*;').errors
            .any((issue) => issue.message.contains('UndefinedX')),
        isTrue,
      );
      final errors = issues(
        "start S; S --> ('a' Missing) 'b';",
        'Undefined nonterminal',
      );
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('Missing'));
    });
  });

  group('states', () {
    test('testDetectsStateTransitionOnNonLexicalRule', () {
      final built = Grammar.builder()
          .start('S')
          .add(
            GrammarRule(
              LHS('S'),
              [const Terminal('if'), Nonterminal('EXPR')],
              kind: Kind.syntactic,
              transition: 'IF_STATE',
            ),
          )
          .add(GrammarRule.simple('EXPR', const [Terminal('true')]))
          .build();

      expect(
        linter
            .lint(built)
            .errors
            .any(
              (issue) =>
                  issue.title.contains('State transition on non-lexical'),
            ),
        isTrue,
      );
    });

    test('testDetectsStateAnnotationInNonLexicalRule', () {
      for (final rhs in [
        [const StateAnnotation('STATE'), Nonterminal('NP')],
        [
          Sequence([const StateAnnotation('STATE'), Nonterminal('NP')]),
        ],
      ]) {
        final built = Grammar.builder()
            .start('S')
            .add(GrammarRule.simple('S', rhs))
            .add(GrammarRule.simple('NP', const [Terminal('the')]))
            .build();

        expect(
          linter
              .lint(built)
              .errors
              .any(
                (issue) =>
                    issue.title.contains('State annotation in non-lexical'),
              ),
          isTrue,
        );
      }
    });

    test('testAllowsStatesInLexicalRules', () {
      expect(lint("start S; S --> O; O --> '<' ==> IN;").hasErrors, isFalse);
      expect(lint("start S; S --> A; A --> {IN} 'a';").hasErrors, isFalse);
      expect(
        lint("start S; S --> A; A --> 'a' where in_state('IN');").hasErrors,
        isFalse,
      );
      expect(
        lint(
          "start S; S --> K; K --> ('if' | 'while' | 'for') ==> KEYWORD_STATE;",
        ).hasErrors,
        isFalse,
      );
    });

    test('testLexicalPredicatesAllowedInSyntacticRule', () {
      // S-C7: a lexical predicate in a syntactic rule reads the state and
      // offset where the constituent starts; the 1.x linter warned about it.
      expect(
        lint(
          "start S; S --> A B where in_state('DEFAULT'), at_char_position('0');"
          " A --> 'a'; B --> 'b';",
        ).issues,
        isEmpty,
      );
    });

    test('testWarnsBeforeInLexicalRule', () {
      const title = 'before in lexical rule';
      final warnings = issues(
        "start S; S --> A B; A --> 'a' where before('B'); B --> 'b';",
        title,
      );

      expect(warnings, hasLength(1));
      expect(warnings.single.severity, Severity.warning);
      expect(
        issues(
          "start S; S --> P B; P --> A where before('B'); A --> 'a'; B --> 'b';",
          title,
        ),
        isEmpty,
      );
    });

    test('testWarnsLexicalTieByDeclarationOrder', () {
      const title = 'Lexical tie broken by declaration order';
      const start = 'start S; S --> {TOKEN}; ';

      for (final tied in [
        "W{k: b} --> 'a'; W{k: a} --> 'a';",
        'W{k: b} --> [a-z]+; W{k: a} --> [a-z]+;',
        "W{k: b} --> {X} 'a'; W{k: a} --> 'a';",
        "W{k: b} --> {X} 'a' ==> Y; W{k: a} --> {X} 'a' ==> Y;",
      ]) {
        final warnings = issues(start + tied, title);
        expect(warnings, hasLength(1), reason: tied);
        expect(warnings.single.severity, Severity.warning, reason: tied);
        expect(warnings.single.message, contains("'W'"), reason: tied);
      }
      for (final separate in [
        "B{k: b} --> 'a'; A{k: a} --> 'a';",
        "W{k: a} --> 'a'; W{k: a} --> 'a';",
        "W{k: b} --> 'a' ==> X; W{k: a} --> 'a' ==> Y;",
        "W{k: b} --> {X} 'a'; W{k: a} --> {Y} 'a';",
        "W{k: b} --> 'a'; W{k: a} --> 'b';",
      ]) {
        expect(issues(start + separate, title), isEmpty, reason: separate);
      }
    });
  });

  group('weights', () {
    test('testWarnsWeightInsideWeightedGroup', () {
      final warnings = issues(
        "start S; S --> A where (equals('a', 'a'):3, equals('b', 'b')):5; A --> 'a';",
        'Weight inside a weighted group',
      );

      expect(warnings, hasLength(1));
      expect(warnings.single.severity, Severity.warning);
      expect(
        issues(
          "start S; S --> A where equals('a', 'a'):3, equals('b', 'b'):5; A --> 'a';",
          'Weight inside a weighted group',
        ),
        isEmpty,
      );
    });

    test('testCostHintForUnregisteredSoftPredicate', () {
      final hints = issues(
        "start S; S --> A:a 'x' where bound(a):1; A --> 'y';",
        'Soft group that never holds',
      );

      expect(hints, hasLength(1));
      expect(hints.single.severity, Severity.info);
      expect(hints.single.message, contains('@1'));
    });

    test('testNoCostHintForRegisteredPredicate', () {
      final predicates = Predicates.builder()
          .builtins()
          .add('bound', 1, 1, Phase.syntactic, (environment, args) => true)
          .build();

      expect(
        issues(
          "start S; S --> A:a 'x' where bound(a):1; A --> 'y';",
          'Soft group that never holds',
          GrammarLinter(predicates),
        ),
        isEmpty,
      );
    });
  });

  group('report', () {
    test('testLintReportFormatting', () {
      final formatted = lint("start S; S --> Missing; X --> Y 'z'; Y --> 'y';")
          .format();

      expect(formatted, contains('Grammar Linting Report'));
      expect(formatted, contains('ERRORS'));
      expect(formatted, contains('WARNINGS'));
      expect(formatted, contains('[ERROR]'));
      expect(formatted, contains('[WARN]'));
    });
  });

  group('corpus', () {
    test('testNoErrorsOnLoadingGrammars', () {
      for (final MapEntry(key: name, value: files) in cases.entries) {
        final loaded = GrammarLoader.unvalidated(files['grammar.ug']!);
        final expected = files['expected.json']!.replaceAll(RegExp(r'\s'), '');
        if (loaded case Success(value: final source)
            when !expected.contains('"error":"validation"')) {
          expect(linter.lint(source).errors, isEmpty, reason: name);
        }
      }
    });
  });
}
