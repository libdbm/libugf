import 'package:test/test.dart';
import 'package:libugf/libugf.dart';

void main() {
  group('RuleElement types', () {
    test('Nonterminal creation', () {
      final nt = Nonterminal('np');
      expect(nt.name, equals('np'));
      expect(nt.label, isNull);
      expect(nt.features.isEmpty, isTrue);
    });

    test('Nonterminal with label', () {
      final nt = Nonterminal('np', 'subject');
      expect(nt.name, equals('np'));
      expect(nt.label, equals('subject'));
    });

    test('Nonterminal with features', () {
      final features = Structure.of({'case': const StringConstant('nom')});
      final nt = Nonterminal.withFeatures('np', features);
      expect(nt.features['case'], equals(const StringConstant('nom')));
    });

    test('Nonterminal withLabel', () {
      final nt = Nonterminal('np').withLabel('subj');
      expect(nt.label, equals('subj'));
    });

    test('Terminal creation', () {
      final term = const Terminal('the');
      expect(term.text, equals('the'));
      expect(term.label, isNull);
    });

    test('Terminal with label', () {
      final term = const Terminal('the', 'det');
      expect(term.label, equals('det'));
    });

    test('Regex creation', () {
      const regex = Regex(r'[A-Z][a-z]*');
      expect(regex.pattern, equals(r'[A-Z][a-z]*'));
      expect(regex.label, isNull);
    });

    test('Repetition star', () {
      final rep = Repetition.star(Nonterminal('np'));
      expect(rep.quantifier, equals(Quantifier.star));
      expect(rep.element, isA<Nonterminal>());
    });

    test('Repetition plus', () {
      final rep = const Repetition.plus(Terminal('a'));
      expect(rep.quantifier, equals(Quantifier.plus));
    });

    test('Repetition optional', () {
      final rep = Repetition.optional(Nonterminal('adj'));
      expect(rep.quantifier, equals(Quantifier.optional));
    });

    test('Alternation creation', () {
      final alt = Alternation([const Terminal('a'), const Terminal('the')]);
      expect(alt.options.length, equals(2));
    });

    test('StateAnnotation creation', () {
      final state = const StateAnnotation('CONTENT');
      expect(state.state, equals('CONTENT'));
    });

    test('TokenMatch creation', () {
      final tm = TokenMatch();
      expect(tm.label, isNull);
    });

    test('TokenMatch with label', () {
      final tm = TokenMatch('W');
      expect(tm.label, equals('W'));
    });
  });

  group('LHS', () {
    test('simple LHS', () {
      final lhs = LHS('sentence');
      expect(lhs.symbol, equals('sentence'));
      expect(lhs.hasFeatures, isFalse);
    });

    test('LHS with features', () {
      final features = Structure.of({'tense': const StringConstant('past')});
      final lhs = LHS('vp', features);
      expect(lhs.symbol, equals('vp'));
      expect(lhs.hasFeatures, isTrue);
    });
  });

  group('GrammarRule', () {
    test('simple rule', () {
      final rule = GrammarRule.simple('s', [
        Nonterminal('np'),
        Nonterminal('vp'),
      ]);
      expect(rule.lhs.symbol, equals('s'));
      expect(rule.rhs.length, equals(2));
      expect(rule.constraints, isEmpty);
    });

    test('rule with constraints', () {
      final rule = GrammarRule.simple(
        's',
        [Nonterminal('np', 'subj'), Nonterminal('vp', 'pred')],
        [
          const Call('agree', [Variable('subj'), Variable('pred')]),
        ],
      );
      expect(rule.constraints.length, equals(1));
    });

    test('rule toString', () {
      final rule = GrammarRule.simple('s', [
        Nonterminal('np'),
        Nonterminal('vp'),
      ]);
      expect(rule.toString(), contains('s -->'));
      expect(rule.toString(), contains('np'));
      expect(rule.toString(), contains('vp'));
    });
  });

  group('ImportDeclaration', () {
    test('ImportAll', () {
      final imp = const ImportAll('syntax.core');
      expect(imp.path, equals('syntax.core'));
      expect(imp.alias, isNull);
    });

    test('ImportAll with alias', () {
      final imp = const ImportAll('syntax.core', 'core');
      expect(imp.alias, equals('core'));
    });

    test('ImportSelective', () {
      final imp = ImportSelective('syntax.core', {'np', 'vp'});
      expect(imp.path, equals('syntax.core'));
      expect(imp.symbols, contains('np'));
      expect(imp.symbols, contains('vp'));
    });

    test('ImportFile', () {
      final imp = const ImportFile('base.ug');
      expect(imp.path, equals('base.ug'));
    });
  });

  group('ModuleInfo', () {
    test('anonymous module', () {
      expect(ModuleInfo.anonymous.name, isEmpty);
    });

    test('named module', () {
      final mod = const ModuleInfo('syntax.core');
      expect(mod.name, equals('syntax.core'));
    });

    test('isExported with empty exports', () {
      final mod = const ModuleInfo('test');
      expect(mod.isExported('anything'), isTrue);
    });

    test('isExported with specific exports', () {
      final mod = ModuleInfo.withExports('test', {'np', 'vp'});
      expect(mod.isExported('np'), isTrue);
      expect(mod.isExported('vp'), isTrue);
      expect(mod.isExported('s'), isFalse);
    });
  });

  group('Grammar', () {
    test('build simple grammar', () {
      final grammar = GrammarBuilder()
          .start('s')
          .add(GrammarRule.simple('s', [Nonterminal('np'), Nonterminal('vp')]))
          .add(GrammarRule.simple('np', [Nonterminal('det'), Nonterminal('n')]))
          .add(GrammarRule.simple('vp', [Nonterminal('v')]))
          .build();

      expect(grammar.start, equals('s'));
      expect(grammar.nonterminals.length, equals(3));
      expect(grammar.hasRulesFor('s'), isTrue);
      expect(grammar.hasRulesFor('np'), isTrue);
      expect(grammar.hasRulesFor('vp'), isTrue);
    });

    test('rulesFor returns empty list for unknown symbol', () {
      final grammar = GrammarBuilder()
          .add(GrammarRule.simple('s', [Nonterminal('np')]))
          .build();

      expect(grammar.rulesFor('unknown'), isEmpty);
    });

    test('start symbol defaults to first rule', () {
      final grammar = GrammarBuilder()
          .add(GrammarRule.simple('document', [Nonterminal('section')]))
          .add(GrammarRule.simple('section', [Nonterminal('para')]))
          .build();

      expect(grammar.start, equals('document'));
    });

    test('toBuilder creates modifiable copy', () {
      final grammar = GrammarBuilder()
          .start('s')
          .add(GrammarRule.simple('s', [Nonterminal('np')]))
          .build();

      final modified = grammar
          .toBuilder()
          .add(GrammarRule.simple('np', [const Terminal('test')]))
          .build();

      expect(modified.hasRulesFor('s'), isTrue);
      expect(modified.hasRulesFor('np'), isTrue);
      expect(grammar.hasRulesFor('np'), isFalse);
    });

    test('grammar with module and imports', () {
      final grammar = GrammarBuilder()
          .module(const ModuleInfo('syntax.main'))
          .addImport(const ImportAll('syntax.core'))
          .add(GrammarRule.simple('s', [Nonterminal('np')]))
          .build();

      expect(grammar.module.name, equals('syntax.main'));
      expect(grammar.imports.length, equals(1));
    });
  });

  group('RuleElement equality', () {
    test('Nonterminal equality', () {
      expect(Nonterminal('np'), equals(Nonterminal('np')));
      expect(Nonterminal('np'), isNot(equals(Nonterminal('vp'))));
      expect(Nonterminal('np', 'subj'), equals(Nonterminal('np', 'subj')));
      expect(
        Nonterminal('np', 'subj'),
        isNot(equals(Nonterminal('np', 'obj'))),
      );
    });

    test('Terminal equality', () {
      expect(const Terminal('the'), equals(const Terminal('the')));
      expect(const Terminal('the'), isNot(equals(const Terminal('a'))));
    });

    test('Repetition equality', () {
      expect(
        Repetition.star(Nonterminal('np')),
        equals(Repetition.star(Nonterminal('np'))),
      );
      expect(
        Repetition.star(Nonterminal('np')),
        isNot(equals(Repetition.plus(Nonterminal('np')))),
      );
    });
  });
}
