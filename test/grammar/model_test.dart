import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

GrammarRule rule(String symbol, List<RuleElement> rhs) =>
    GrammarRule(LHS(symbol), rhs);

/// Ported from Java `GrammarBuilderTests` at unifica 8d8c01a, then the 2.0
/// rule model: classification (S-G1), costs, transitions, sequences.
void main() {
  group('building', () {
    test('testBuildsEmptyGrammar', () {
      expect(Grammar.builder().build().rules, isEmpty);
    });

    test('testBuildsWithRules', () {
      final grammar = Grammar.builder()
          .add(rule('S', [Nonterminal('A')]))
          .add(rule('A', [const Terminal('a')]))
          .add(rule('A', [const Terminal('b')]))
          .build();

      expect(grammar.rules, hasLength(2));
      expect(grammar.rulesFor('S'), hasLength(1));
      expect(grammar.rulesFor('A'), hasLength(2));
      expect(grammar.rulesFor('missing'), isEmpty);
      expect(grammar.hasRulesFor('A'), isTrue);
    });

    test('testStartSymbol', () {
      expect(
        Grammar.builder()
            .start('document')
            .add(rule('document', []))
            .build()
            .start,
        'document',
      );
      expect(
        Grammar.builder()
            .add(rule('first', []))
            .add(rule('second', []))
            .build()
            .start,
        'first',
      );
      expect(
        Grammar.builder()
            .add(rule('A', []))
            .add(rule('B', []))
            .start('B')
            .build()
            .start,
        'B',
      );
      expect(Grammar.builder().build().start, 'document');
    });

    test('testModuleInfo', () {
      final grammar = Grammar.builder()
          .module(const ModuleInfo('myModule', {'export1', 'export2'}))
          .build();

      expect(grammar.module.name, 'myModule');
      expect(grammar.module.isExported('export1'), isTrue);
      expect(Grammar.builder().build().module, ModuleInfo.anonymous);
    });

    test('testImports', () {
      final grammar = Grammar.builder()
          .addImport(const ImportAll('module1'))
          .addImport(ImportSelective('module2', {'sym1', 'sym2'}))
          .addImport(const ImportFile('path/to/file.ug'))
          .build();

      expect(grammar.imports, hasLength(3));
      expect(grammar.imports.first.path, 'module1');
    });

    test('testSkipsAndWhitespace', () {
      final grammar = Grammar.builder()
          .skip('COMMENT')
          .skip('WS')
          .skip('COMMENT')
          .whitespace('[ ]+')
          .build();

      expect(grammar.skips, {'COMMENT', 'WS'});
      expect(grammar.whitespace, '[ ]+');
      expect(Grammar.builder().build().whitespace, isNull);
      expect(Grammar.builder().whitespace('').build().whitespace, '');
    });

    test('testMethodsReturnBuilder', () {
      final builder = Grammar.builder();
      expect(builder.add(rule('S', [])), same(builder));
      expect(builder.start('S'), same(builder));
      expect(builder.module(ModuleInfo.anonymous), same(builder));
      expect(builder.addImport(const ImportAll('x')), same(builder));
      expect(builder.skip('X'), same(builder));
      expect(builder.whitespace(null), same(builder));
    });

    test('testFromExistingGrammar', () {
      final original = Grammar.builder()
          .module(const ModuleInfo('original', {'A'}))
          .start('S')
          .add(rule('S', [Nonterminal('A')]))
          .add(rule('A', [const Terminal('a')]))
          .addImport(const ImportAll('dep'))
          .skip('WS')
          .whitespace('none')
          .build();

      final copy = original.toBuilder().build();
      expect(copy.module.name, 'original');
      expect(copy.start, 'S');
      expect(copy.rules, hasLength(2));
      expect(copy.imports, hasLength(1));
      expect(copy.skips, {'WS'});
      expect(copy.whitespace, 'none');

      final modified = original
          .toBuilder()
          .add(rule('B', [const Terminal('b')]))
          .build();
      expect(original.rules, hasLength(2));
      expect(modified.rules, hasLength(3));
    });
  });

  group('validation', () {
    test('testValidateReturnsLintReport', () {
      final report = Grammar.builder()
          .start('S')
          .add(rule('S', [const Terminal('x')]))
          .validate();

      expect(report.hasErrors, isFalse);
    });

    test('testValidatedSucceeds', () {
      final result = Grammar.builder()
          .start('S')
          .add(rule('S', [const Terminal('x')]))
          .validated();

      expect(result, isA<Success<Grammar, ErrorDetails>>());
    });

    test('testValidatedFailsForInvalidGrammar', () {
      final result = Grammar.builder()
          .start('S')
          .add(rule('S', [Nonterminal('undefined')]))
          .validated();

      expect(
        (result as Failure<Grammar, ErrorDetails>).error.code,
        'grammar.validation',
      );
    });
  });

  group('immutability', () {
    test('testBuildIsolatedFromBuilderReuse', () {
      final builder = Grammar.builder()
          .start('S')
          .add(rule('S', [const Terminal('a')]));
      final grammar = builder.build();

      builder.add(rule('S', [const Terminal('b')]));

      expect(grammar.rulesFor('S'), hasLength(1));
      expect(builder.build().rulesFor('S'), hasLength(2));
    });

    test('testBuiltListsUnmodifiable', () {
      final grammar = Grammar.builder()
          .add(rule('S', [const Terminal('a')]))
          .build();

      expect(
        () => grammar.rulesFor('S').add(rule('S', [])),
        throwsUnsupportedError,
      );
      expect(() => grammar.skips.add('X'), throwsUnsupportedError);
    });

    test('testRuleAndElementsCopyLists', () {
      final rhs = <RuleElement>[const Terminal('a')];
      final made = rule('S', rhs);
      final options = <RuleElement>[const Terminal('a')];
      final alternation = Alternation(options);
      final elements = <RuleElement>[const Terminal('a')];
      final sequence = Sequence(elements);

      rhs.add(const Terminal('b'));
      options.add(const Terminal('b'));
      elements.add(const Terminal('b'));

      expect(made.rhs, hasLength(1));
      expect(alternation.options, hasLength(1));
      expect(sequence.elements, hasLength(1));
    });

    test('testRulesKeepDeclarationOrder', () {
      final grammar = Grammar.builder()
          .add(rule('Z', [const Terminal('z')]))
          .add(rule('A', [const Terminal('a')]))
          .add(rule('M', [const Terminal('m')]))
          .build();

      expect(grammar.nonterminals, ['Z', 'A', 'M']);
    });
  });

  group('rules', () {
    Kind classify(List<RuleElement> rhs, {bool transition = false}) =>
        GrammarRule.classify(rhs, transition: transition);

    test('testClassify', () {
      expect(classify([]), Kind.syntactic);
      expect(classify([Nonterminal('A')]), Kind.syntactic);
      expect(classify([TokenMatch()]), Kind.syntactic);
      expect(
        classify([const Regex('[a-z]+'), Nonterminal('A')]),
        Kind.syntactic,
      );
      expect(classify([const Regex('[a-z]+')]), Kind.lexical);
      expect(
        classify([const StateAnnotation('S'), const Terminal('a')]),
        Kind.lexical,
      );
      expect(classify([const Terminal('a')]), Kind.lexical);
      expect(
        classify([const Terminal('a'), const Terminal('b')]),
        Kind.syntactic,
      );
      expect(
        classify([const Terminal('a'), const Terminal('b')], transition: true),
        Kind.lexical,
      );
      expect(
        classify([
          Alternation([const Terminal('a'), Nonterminal('B')]),
        ]),
        Kind.syntactic,
      );
      expect(
        classify([
          Sequence([const Regex('x'), const Terminal('y')]),
        ]),
        Kind.lexical,
      );
      expect(classify([const Repetition.star(Regex('x'))]), Kind.lexical);
      expect(classify([Repetition.plus(Nonterminal('A'))]), Kind.syntactic);
    });

    test('testRuleDefaults', () {
      final made = rule('S', [const Regex('[a-z]+')]);

      expect(made.kind, Kind.lexical);
      expect(made.cost, 0);
      expect(made.transition, isNull);
      expect(made.constraints, isEmpty);
    });

    test('testRuleKindFollowsTransition', () {
      final made = GrammarRule(LHS('S'), [
        const Terminal('a'),
        const Terminal('b'),
      ], transition: 'IN');

      expect(made.kind, Kind.lexical);
      expect(made.transition, 'IN');
    });

    test('testRuleWithConstraintsAndCost', () {
      final made = GrammarRule(
        LHS('S'),
        [Nonterminal('A')],
        constraints: const [Weighted(Call('p', []), 3)],
        cost: 7,
      );

      expect(made.constraints, const [Weighted(Call('p', []), 3)]);
      expect(made.cost, 7);
    });

    test('testNegativeCostIsAProgrammingError', () {
      expect(
        () => GrammarRule(LHS('S'), const [], cost: -1),
        throwsArgumentError,
      );
    });

    test('testStructuralEquality', () {
      expect(
        rule('S', [const Regex('a', 'x')]),
        rule('S', [const Regex('a', 'x')]),
      );
      expect(const Regex('a', 'x'), isNot(const Regex('a', 'y')));
      expect(Sequence([const Terminal('a')]), Sequence([const Terminal('a')]));
      expect(
        Sequence([const Terminal('a')]).hashCode,
        Sequence([const Terminal('a')]).hashCode,
      );
      expect(
        Sequence([const Terminal('a')]),
        isNot(Alternation([const Terminal('a')])),
      );
      expect(
        GrammarRule(LHS('S'), const [], cost: 1),
        isNot(GrammarRule(LHS('S'), const [], cost: 2)),
      );
    });
  });
}
