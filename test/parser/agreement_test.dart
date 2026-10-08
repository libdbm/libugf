import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Parser parser(Grammar grammar) => ParserFactory.create(grammar).orElseThrow();

Structure number(String value) => Structure.of({'num': StringConstant(value)});

/// The feature unification scenarios of Java `ParserScenarioTests` at
/// unifica 8d8c01a, and S-F5 renaming apart. The diagnostics they also check
/// are Task 30's.
void main() {
  test('testPreservesFeaturesFromLexicalRules', () {
    final grammar = Grammar.builder()
        .start('S')
        .add(GrammarRule.simple('S', [Nonterminal('DET'), Nonterminal('N')]))
        .add(GrammarRule(LHS('DET', number('sing')), const [Terminal('a')]))
        .add(GrammarRule.simple('N', const [Terminal('cat')]))
        .build();

    final tree = parser(grammar).parse('a cat').tree! as Node;

    expect((tree.children.first as Node).features, number('sing'));
  });

  group('agreement', () {
    final agreement = Structure.of({'num': const Variable('n')});
    final grammar = Grammar.builder()
        .start('S')
        .add(
          GrammarRule.simple('S', [
            Nonterminal('NP', null, agreement),
            Nonterminal('VP', null, agreement),
          ]),
        )
        .add(GrammarRule(LHS('NP', number('sg')), const [Terminal('cat')]))
        .add(GrammarRule(LHS('NP', number('pl')), const [Terminal('cats')]))
        .add(GrammarRule(LHS('VP', number('sg')), const [Terminal('runs')]))
        .add(GrammarRule(LHS('VP', number('pl')), const [Terminal('run')]))
        .build();

    test('testRecordsUnificationFailure', () {
      expect(parser(grammar).parse('cat run').success, isFalse);
    });

    test('testAgreementHolds', () {
      expect(parser(grammar).parse('cat runs').success, isTrue);
      expect(parser(grammar).parse('cats run').success, isTrue);
    });
  });

  group('renaming apart', () {
    ParseResult parse(String source, String input) =>
        parser(GrammarLoader.parse(source).orElseThrow()).parse(input);

    test('testConstituentVariablesAreIndependent', () {
      // Each X constituent leaves its variable unbound, renamed apart, so
      // the two uses do not constrain each other.
      const source =
          "start S; S --> X{v: sg} X{v: pl}; X{v: \$V} --> Y; Y --> 'x';";

      expect(parse(source, 'x x').success, isTrue);
    });

    test('testEdgeVariablesAreIndependent', () {
      // A token's variables are renamed apart per edge.
      const source = "start S; S --> T{v: sg} T{v: pl}; T{v: \$V} --> 'x';";

      expect(parse(source, 'x x').success, isTrue);
    });

    test('testFeaturesFlowUp', () {
      final tree =
          parse(
                "start S; S{n: \$N} --> D{n: \$N} W{n: \$N}; D{n: \$N} --> 'the'; W{n: pl} --> 'dogs';",
                'the dogs',
              ).tree!
              as Node;

      expect(tree.features, Structure.of({'n': const StringConstant('pl')}));
    });
  });
}
