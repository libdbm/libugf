import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

import '../corpus/corpus.g.dart';

final standard = Predicates.standard();

Grammar grammar(String source) =>
    GrammarLoader.unvalidated(source).orElseThrow();

Compiled compile(String source) =>
    Compiler.compile(grammar(source), standard).orElseThrow();

ErrorDetails failed(Result<Compiled, ErrorDetails> result) {
  final error = (result as Failure<Compiled, ErrorDetails>).error;
  expect(error.code, Compiler.invalid);
  return error;
}

ErrorDetails failure(String source) =>
    failed(Compiler.compile(grammar(source), standard));

List<Lexeme> lexemes(Compiled compiled, String category) => [
  for (final lexeme in compiled.lexemes)
    if (lexeme.category == category) lexeme,
];

/// A full match of [pattern] on [input].
bool matches(RegExp pattern, String input) =>
    pattern.matchAsPrefix(input)?.end == input.length;

/// Ported from Java `CompilerTests` at unifica 8d8c01a, except the lowering
/// tests, which are in `lowering_test.dart`. `testIdsStable`, `testNullable`
/// and `testRecursiveNullable` are also here with plain productions.
void main() {
  group('lexemes', () {
    test('testStateAnnotationLowered', () {
      final compiled = compile("start s; s --> b; b --> {IN} 'y';");

      final lexeme = lexemes(compiled, 'b').first;
      expect(lexeme.states, ['IN']);
      expect(matches(lexeme.pattern, 'y'), isTrue);
      expect(compiled.lexemes, hasLength(1));
    });

    test('testLexicalSequenceAtomic', () {
      final compiled = compile("start S; S --> T; T --> '\"' [a-z]* '\"';");

      expect(compiled.lexemes, hasLength(1));
      expect(matches(lexemes(compiled, 'T').first.pattern, '"abc"'), isTrue);
    });

    test('testAnonymousLexemesShared', () {
      final compiled = compile("start S; S --> 'a' X 'a'; X --> 'b';");

      final anonymous = [
        for (final lexeme in compiled.lexemes)
          if (lexeme.anonymous) lexeme,
      ];
      expect(anonymous, hasLength(1));
      expect(anonymous.first.category, "'a'");
      expect(anonymous.first.literal, 'a');
      final rhs = compiled.productionsFor('S').first.rhs;
      expect(rhs.first, const Anonymous("'a'"));
      expect(rhs[1], Named('X'));
    });

    test('testLiteralIsAField', () {
      final compiled = compile(r"start S; S --> 'a.b' [a-z]+ X; X --> 'x';");

      expect(
        [for (final lexeme in compiled.lexemes) lexeme.literal],
        ['a.b', null, 'x'],
      );
      final named = compile(
        "start S; S --> A B C; A --> {IN} 'a'; B --> 'b':l; C --> 'c' 'd' ==> X;",
      );
      expect(
        [for (final lexeme in named.lexemes) lexeme.literal],
        ['a', null, null],
      );
      expect(matches(lexemes(compiled, "'a.b'").first.pattern, 'a.b'), isTrue);
      expect(matches(lexemes(compiled, "'a.b'").first.pattern, 'axb'), isFalse);
    });

    test('testLabelsBecomeGroups', () {
      final lexeme = lexemes(
        compile("start S; S --> T; T --> [a-z]+:w '!';"),
        'T',
      ).first;

      final match = lexeme.pattern.matchAsPrefix('abc!')! as RegExpMatch;
      expect(match.end, 4);
      expect(lexeme.labels, ['w']);
      expect(match.namedGroup(Lexeme.group(0)), 'abc');
    });

    test('testTransitionAndCost', () {
      final lexeme = lexemes(
        compile("start S; S --> o; o --> '<' ==> IN @2;"),
        'o',
      ).first;

      expect(lexeme.transition, 'IN');
      expect(lexeme.cost, 2);
    });

    test('testSequenceOfLiteralsIsSyntactic', () {
      final compiled = compile("start A; A --> 'a' 'b';");

      expect(compiled.lexical('A'), isFalse);
      expect(compiled.productionsFor('A').first.rhs, hasLength(2));
    });

    test('testGroupsInsideALexeme', () {
      final lexeme = lexemes(
        compile("start S; S --> T; T --> ('a' | 'b':x)+ [0-9]?;"),
        'T',
      ).first;

      expect(matches(lexeme.pattern, 'abba7'), isTrue);
      expect(matches(lexeme.pattern, 'c'), isFalse);
      expect(lexeme.labels, ['x']);
    });

    test('testDollarInLexeme', () {
      final lexeme = lexemes(
        compile(r'start S; S --> A; A --> [a-z]+(?=$);'),
        'A',
      ).first;

      expect(matches(lexeme.pattern, 'ab'), isTrue);
      expect(lexeme.pattern.matchAsPrefix('ab\n'), isNull);
    });
  });

  group('productions', () {
    test('testIdsStable', () {
      const source = "start S; S --> A 'x'; S --> 'y'; A --> 'a';";
      final first = compile(source);
      final second = compile(source);

      expect(first.productions, second.productions);
      String describe(Lexeme lexeme) =>
          '${lexeme.id}${lexeme.category}${lexeme.pattern.pattern}';
      expect(
        first.lexemes.map(describe).toList(),
        second.lexemes.map(describe).toList(),
      );
      for (var index = 0; index < first.productions.length; index++) {
        expect(first.productions[index].id, index);
      }
    });

    test('testNullable', () {
      final compiled = compile(
        "start S; S --> A A; A --> E; A --> ; E --> 'a';",
      );

      expect(compiled.nullable, containsAll(['S', 'A']));
      expect(compiled.nullable, isNot(contains('E')));
    });

    test('testRecursiveNullable', () {
      final compiled = compile(
        "start S; S --> S S; S --> T; S --> ; T --> 'a';",
      );

      expect(compiled.nullable, contains('S'));
    });

    test('testCompiledShape', () {
      final compiled = compile(
        "start S; skip C; S --> A {TOKEN}:t; A{n: one} --> 'a'; C --> '#';",
      );

      expect(compiled.start, 'S');
      expect(compiled.predicates, same(standard));
      expect(compiled.categories, {'A', 'C'});
      expect(compiled.skips, {'C'});
      expect(compiled.lexical('A'), isTrue);
      expect(compiled.productionsFor('missing'), isEmpty);
      final production = compiled.productionsFor('S').single;
      expect(production.rhs, [Named('A'), Any('t')]);
      expect(production.auxiliary, isFalse);
      expect(
        lexemes(compiled, 'A').single.features,
        Structure.of({'n': const StringConstant('one')}),
      );
      expect(
        () => compiled.lexemes.add(compiled.lexemes.first),
        throwsUnsupportedError,
      );
    });

    test('testWhitespace', () {
      expect(
        compile("start S; S --> 'a';").whitespace!.pattern,
        Patterns.whitespace,
      );
      expect(
        compile("start S; whitespace none; S --> 'a';").whitespace,
        isNull,
      );
      expect(
        matches(
          compile("start S; whitespace [ ]+; S --> 'a';").whitespace!,
          '  ',
        ),
        isTrue,
      );
    });
  });

  group('order', () {
    String lexeme(Lexeme lexeme) =>
        '${lexeme.category}${lexeme.anonymous ? '*' : ''}';

    String production(Production production) => [
      production.symbol,
      for (final element in production.rhs)
        switch (element) {
          Named(:final name) => name,
          Anonymous(:final category) => category,
          Any() => '{TOKEN}',
        },
    ].join(' ');

    void check(String name, List<String> lexemes, List<String> productions) {
      final compiled = compile(cases[name]!['grammar.ug']!);
      expect(compiled.lexemes.map(lexeme).toList(), lexemes, reason: name);
      expect(
        compiled.productions.map(production).toList(),
        productions,
        reason: name,
      );
      for (var index = 0; index < compiled.lexemes.length; index++) {
        expect(compiled.lexemes[index].id, index);
      }
    }

    test('testDeclarationOrder', () {
      check(
        'parse-tie-break-declared-first',
        ['X'],
        ['S A', 'S B', 'A X', 'B X'],
      );
      check('parse-order-invariance-second', ['A', 'B'], ['S B', 'S A']);
      check('parse-tie-break-token', ['B', 'A'], ['S {TOKEN}']);
      check(
        'lexical-state-branching',
        ['a', 'b', 'x', 'y'],
        ['s a x', 's b y'],
      );
      check('review-lexical-sequence', ["'a'*", "'b'*"], ["A 'a' 'b'"]);
    });
  });

  group('validation', () {
    test('testUnknownPredicatesAllReported', () {
      final error = failure(
        "start S; S --> A where nope('a'), (also():3); A --> 'a';",
      );

      expect(error.issues, [
        'S: unknown predicate nope',
        'S: unknown predicate also',
      ]);
    });

    test('testWrongArity', () {
      expect(failure("start S; S --> A where equals('a'); A --> 'a';").issues, [
        'S: predicate equals expects 2 arguments, got 1',
      ]);
      expect(
        failure("start S; S --> A where before(); A --> 'a';").issues.single,
        'S: predicate before expects 1..n arguments, got 0',
      );
    });

    test('testUndefinedSymbol', () {
      expect(failure("start S; S --> A B; A --> 'a';").issues, [
        'S: undefined symbol B',
      ]);
      expect(failure("start T; S --> 'a';").issues, [
        'start symbol T is not defined',
      ]);
    });

    test('testWeightUnderOr', () {
      expect(
        failure(
          "start S; S --> A where (equals('a', 'a'):3 | equals('b', 'b')); A --> 'a';",
        ).issues.single,
        startsWith('S: '),
      );
    });

    test('testLexicalPredicateInSyntacticProduction', () {
      expect(
        compile("start S; S --> A where in_state('X'); A --> 'a';").productions,
        hasLength(1),
      );
    });

    test('testInvalidConstantRegex', () {
      expect(
        failure("start S; S --> W:w where matches(w, '['); W --> 'x';")
            .issues
            .single,
        startsWith('S: invalid regex in matches: '),
      );
    });

    test('testPatternsOutsideSubset', () {
      for (final source in [
        'start S; S --> A; A --> [a-z]++;',
        "start S; S --> A [a-z]++; A --> 'a';",
        r"start S; whitespace [\h]+; S --> A; A --> 'a';",
        "start S; S --> A:a where matches(a, '(?<n>a)'); A --> 'a';",
      ]) {
        expect(
          failure(source).issues.any((issue) => issue.contains('S-L7')),
          isTrue,
          reason: source,
        );
      }
    });

    test('testInvalidRegexElementReportedOnce', () {
      // The production adds no lexeme, so its use is undefined too, as in
      // Java.
      expect(failure('start S; S --> A; A --> [a-z]++ [0-9]+;').issues, [
        'A: possessive quantifiers are not portable at offset 6 (S-L7)',
        'S: undefined symbol A',
      ]);
    });

    test('testFlagsOnlyInStandalonePatterns', () {
      final flagged = Grammar.builder()
          .start('S')
          .add(GrammarRule.simple('S', [Nonterminal('A')]))
          .add(GrammarRule.simple('A', [const Regex('(?s).')]))
          .build();

      expect(
        failed(Compiler.compile(flagged, standard)).issues
            .any((issue) => issue.contains('S-L7')),
        isTrue,
      );
      compile("start S; S --> W:w where matches(w, '(?s).+'); W --> 'a';");
    });

    test('testInvalidGrammarRegexIsSyntaxFailure', () {
      expect(
        GrammarLoader.unvalidated('start S; S --> [a-;'),
        isA<Failure<Grammar, ErrorDetails>>(),
      );
    });

    test('testSkipMustNameLexicalProduction', () {
      expect(failure("start S; skip Missing; S --> 'a';").issues, [
        'skip Missing does not name a lexical production',
      ]);
      expect(compile("start S; skip C; S --> 'a'; C --> '#' [a-z]*;").skips, {
        'C',
      });
    });

    test('testMisplacedElements', () {
      final annotated = Grammar.builder()
          .start('S')
          .add(
            GrammarRule.simple('S', [
              const StateAnnotation('IN'),
              Nonterminal('A'),
            ]),
          )
          .add(GrammarRule.simple('A', [const Terminal('a')]))
          .build();
      expect(failed(Compiler.compile(annotated, standard)).issues, [
        'S: a state annotation is only allowed in a lexical production',
      ]);

      final lexical = Grammar.builder()
          .start('S')
          .add(GrammarRule.simple('S', [Nonterminal('A')]))
          .add(
            GrammarRule(LHS('A'), [
              const Terminal('a'),
              Nonterminal('B'),
              TokenMatch(),
            ], kind: Kind.lexical),
          )
          .add(GrammarRule.simple('B', [const Terminal('b')]))
          .build();
      expect(failed(Compiler.compile(lexical, standard)).issues, [
        'A: a lexical production cannot contain the symbol B',
        'A: a lexical production cannot contain {TOKEN}',
        'S: undefined symbol A',
      ]);
    });

    test('testCustomPredicates', () {
      final predicates = Predicates.builder()
          .builtins()
          .add('bound', 1, 1, Phase.syntactic, (environment, args) => true)
          .build();

      expect(
        Compiler.compile(
          grammar("start S; S --> A:a where bound(a):1; A --> 'a';"),
          predicates,
        ),
        isA<Success<Compiled, ErrorDetails>>(),
      );
    });
  });
}
