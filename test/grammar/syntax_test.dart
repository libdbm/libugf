import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Grammar load(String source) => GrammarLoader.unvalidated(source).orElseThrow();

ErrorDetails failure(String source) =>
    (GrammarLoader.unvalidated(source) as Failure<Grammar, ErrorDetails>).error;

Expression constraint(String where) =>
    load("start S; S --> 'x' where $where;")
        .rulesFor('S')
        .first
        .constraints
        .single;

GrammarRule only(String source, String symbol) =>
    load(source).rulesFor(symbol).single;

const x = Variable(r'$X');
Call call(String name, [List<Value> args = const [x]]) => Call(name, args);

/// The 2.0 grammar syntax (`UnificationGrammar.g4` at unifica 1ce922a).
/// Ported from Java `UnificationGrammarLexerTests`, `ConstraintParsingTests`,
/// `DefeasibleConstraintTests` and the grammar-text parts of
/// `PlanConversionTests`, with the edge cases of the ANTLR lexer.
void main() {
  group('strings', () {
    test('testStringLiterals', () {
      for (final source in [
        "s --> 'hello';",
        's --> "hello";',
        r"s --> 'it\'s';",
        r's --> "say \"hello\"";',
        r"s --> 'path\\to\\file';",
        "s --> '';",
        r"s --> 'hello\nworld\ttab';",
        "s{val:'quoted'} --> 'x';",
      ]) {
        expect(load(source).rulesFor('s'), hasLength(1), reason: source);
      }
    });

    test('testLiteralEscapes', () {
      final texts = [
        for (final element in only(
          r'''start S; S --> '\'' '\n' '\\' "\"" 'A' '\q';''',
          'S',
        ).rhs)
          (element as Terminal).text,
      ];
      expect(texts, ["'", '\n', r'\', '"', 'A', 'q']);
    });

    test('testMalformedUnicodeEscape', () {
      for (final literal in [r"'\u12'", r"'\uzz12'", r"'\u'"]) {
        expect(
          failure('start S; S --> $literal;').code,
          'grammar.syntax',
          reason: literal,
        );
      }
    });

    test('testUnterminatedString', () {
      expect(failure("start S; S --> 'abc;").code, 'grammar.syntax');
    });
  });

  group('regexes', () {
    String pattern(String rhs) =>
        (only('s --> $rhs;', 's').rhs.single as Regex).pattern;

    test('testRegexTokens', () {
      expect(pattern('[a-z]+'), '[a-z]+');
      expect(pattern('[^abc]+'), '[^abc]+');
      expect(pattern(r'[\]]+'), r'[\]]+');
      expect(pattern(r'[\\]+'), r'[\\]+');
      expect(pattern('.+'), '.+');
      expect(pattern(r'[\s\S]*'), r'[\s\S]*');
      expect(pattern('.?'), '.?');
      expect(pattern('(?:abc)+'), '(?:abc)+');
      expect(pattern('(?!bad)'), '(?!bad)');
      expect(pattern('(?=good)'), '(?=good)');
      expect(pattern('(?<=a)'), '(?<=a)');
      expect(pattern('(?<!a)'), '(?<!a)');
    });

    test('testQuantities', () {
      expect(pattern('[a-z]{2}'), '[a-z]{2}');
      expect(pattern('[a-z]{2,}'), '[a-z]{2,}');
      expect(pattern('[a-z]{2,3}?'), '[a-z]{2,3}?');
      expect(pattern('[a-z]+?'), '[a-z]+?');
      expect(pattern('[a-z]++'), '[a-z]++');
      expect(pattern('.*?'), '.*?');
      expect(pattern('.{3}'), '.{3}');
    });

    test('testAdjacentRegexTokensJoin', () {
      expect(pattern('[a-z]+ [0-9]*'), '[a-z]+[0-9]*');
      expect(pattern('[a-z][0-9]'), '[a-z][0-9]');
    });

    test('testGroupsNestAndHoldClasses', () {
      expect(pattern('(?:a(?:b|[)(])c)'), '(?:a(?:b|[)(])c)');
      expect(pattern(r'(?:\))'), r'(?:\))');
    });

    test('testRegexLabel', () {
      final regex = only('s --> [a-z]+:word;', 's').rhs.single as Regex;
      expect((regex.pattern, regex.label), ('[a-z]+', 'word'));
    });

    test('testBareDotAndDotStarAreNotRegexes', () {
      expect(failure('s --> .;').code, 'grammar.syntax');
      expect(failure('s --> .*;').code, 'grammar.syntax');
    });

    test('testUnclosedClassIsASyntaxError', () {
      expect(failure('s --> [a-z;').code, 'grammar.syntax');
      expect(failure('s --> []a];').code, 'grammar.syntax');
    });

    test('testInvalidRegexIsASyntaxError', () {
      // A pattern inside the subset that no engine accepts, as Java reports
      // a PatternSyntaxException at load.
      expect(failure('s --> [z-a];').code, 'grammar.syntax');
    });

    test('testPatternsOutsideTheSubsetLoad', () {
      // The compiler reports them (grammar.invalid); loading accepts them.
      expect(pattern('[a-z]++'), '[a-z]++');
      expect(pattern(r'[\w-a]+'), r'[\w-a]+');
    });
  });

  group('modules', () {
    test('testModuleNameWithDots', () {
      expect(load("module syntax.core; s --> 'x';").module.name, 'syntax.core');
    });

    test('testImports', () {
      final grammar = load('''
        import syntax.base.*;
        import syntax.core{np, vp};
        import "legacy.ug";
        import plain;
        s --> 'x';
      ''');
      expect(grammar.imports, [
        const ImportAll('syntax.base'),
        ImportSelective('syntax.core', {'np', 'vp'}),
        const ImportFile('legacy.ug'),
        const ImportAll('plain'),
      ]);
    });

    test('testExports', () {
      final listed = load("module m; export a, b; export c; s --> 'x';").module;
      expect(listed.name, 'm');
      expect(listed.exports, {'a', 'b', 'c'});
      expect(load("module m; export *; s --> 'x';").module.exports, isEmpty);
      expect(load("export a; s --> 'x';").module.name, 'anonymous');
      expect(load("s --> 'x';").module, ModuleInfo.anonymous);
    });

    test('testMixedDotsAndRegex', () {
      final grammar = load(r'module a.b.c; s --> [a-z]+ [\s\S]* ;');
      expect(grammar.module.name, 'a.b.c');
      expect(grammar.rulesFor('s'), hasLength(1));
    });
  });

  group('statements', () {
    test('testSkipStatement', () {
      expect(
        load(
          "start S; skip Comment, Line; skip Other; S --> 'a'; Comment --> '#' [a-z]*;",
        ).skips,
        {'Comment', 'Line', 'Other'},
      );
    });

    test('testWhitespaceStatement', () {
      expect(load("whitespace [ \\t]+; S --> 'a';").whitespace, r'[ \t]+');
      expect(load("whitespace none; S --> 'a';").whitespace, '');
      expect(load("S --> 'a';").whitespace, isNull);
      expect(failure("whitespace tabs; S --> 'a';").code, 'grammar.syntax');
    });

    test('testStartAndKeywordsAreReserved', () {
      expect(load("start S; S --> 'a';").start, 'S');
      expect(failure("start --> 'a';").code, 'grammar.syntax');
      expect(failure("where --> 'a';").code, 'grammar.syntax');
      expect(
        load("none --> 'a'; cost --> 'b';").rulesFor('none'),
        hasLength(1),
      );
    });

    test('testCommentsAreSkipped', () {
      expect(
        load("# a comment\nS --> 'a'; # another\n").rulesFor('S'),
        hasLength(1),
      );
    });
  });

  group('rules', () {
    test('testTopLevelAlternativesAreRules', () {
      final rules = load("S --> 'a' | B 'c' | ; B --> 'b';").rulesFor('S');
      expect([for (final rule in rules) rule.rhs.length], [1, 2, 0]);
    });

    test('testAlternativesShareConstraintsTransitionAndCost', () {
      final rules = load("T --> 'a' | 'b' where p(\$X) ==> IN @3;")
          .rulesFor('T');
      expect(rules, hasLength(2));
      for (final rule in rules) {
        expect(rule.constraints, [call('p')]);
        expect(
          (rule.transition, rule.cost, rule.kind),
          ('IN', 3, Kind.lexical),
        );
      }
    });

    test('testGroups', () {
      final rhs = only(
        "S --> ('a' 'b') ('c' | 'd' 'e' | ) () B; B --> 'b';",
        'S',
      ).rhs;
      expect(rhs, [
        Sequence(const [Terminal('a'), Terminal('b')]),
        Alternation([
          const Terminal('c'),
          Sequence(const [Terminal('d'), Terminal('e')]),
          Sequence(const []),
        ]),
        Sequence(const []),
        Nonterminal('B'),
      ]);
    });

    test('testSingleElementGroupIsTheElement', () {
      expect(only("S --> ('a')*;", 'S').rhs, [
        const Repetition.star(Terminal('a')),
      ]);
    });

    test('testQuantifiersAndLabels', () {
      final rhs = only(
        "S --> A* B+ C? 'x':y {TOKEN}:t A{n: \$N}:a; A --> 'a'; B --> 'b'; C --> 'c';",
        'S',
      );
      expect(rhs.rhs, [
        Repetition.star(Nonterminal('A')),
        Repetition.plus(Nonterminal('B')),
        Repetition.optional(Nonterminal('C')),
        const Terminal('x', 'y'),
        const TokenMatch('t'),
        Nonterminal.withFeatures(
          'A',
          Structure.of({'n': const Variable(r'$N')}),
          'a',
        ),
      ]);
    });

    test('testDoubleQuantifierIsASyntaxError', () {
      expect(failure("S --> 'a'+?;").code, 'grammar.syntax');
    });

    test('testLabelledGroupIsASyntaxError', () {
      expect(failure("S --> ('a' 'b'):x;").code, 'grammar.syntax');
    });

    test('testFeatures', () {
      final rule = only(
        "S{num: \$N, case: nom, agr: {p: '3'}} --> A{num: \$N}; A --> 'a';",
        'S',
      );
      expect(
        rule.lhs.features,
        Structure.of({
          'num': const Variable(r'$N'),
          'case': const StringConstant('nom'),
          'agr': Structure.of({'p': const StringConstant('3')}),
        }),
      );
      expect(
        (rule.rhs.single as Nonterminal).features,
        Structure.of({'num': const Variable(r'$N')}),
      );
      expect(failure("S{} --> 'a';").code, 'grammar.syntax');
    });

    test('testStateTransitions', () {
      String? transition(String text) =>
          only("T --> 'a' $text;", 'T').transition;
      expect(transition('==> IN'), 'IN');
      expect(transition('==> _'), '_');
      expect(transition('==> !IN'), '!IN');
      expect(transition('==> ^IN'), '^IN');
    });

    test('testStateAnnotation', () {
      expect(
        only("T --> {IN} 'y';", 'T').rhs.first,
        const StateAnnotation('IN'),
      );
    });

    test('testLexicalConstructsRejectNonterminals', () {
      expect(failure("S --> A ==> IN; A --> 'a';").code, 'grammar.syntax');
      expect(failure("S --> {IN} A; A --> 'a';").code, 'grammar.syntax');
      expect(failure("S --> 'a' | ==> IN;").code, 'grammar.syntax');
    });

    test('testLexicalKindRecorded', () {
      expect(only("start K; K --> 'if';", 'K').kind, Kind.lexical);
      expect(only('''start S; S --> '"' [^"]* '"';''', 'S').kind, Kind.lexical);
      expect(only("start b; b --> {IN} 'y';", 'b').kind, Kind.lexical);
      expect(only("start o; o --> '<' ==> IN;", 'o').kind, Kind.lexical);
      expect(only("start I; I --> ([a-z] | '_')+;", 'I').kind, Kind.lexical);
    });

    test('testSyntacticKindRecorded', () {
      expect(only("start A; A --> 'a' 'b';", 'A').kind, Kind.syntactic);
      expect(
        load("start S; S --> A 'x'; A --> 'a';").rulesFor('S').single.kind,
        Kind.syntactic,
      );
      expect(only('start T; T --> {TOKEN};', 'T').kind, Kind.syntactic);
      expect(only("start A; A --> 'a'+;", 'A').kind, Kind.syntactic);
    });

    test('testProductionCost', () {
      int cost(String source, String symbol) =>
          load(source).rulesFor(symbol).first.cost;
      expect(
        cost(
          "start np; np --> det n where agree(det, n) @2; det --> 'a'; n --> 'b';",
          'np',
        ),
        2,
      );
      expect(cost("start S; S --> A @1; A --> 'a';", 'S'), 1);
      expect(cost("start o; o --> '<' ==> IN @5;", 'o'), 5);
      expect(cost("start S; S --> A; A --> 'a';", 'S'), 0);
      expect(cost("start cost; cost --> A @3; A --> 'a';", 'cost'), 3);
    });

    test('testOutOfRangeNumbersAreSyntaxErrors', () {
      expect(
        failure("S --> 'x' where p():99999999999999999999;").code,
        'grammar.syntax',
      );
      expect(
        failure("S --> 'x' @99999999999999999999;").code,
        'grammar.syntax',
      );
    });
  });

  group('variables', () {
    // Ported from Java `VariableSyntaxTests` at unifica 1ce922a: a `$`
    // prefix, not capitalization, marks a variable.
    Structure features(String source) => only(source, 'S').lhs.features;

    test('testPrefixedValueIsVariable', () {
      expect(
        features(r"S{num: $N} --> 'a';").get('num'),
        const Variable(r'$N'),
      );
      expect(
        features(r"S{num: $n} --> 'a';").get('num'),
        const Variable(r'$n'),
      );
    });

    test('testCapitalizedValueIsAtom', () {
      expect(
        features("S{case: Nom} --> 'a';").get('case'),
        const StringConstant('Nom'),
      );
    });

    test('testPrefixedArgumentIsVariable', () {
      final rule = only(r"S --> 'a' where f($X, $X.num, n);", 'S');

      expect((rule.constraints.single as Call).args, [
        const Variable(r'$X'),
        FeaturePath([r'$X', 'num']),
        const Variable('n'),
      ]);
    });

    test('testDisplayOmitsPrefix', () {
      expect(const Variable(r'$X').display(), '?X');
    });
  });

  group('constraints', () {
    test('testPredicates', () {
      expect(
        constraint(r'agree($X, $Y)'),
        const Call('agree', [Variable(r'$X'), Variable(r'$Y')]),
      );
      expect(
        constraint("equals(W.cat, 'noun', {f: v})"),
        Call('equals', [
          FeaturePath(['W', 'cat']),
          const StringConstant('noun'),
          Structure.of({'f': const StringConstant('v')}),
        ]),
      );
      // A bare name is a label or symbol, read with Java's Variable.of.
      expect(constraint('p(subj)'), const Call('p', [Variable('subj')]));
      expect(constraint('p()'), const Call('p', []));
    });

    test('testPrecedence', () {
      final a = call('a');
      final b = call('b');
      final c = call('c');
      final d = call('d');
      expect(constraint('!a(\$X)'), Not(a));
      expect(constraint('!!a(\$X)'), Not(Not(a)));
      expect(constraint('a(\$X) | b(\$X)'), Or([a, b]));
      expect(constraint('a(\$X) | b(\$X) | c(\$X)'), Or([a, b, c]));
      expect(
        constraint('a(\$X), b(\$X) | c(\$X)'),
        Or([
          And([a, b]),
          c,
        ]),
      );
      expect(constraint('!a(\$X), b(\$X)'), And([Not(a), b]));
      expect(constraint('!a(\$X) | b(\$X)'), Or([Not(a), b]));
      expect(
        constraint('a(\$X), (b(\$X) | c(\$X))'),
        And([
          a,
          Or([b, c]),
        ]),
      );
      expect(constraint('!(a(\$X) | b(\$X))'), Not(Or([a, b])));
      expect(
        constraint('((a(\$X) | b(\$X)), c(\$X)) | d(\$X)'),
        Or([
          And([
            Or([a, b]),
            c,
          ]),
          d,
        ]),
      );
      expect(
        constraint('!a(\$X), !b(\$X), !c(\$X)'),
        And([Not(a), Not(b), Not(c)]),
      );
    });

    test('testWeights', () {
      expect(constraint('prefer(\$X):10'), Weighted(call('prefer'), 10));
      expect(
        constraint('(a(\$X), b(\$X)):5'),
        Weighted(And([call('a'), call('b')]), 5),
      );
      expect(
        constraint('!forbidden(\$X):15'),
        Not(Weighted(call('forbidden'), 15)),
      );
      expect(
        constraint('(!forbidden(\$X)):15'),
        Weighted(Not(call('forbidden')), 15),
      );
      expect(constraint('a(\$X):0'), Weighted(call('a'), 0));
    });
  });

  group('plans', () {
    Plan plan(String where) => Plan.of(
      load("start S; S --> 'x' where $where;").rulesFor('S').first.constraints,
    ).orElseThrow();

    ErrorDetails rejected(String where) => (Plan.of(
      load("start S; S --> 'x' where $where;").rulesFor('S').first.constraints,
    ) as Failure<Plan, ErrorDetails>).error;

    test('testRequiredAndSoft', () {
      expect(plan('r(\$X)'), Plan([call('r')], const []));
      expect(plan('p(\$X):3'), Plan(const [], [Soft(call('p'), 3)]));
      expect(
        plan('p(\$X):3, q(\$X):7'),
        Plan(const [], [Soft(call('p'), 3), Soft(call('q'), 7)]),
      );
      expect(plan('r(\$X), p(\$X):3'), Plan([call('r')], [Soft(call('p'), 3)]));
    });

    test('testGroups', () {
      expect(
        plan('(p(\$X), q(\$X)):7'),
        Plan(const [], [
          Soft(And([call('p'), call('q')]), 7),
        ]),
      );
      expect(
        plan('(p(\$X) | q(\$X)):7'),
        Plan(const [], [
          Soft(Or([call('p'), call('q')]), 7),
        ]),
      );
      expect(
        plan('r(\$X), (p(\$X):3, q(\$X):4)'),
        Plan([call('r')], [Soft(call('p'), 3), Soft(call('q'), 4)]),
      );
      expect(
        plan('(p(\$X):3, q(\$X):4):9'),
        Plan(const [], [
          Soft(And([call('p'), call('q')]), 9),
        ]),
      );
    });

    test('testMisplacedWeightsRejected', () {
      expect(rejected('(p(\$X):3 | q(\$X))').code, 'constraint.weight');
      expect(rejected('!p(\$X):3').code, 'constraint.weight');
      expect(rejected('(p(\$X):3 | q(\$X)), !r(\$X):2').issues, hasLength(2));
    });
  });

  group('errors', () {
    test('testErrorsAreCollectedWithPositions', () {
      final error = failure("S --> 'a' ;;\nT -> 'b';\nU --> 'c';");
      expect(error.code, 'grammar.syntax');
      expect(error.issues.length, greaterThanOrEqualTo(2));
      expect(error.issues.first, startsWith('line 1:'));
      expect(error.issues.any((issue) => issue.startsWith('line 2:')), isTrue);
    });

    test('testUnrecognizedCharacter', () {
      final error = failure("S --> 'a' ~;");
      expect(error.issues.first, startsWith('line 1:10'));
    });
  });
}
