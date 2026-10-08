import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

final standard = Predicates.standard();

StringConstant string(String text) => StringConstant(text);

Variable variable(String name) => Variable(name);

/// Whether [name] holds for [args] in [environment]. A call the registry
/// would reject at compile time (S-C8) evaluates as false, as in Java
/// `BuiltinsTests`.
bool holds(
  Environment environment,
  String name, [
  List<Value> args = const [],
]) {
  final entry = standard.entry(name);
  if (entry == null || !entry.accepts(args.length)) {
    return false;
  }
  return environment.test(Call(name, args));
}

Environment bound(Map<String, Value> bindings) =>
    Environment.of(standard).merge(bindings);

Structure structure(Map<String, String> features) => Structure.of({
  for (final MapEntry(:key, :value) in features.entries) key: string(value),
});

/// Ported from Java `BuiltinsTests`, the standard-builtin tests of
/// `PredicatesTests` and `TotalityTests`, at unifica 8d8c01a.
void main() {
  group('registry', () {
    const unlimited = Entry.unlimited;
    const table = <(String, int, int, Phase)>[
      ('in_state', 1, unlimited, Phase.lexical),
      ('state_depth', 1, 1, Phase.lexical),
      ('state_contains', 1, unlimited, Phase.lexical),
      ('at_char_start', 0, 0, Phase.lexical),
      ('at_char_position', 1, 1, Phase.lexical),
      ('agree', 2, 2, Phase.syntactic),
      ('unify', 2, 2, Phase.syntactic),
      ('has_feature', 2, 2, Phase.syntactic),
      ('get_feature', 3, 3, Phase.syntactic),
      ('feature_eq', 4, 4, Phase.syntactic),
      ('equals', 2, 2, Phase.syntactic),
      ('not_equals', 2, 2, Phase.syntactic),
      ('is_string', 1, 1, Phase.syntactic),
      ('is_number', 1, 1, Phase.syntactic),
      ('is_structure', 1, 1, Phase.syntactic),
      ('is_bound', 1, 1, Phase.syntactic),
      ('starts_with', 2, 2, Phase.syntactic),
      ('ends_with', 2, 2, Phase.syntactic),
      ('contains', 2, 2, Phase.syntactic),
      ('matches', 2, 2, Phase.syntactic),
      ('not_empty', 1, 1, Phase.syntactic),
      ('is_upper', 1, 1, Phase.syntactic),
      ('is_lower', 1, 1, Phase.syntactic),
      ('is_capitalized', 1, 1, Phase.syntactic),
      ('lt', 2, 2, Phase.syntactic),
      ('le', 2, 2, Phase.syntactic),
      ('gt', 2, 2, Phase.syntactic),
      ('ge', 2, 2, Phase.syntactic),
      ('at_start', 0, 0, Phase.positional),
      ('at_position', 1, 1, Phase.positional),
      ('at_end', 0, 0, Phase.positional),
      ('before', 1, unlimited, Phase.positional),
    ];

    test('testEveryEntryMatchesJava', () {
      for (final (name, minimum, maximum, phase) in table) {
        final entry = standard.entry(name)!;
        expect(
          (entry.minimum, entry.maximum, entry.phase),
          (minimum, maximum, phase),
          reason: name,
        );
      }
      final all = <String>{
        for (final phase in Phase.values) ...standard.names(phase),
      };
      expect(all, {for (final (name, _, _, _) in table) name});
      expect(all, hasLength(32));
    });

    test('testStandardIncludesTheLexicalPredicates', () {
      expect(
        standard.names(Phase.lexical),
        Predicates.builder().lexical().build().names(Phase.lexical),
      );
    });

    test('testUnknownPredicate', () {
      expect(standard.entry('nonexistent'), isNull);
      expect(holds(Environment.of(standard), 'nonexistent'), isFalse);
    });
  });

  group('agree', () {
    test('testPassesWhenStructuresUnify', () {
      final environment = bound({
        'x': structure({'num': 'sing'}),
        'y': structure({'num': 'sing'}),
      });
      expect(
        holds(environment, 'agree', [variable('x'), variable('y')]),
        isTrue,
      );
      expect(
        holds(environment, 'unify', [variable('x'), variable('y')]),
        isTrue,
      );
    });

    test('testFailsWhenStructuresDoNotUnify', () {
      final environment = bound({
        'x': structure({'num': 'sing'}),
        'y': structure({'num': 'plur'}),
      });
      expect(
        holds(environment, 'agree', [variable('x'), variable('y')]),
        isFalse,
      );
    });

    test('testFailsWithWrongArityOrUnbound', () {
      expect(holds(bound({}), 'agree', [string('x')]), isFalse);
      expect(
        holds(bound({'y': Structure.empty}), 'agree', [
          variable('x'),
          variable('y'),
        ]),
        isFalse,
      );
    });
  });

  group('features', () {
    final environment = bound({
      'x': structure({'num': 'sing'}),
      'y': structure({'number': 'sing'}),
      'z': structure({'num': 'plur'}),
      'e': Structure.empty,
      's': string('hello'),
    });

    test('testHasFeature', () {
      expect(
        holds(environment, 'has_feature', [variable('x'), string('num')]),
        isTrue,
      );
      expect(
        holds(environment, 'has_feature', [variable('x'), string('case')]),
        isFalse,
      );
      expect(
        holds(environment, 'has_feature', [variable('s'), string('num')]),
        isFalse,
      );
      expect(holds(environment, 'has_feature', [string('x')]), isFalse);
    });

    test('testGetFeature', () {
      expect(
        holds(environment, 'get_feature', [
          variable('x'),
          string('num'),
          string('sing'),
        ]),
        isTrue,
      );
      expect(
        holds(environment, 'get_feature', [
          variable('x'),
          string('num'),
          string('plur'),
        ]),
        isFalse,
      );
      expect(
        holds(environment, 'get_feature', [
          variable('x'),
          string('case'),
          string('nom'),
        ]),
        isFalse,
      );
    });

    test('testFeatureEq', () {
      expect(
        holds(environment, 'feature_eq', [
          variable('x'),
          string('num'),
          variable('y'),
          string('number'),
        ]),
        isTrue,
      );
      expect(
        holds(environment, 'feature_eq', [
          variable('x'),
          string('num'),
          variable('z'),
          string('num'),
        ]),
        isFalse,
      );
      expect(
        holds(environment, 'feature_eq', [
          variable('x'),
          string('num'),
          variable('e'),
          string('num'),
        ]),
        isFalse,
      );
    });

    test('testFeatureBuiltinsAcceptBinding', () {
      final features = structure({'num': 'sg'});
      final labels = bound({
        'np': Binding.of('the dog', features),
        'vp': Binding.of('runs', features),
      });

      expect(
        holds(labels, 'has_feature', [variable('np'), string('num')]),
        isTrue,
      );
      expect(
        holds(labels, 'get_feature', [
          variable('np'),
          string('num'),
          string('sg'),
        ]),
        isTrue,
      );
      expect(
        holds(labels, 'feature_eq', [
          variable('np'),
          string('num'),
          variable('vp'),
          string('num'),
        ]),
        isTrue,
      );
      expect(holds(labels, 'agree', [variable('np'), variable('vp')]), isTrue);
    });
  });

  group('equality', () {
    test('testEqualsAndNotEquals', () {
      final environment = bound({'x': string('hello')});
      expect(
        holds(environment, 'equals', [variable('x'), string('hello')]),
        isTrue,
      );
      expect(
        holds(environment, 'equals', [variable('x'), string('world')]),
        isFalse,
      );
      expect(
        holds(environment, 'not_equals', [variable('x'), string('world')]),
        isTrue,
      );
      expect(
        holds(environment, 'not_equals', [variable('x'), string('hello')]),
        isFalse,
      );
      expect(
        holds(environment, 'not_equals', [variable('u'), string('hello')]),
        isTrue,
      );
    });

    test('testLabelAndStringCompareByText', () {
      // S-C9.
      final environment = bound({
        'w': Binding.of('hello', structure({'f': 'v'})),
      });
      expect(
        holds(environment, 'equals', [variable('w'), string('hello')]),
        isTrue,
      );
      expect(
        holds(environment, 'equals', [string('hello'), variable('w')]),
        isTrue,
      );
      expect(
        holds(environment, 'equals', [variable('w'), string('world')]),
        isFalse,
      );
      expect(
        holds(environment, 'not_equals', [variable('w'), string('hello')]),
        isFalse,
      );
      expect(
        holds(environment, 'not_equals', [string('world'), variable('w')]),
        isTrue,
      );
    });

    test('testTwoLabelsCompareByValue', () {
      final environment = bound({
        'a': Binding.of('hello', structure({'f': 'v'})),
        'b': Binding.of('hello'),
        'c': Binding.of('hello', structure({'f': 'v'})),
      });
      expect(
        holds(environment, 'equals', [variable('a'), variable('b')]),
        isFalse,
      );
      expect(
        holds(environment, 'not_equals', [variable('a'), variable('b')]),
        isTrue,
      );
      expect(
        holds(environment, 'equals', [variable('a'), variable('c')]),
        isTrue,
      );
    });

    test('testNumbersCompareByValue', () {
      expect(
        holds(bound({}), 'equals', [
          NumericConstant.integer(1),
          NumericConstant.real(1.0),
        ]),
        isTrue,
      );
    });
  });

  group('types', () {
    test('testTypeTests', () {
      final environment = bound({
        's': string('hello'),
        'n': NumericConstant.integer(42),
        'f': NumericConstant.real(3.14),
        'm': structure({'a': 'b'}),
      });
      expect(holds(environment, 'is_string', [variable('s')]), isTrue);
      expect(holds(environment, 'is_string', [variable('n')]), isFalse);
      expect(holds(environment, 'is_number', [variable('f')]), isTrue);
      expect(holds(environment, 'is_number', [string('42')]), isFalse);
      expect(holds(environment, 'is_structure', [variable('m')]), isTrue);
      expect(holds(environment, 'is_structure', [variable('s')]), isFalse);
    });

    test('testIsBound', () {
      // S-C11.
      final environment = bound({
        'x': string('val'),
        'w': Binding.of('x', structure({'f': 'v'})),
        'v': Binding.of('x', Structure.of({'f': variable('Y')})),
        'X': variable('Y'),
        'S': Structure.of({'f': variable('Y')}),
      });
      expect(holds(environment, 'is_bound', [variable('x')]), isTrue);
      expect(holds(environment, 'is_bound', [variable('unknown')]), isFalse);
      expect(holds(environment, 'is_bound', [string('literal')]), isTrue);
      expect(
        holds(environment, 'is_bound', [
          FeaturePath(['w', 'f']),
        ]),
        isTrue,
      );
      expect(
        holds(environment, 'is_bound', [
          FeaturePath(['w', 'missing']),
        ]),
        isFalse,
      );
      expect(
        holds(environment, 'is_bound', [
          FeaturePath(['unknown', 'f']),
        ]),
        isFalse,
      );
      expect(
        holds(environment, 'is_bound', [
          FeaturePath(['v', 'f']),
        ]),
        isFalse,
      );
      expect(holds(environment, 'is_bound', [variable('X')]), isFalse);
      expect(holds(environment, 'is_bound', [variable('S')]), isTrue);
    });
  });

  group('strings', () {
    final environment = bound({
      's': string('hello world'),
      'e': string(''),
      'n': NumericConstant.integer(42),
      'w': Binding.of('abc'),
      'p': Binding.of('ab cd', structure({'num': 'sg'})),
    });

    test('testStartsEndsContains', () {
      expect(
        holds(environment, 'starts_with', [variable('s'), string('hello')]),
        isTrue,
      );
      expect(
        holds(environment, 'starts_with', [variable('s'), string('world')]),
        isFalse,
      );
      expect(
        holds(environment, 'ends_with', [variable('s'), string('world')]),
        isTrue,
      );
      expect(
        holds(environment, 'ends_with', [variable('s'), string('hello')]),
        isFalse,
      );
      expect(
        holds(environment, 'contains', [variable('s'), string('lo wo')]),
        isTrue,
      );
      expect(
        holds(environment, 'contains', [variable('s'), string('xyz')]),
        isFalse,
      );
      expect(
        holds(environment, 'starts_with', [variable('u'), string('a')]),
        isFalse,
      );
    });

    test('testMatchesIsAFullMatch', () {
      expect(
        holds(bound({'s': string('abc123')}), 'matches', [
          variable('s'),
          string('[a-z]+[0-9]+'),
        ]),
        isTrue,
      );
      expect(
        holds(environment, 'matches', [string('abc'), string('[0-9]+')]),
        isFalse,
      );
      expect(
        holds(environment, 'matches', [string('abc'), string('ab')]),
        isFalse,
      );
      expect(
        holds(environment, 'matches', [string('ab'), string('a|ab')]),
        isTrue,
      );
      expect(
        holds(environment, 'matches', [string('a\nb'), string('(?s)a.b')]),
        isTrue,
      );
      expect(
        holds(environment, 'matches', [string('a\nb'), string('a.b')]),
        isFalse,
      );
    });

    test('testMatchesOutsideTheSubsetIsFalse', () {
      expect(
        holds(environment, 'matches', [string('abc'), string('[invalid')]),
        isFalse,
      );
      expect(
        holds(environment, 'matches', [string('aa'), string('a++')]),
        isFalse,
      );
      expect(
        holds(environment, 'matches', [string('a'), string('(?i)A')]),
        isFalse,
      );
    });

    test('testNotEmptyAndCase', () {
      expect(holds(environment, 'not_empty', [variable('s')]), isTrue);
      expect(holds(environment, 'not_empty', [variable('e')]), isFalse);
      expect(holds(environment, 'not_empty', [variable('u')]), isFalse);
      expect(holds(environment, 'not_empty', [variable('n')]), isFalse);
      expect(holds(environment, 'is_upper', [string('ABC')]), isTrue);
      expect(holds(environment, 'is_upper', [string('AbC')]), isFalse);
      expect(holds(environment, 'is_upper', [string('')]), isFalse);
      expect(holds(environment, 'is_lower', [string('abc')]), isTrue);
      expect(holds(environment, 'is_lower', [string('')]), isFalse);
      expect(holds(environment, 'is_capitalized', [string('Ábc')]), isTrue);
      expect(holds(environment, 'is_capitalized', [string('abc')]), isFalse);
      expect(holds(environment, 'is_capitalized', [string('1bc')]), isFalse);
    });

    test('testStringBuiltinsOnLabels', () {
      // S-C9: literals, labelled terminals and labelled nonterminals alike.
      expect(
        holds(environment, 'starts_with', [string('abc'), string('ab')]),
        isTrue,
      );
      expect(
        holds(environment, 'starts_with', [variable('w'), string('ab')]),
        isTrue,
      );
      expect(
        holds(environment, 'starts_with', [variable('p'), string('ab')]),
        isTrue,
      );
      expect(
        holds(environment, 'ends_with', [variable('p'), string('cd')]),
        isTrue,
      );
      expect(
        holds(environment, 'contains', [variable('p'), string('b c')]),
        isTrue,
      );
      expect(
        holds(environment, 'matches', [variable('w'), string('[a-c]+')]),
        isTrue,
      );
      expect(
        holds(environment, 'matches', [variable('p'), string('ab')]),
        isFalse,
      );
      expect(holds(environment, 'not_empty', [variable('w')]), isTrue);
      expect(holds(environment, 'is_lower', [variable('w')]), isTrue);
      expect(holds(environment, 'is_capitalized', [variable('w')]), isFalse);
    });

    test('testFeatureNamesResolveAsPaths', () {
      // A bare label in a grammar is parsed as a one-part feature path.
      expect(
        holds(environment, 'starts_with', [
          FeaturePath(['w']),
          string('ab'),
        ]),
        isTrue,
      );
    });
  });

  group('numbers', () {
    test('testComparisons', () {
      final five = NumericConstant.integer(5);
      final ten = NumericConstant.integer(10);
      final environment = bound({});
      expect(holds(environment, 'lt', [five, ten]), isTrue);
      expect(holds(environment, 'lt', [ten, five]), isFalse);
      expect(holds(environment, 'le', [five, ten]), isTrue);
      expect(holds(environment, 'le', [five, five]), isTrue);
      expect(holds(environment, 'le', [ten, five]), isFalse);
      expect(holds(environment, 'gt', [ten, five]), isTrue);
      expect(holds(environment, 'gt', [five, ten]), isFalse);
      expect(holds(environment, 'ge', [ten, five]), isTrue);
      expect(holds(environment, 'ge', [ten, ten]), isTrue);
      expect(holds(environment, 'ge', [five, ten]), isFalse);
      expect(holds(environment, 'lt', [string('5'), ten]), isFalse);
    });

    test('testMixedComparisonsAreExact', () {
      final environment = bound({});
      expect(
        holds(environment, 'lt', [
          NumericConstant.real(4.5),
          NumericConstant.integer(5),
        ]),
        isTrue,
      );
      expect(
        holds(environment, 'gt', [
          NumericConstant.real(5.5),
          NumericConstant.integer(5),
        ]),
        isTrue,
      );
      expect(
        holds(environment, 'le', [
          NumericConstant.real(5.0),
          NumericConstant.integer(5),
        ]),
        isTrue,
      );
      expect(
        holds(environment, 'lt', [
          NumericConstant.integer(-5),
          NumericConstant.real(-4.5),
        ]),
        isTrue,
      );
    });

    test('testLargeComparisonsAreExact', () {
      if (identical(0, 0.0)) {
        return; // On the web both are the same double.
      }
      final environment = bound({});
      final big = NumericConstant.integer(int.parse('9007199254740992'));
      final bigger = NumericConstant.integer(int.parse('9007199254740993'));
      expect(holds(environment, 'lt', [big, bigger]), isTrue);
      expect(holds(environment, 'ge', [big, bigger]), isFalse);
      expect(
        holds(environment, 'gt', [
          bigger,
          NumericConstant.real(9007199254740992.0),
        ]),
        isTrue,
      );
      expect(
        holds(environment, 'lt', [
          NumericConstant.integer(int.parse('9223372036854775807')),
          NumericConstant.real(9223372036854775808.0),
        ]),
        isTrue,
      );
    });

    test('testComparisonsWithNonFiniteNumbers', () {
      final environment = bound({});
      final nan = NumericConstant.real(double.nan);
      final infinity = NumericConstant.real(double.infinity);
      expect(
        holds(environment, 'lt', [nan, NumericConstant.integer(1)]),
        isFalse,
      );
      expect(holds(environment, 'ge', [nan, nan]), isFalse);
      expect(
        holds(environment, 'lt', [NumericConstant.integer(1 << 30), infinity]),
        isTrue,
      );
      expect(
        holds(environment, 'gt', [infinity, NumericConstant.real(1.5)]),
        isTrue,
      );
      expect(
        holds(environment, 'lt', [
          NumericConstant.real(double.negativeInfinity),
          NumericConstant.integer(-5),
        ]),
        isTrue,
      );
    });
  });

  group('positions', () {
    Environment at(List<int> positions) => bound({
      Environment.origin: Structure.of({
        for (final position in positions)
          '$position': BooleanConstant.trueValue,
      }),
    });

    test('testTokenPosition', () {
      expect(holds(at([0]), 'at_start'), isTrue);
      expect(holds(at([0]), 'at_position', [string('0')]), isTrue);
      expect(holds(at([0]), 'at_position', [string('1')]), isFalse);
      expect(holds(at([1, 3]), 'at_start'), isFalse);
      expect(holds(at([1, 3]), 'at_position', [string('1')]), isTrue);
      expect(holds(at([1, 3]), 'at_position', [string('3')]), isTrue);
      expect(holds(at([1, 3]), 'at_position', [string('2')]), isFalse);
      expect(holds(bound({}), 'at_start'), isFalse);
    });

    test('testPositionArguments', () {
      final environment = at([1]);
      expect(
        holds(environment, 'at_position', [NumericConstant.integer(1)]),
        isTrue,
      );
      expect(
        holds(environment, 'at_position', [NumericConstant.real(1.0)]),
        isTrue,
      );
      expect(holds(environment, 'at_position', [string('1.5')]), isFalse);
      expect(
        holds(environment, 'at_position', [NumericConstant.real(1.5)]),
        isFalse,
      );
      expect(
        holds(environment, 'at_position', [
          string('999999999999999999999999999999'),
        ]),
        isFalse,
      );
      expect(
        holds(at([0]), 'at_position', [NumericConstant.real(double.nan)]),
        isFalse,
      );
      expect(holds(at([0]), 'at_position', [string('-1')]), isFalse);
    });

    test('testAtEnd', () {
      expect(
        holds(bound({Environment.end: BooleanConstant.trueValue}), 'at_end'),
        isTrue,
      );
      expect(
        holds(bound({Environment.end: BooleanConstant.falseValue}), 'at_end'),
        isFalse,
      );
      expect(holds(bound({}), 'at_end'), isFalse);
    });

    test('testBefore', () {
      final environment = bound({
        Environment.next: Structure.of({'NUM': BooleanConstant.trueValue}),
        'c': string('NUM'),
      });
      expect(holds(environment, 'before', [string('NUM')]), isTrue);
      expect(
        holds(environment, 'before', [string('ID'), string('NUM')]),
        isTrue,
      );
      expect(holds(environment, 'before', [variable('c')]), isTrue);
      expect(holds(environment, 'before', [string('ID')]), isFalse);
      expect(holds(bound({}), 'before', [string('NUM')]), isFalse);
    });
  });

  group('totality', () {
    final arguments = <Value>[
      variable('Unbound'),
      string(''),
      string('abc'),
      string('999999999999999999999999999999'),
      string('1.5'),
      string('-1'),
      string('[unclosed'),
      NumericConstant.real(1.5),
      NumericConstant.real(double.nan),
      NumericConstant.real(double.infinity),
      NumericConstant.integer(1 << 30),
      BooleanConstant.trueValue,
      structure({'a': 'b'}),
      Binding.of('text'),
    ];

    test('testEveryBuiltinTotal', () {
      // Every builtin, at its minimum arity, with every argument kind,
      // returns true or false.
      final environment = Environment.of(standard)
          .lexical(const ['DEFAULT'], 1)
          .merge({
            Environment.origin: Structure.of({'1': BooleanConstant.trueValue}),
            Environment.end: BooleanConstant.falseValue,
            Environment.next: Structure.empty,
          });
      for (final phase in Phase.values) {
        for (final name in standard.names(phase)) {
          final entry = standard.entry(name)!;
          if (entry.minimum == 0) {
            continue;
          }
          for (final argument in arguments) {
            expect(
              () => environment.test(
                Call(name, List.filled(entry.minimum, argument)),
              ),
              returnsNormally,
              reason: '$name($argument)',
            );
          }
        }
      }
    });

    test('testOversizedLexicalNumberIsFalse', () {
      final environment = Environment.of(standard)
          .lexical(const ['DEFAULT'], 0);
      expect(
        environment.test(
          Call('at_char_position', [string('99999999999999999999999')]),
        ),
        isFalse,
      );
      expect(
        environment.test(
          Call('state_depth', [string('99999999999999999999999')]),
        ),
        isFalse,
      );
      expect(
        environment.test(
          Call('at_char_position', [NumericConstant.real(double.nan)]),
        ),
        isFalse,
      );
    });
  });
}
