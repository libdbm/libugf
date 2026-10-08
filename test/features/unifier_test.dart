import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

/// Value unification with bindings flowing back through [bindings], as most
/// of the ported Java tests expect.
Value? unify(Value left, Value right, [Map<String, Value>? bindings]) {
  final working = bindings ?? <String, Value>{};
  return switch (Unifier.unify(left, right, Bindings(working))) {
    Success(:final value) => () {
      working.addAll(value.bindings.values);
      return value.value;
    }(),
    Failure() => null,
  };
}

Structure? merge(Structure left, Structure right) =>
    switch (Unifier.structures(left, right)) {
      Success(:final value) => value.value,
      Failure() => null,
    };

Structure structure(Map<String, Object> features) => Structure.of({
  for (final MapEntry(:key, :value) in features.entries)
    key: switch (value) {
      final String text => StringConstant(text),
      final int number => NumericConstant.integer(number),
      final Value item => item,
      _ => throw ArgumentError(value),
    },
});

/// A structure nested [depth] levels deep: `{next: {next: ... {leaf: x}}}`.
Structure deep(int depth, Value leaf) {
  var current = Structure.of({'leaf': leaf});
  for (var index = 0; index < depth; index++) {
    current = Structure.of({'next': current});
  }
  return current;
}

String code(Result<Object, ErrorDetails> result) =>
    (result as Failure<Object, ErrorDetails>).error.code;

/// Ported from Java `UnificationTests` at unifica 8d8c01a. The three-way
/// unification tests are not ported (SPEC R-FEAT-4), nor the null-argument
/// tests, which Dart's types rule out.
void main() {
  group('single operation', () {
    test('testOccursThroughBinding', () {
      const x = Variable('x');
      final binding = Binding.of('t', Structure.of({'f': x}));

      expect(code(Unifier.unify(x, binding)), 'unification.occurs');
    });

    test('testBindingsAreNotModified', () {
      const bindings = Bindings.empty;

      Unifier.unify(const Variable('x'), const StringConstant('a'), bindings);

      expect(bindings.isEmpty, isTrue);
    });

    test('testStructureEqualityUsesNumericEquality', () {
      final a = Structure.of({'n': NumericConstant.integer(2)});
      final b = Structure.of({'n': NumericConstant.real(2.0)});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('testDeepStructure', () {
      const depth = 10000;
      final left = deep(depth, const Variable('x'));
      final right = deep(depth, const StringConstant('v'));

      final unified = merge(left, right)!;

      expect(unified, right);
      expect(unified.hashCode, right.hashCode);
      expect(unified.display(), isNotEmpty);
      expect(
        code(Unifier.unify(const Variable('x'), left)),
        'unification.occurs',
      );
    });

    test('testResultIsSubstituted', () {
      final left = structure({
        'a': const Variable('x'),
        'b': const Variable('x'),
      });
      final right = structure({'b': 'v'});

      expect(unify(left, right), structure({'a': 'v', 'b': 'v'}));
    });

    test('testMismatchCodeAndPath', () {
      final result = Unifier.unify(
        structure({
          'agr': structure({'num': 'sg'}),
        }),
        structure({
          'agr': structure({'num': 'pl'}),
        }),
      );
      final error = (result as Failure<Unification<Value>, ErrorDetails>).error;
      expect(error.code, 'unification.mismatch');
      expect(error.message, "Feature 'agr.num': Values don't match: sg vs pl");
    });

    test('testTypeMismatchNamesTheKinds', () {
      final result = Unifier.unify(const StringConstant('a'), Structure.empty);
      expect(
        (result as Failure<Unification<Value>, ErrorDetails>).error.message,
        'Type mismatch: StringConstant vs Structure',
      );
    });

    test('testSubstitute', () {
      final value = structure({
        'a': const Variable('x'),
        'b': structure({'c': const Variable('y')}),
      });
      final bindings = Bindings.empty
          .plus('x', const StringConstant('1'))
          .plus('y', const Variable('x'));

      expect(
        Unifier.substitute(value, bindings),
        structure({
          'a': '1',
          'b': structure({'c': '1'}),
        }),
      );
    });

    test('testBindingFeaturesMergeIntoStructure', () {
      final binding = Binding.of(
        'dog',
        structure({'num': const Variable('n')}),
      );
      final result = unify(binding, structure({'num': 'sg'}));
      expect(result, structure({'num': 'sg'}));
    });
  });

  group('structure', () {
    test('testEmptyStructure', () {
      final fs = Structure.empty;
      expect(fs.isEmpty, isTrue);
      expect(fs.size, 0);
      expect(fs.display(), '{}');
    });

    test('testBuilderCreatesStructureWithFeatures', () {
      final fs = Structure.builder()
          .put('num', const StringConstant('sing'))
          .put('person', const StringConstant('3'))
          .put('case', const StringConstant('nom'))
          .build();

      expect(fs.isEmpty, isFalse);
      expect(fs.size, 3);
      expect(fs.has('num') && fs.has('person') && fs.has('case'), isTrue);
    });

    test('testPlusLeavesOriginalUnchanged', () {
      final fs = Structure.empty;

      final updated = fs.plus('num', const StringConstant('sing'));

      expect(fs.get('num'), isNull);
      expect(updated.get('num'), const StringConstant('sing'));
    });

    test('testBuilderFromBaseLeavesBaseUnchanged', () {
      final base = structure({'inner': 'original'});

      final derived = Structure.builder(base)
          .put('inner', const StringConstant('modified'))
          .put('extra', const StringConstant('x'))
          .build();

      expect(base.get('inner'), const StringConstant('original'));
      expect(base.size, 1);
      expect(derived.get('inner'), const StringConstant('modified'));
    });

    test('testOfCopiesItsMap', () {
      final map = <String, Value>{'a': const StringConstant('1')};
      final fs = Structure.of(map);
      map['b'] = const StringConstant('2');

      expect(fs.size, 1);
    });

    test('testKeysAreUnmodifiable', () {
      final fs = structure({'a': '1', 'b': '2'});

      expect(fs.keys, {'a', 'b'});
      expect(() => fs.keys.remove('a'), throwsUnsupportedError);
      expect(() => fs.keys.add('c'), throwsUnsupportedError);
      expect(fs.size, 2);
    });

    test('testDisplay', () {
      final display = structure({'num': 'sing', 'case': 'nom'}).display();
      expect(display, startsWith('{'));
      expect(display, endsWith('}'));
      expect(display, contains('num: sing'));
      expect(display, contains('case: nom'));
      expect(
        structure({
          'a': structure({'b': 'c'}),
        }).display(),
        '{a: {b: c}}',
      );
    });

    test('testEqualityComparesFeatures', () {
      expect(structure({'num': 'sing'}), structure({'num': 'sing'}));
      expect(structure({'num': 'sing'}), isNot(structure({'num': 'plur'})));
      expect(structure({'a': '1'}), isNot(structure({'a': '1', 'b': '2'})));
      expect(
        structure({'a': '1', 'b': '2'}).hashCode,
        structure({'b': '2', 'a': '1'}).hashCode,
      );
    });

    test('testDeepEqualityHashAndDisplayDoNotRecurse', () {
      final left = deep(100000, const StringConstant('v'));
      final right = deep(100000, const StringConstant('v'));

      expect(left, right);
      expect(left.hashCode, right.hashCode);
      expect(left.display().length, greaterThan(100000));
    });
  });

  group('utilities', () {
    test('testFromMapConvertsStrings', () {
      final fs = Utilities.fromMap({
        'num': 'sing',
        'person': 'third',
        'var': '?x',
      });

      expect(fs.size, 3);
      expect(fs.get('num'), isA<StringConstant>());
      expect(fs.get('person'), isA<StringConstant>());
      expect(fs.get('var'), const Variable('x'));
    });

    test('testFromMapRecognizesNumbersAndBooleans', () {
      final fs = Utilities.fromMap({
        'int': '42',
        'float': '3.14',
        't': 'true',
        'f': 'false',
        'T': 'TRUE',
      });

      expect(fs.get('int'), NumericConstant.integer(42));
      expect(fs.get('float'), NumericConstant.real(3.14));
      expect(fs.get('t'), BooleanConstant.trueValue);
      expect(fs.get('f'), BooleanConstant.falseValue);
      expect(fs.get('T'), BooleanConstant.trueValue);
    });

    test('testFromMapSkipsNullValues', () {
      final fs = Utilities.fromMap({'valid': 'value', 'missing': null});

      expect(fs.size, 1);
      expect(fs.has('missing'), isFalse);
    });

    test('testValueToString', () {
      expect(Utilities.valueToString(const StringConstant('test')), 'test');
      expect(Utilities.valueToString(NumericConstant.integer(42)), '42');
      expect(Utilities.valueToString(BooleanConstant.trueValue), 'true');
      expect(Utilities.valueToString(BooleanConstant.falseValue), 'false');
      expect(Utilities.valueToString(Variable.of('x')), '?x');
      expect(Utilities.valueToString(null), isNull);
      expect(Utilities.valueToString(structure({'a': 'b'})), contains('a'));
    });
  });

  group('atomic values', () {
    test('testIdenticalStringsUnify', () {
      expect(
        unify(const StringConstant('sing'), const StringConstant('sing')),
        const StringConstant('sing'),
      );
      expect(
        unify(const StringConstant(''), const StringConstant('')),
        isNotNull,
      );
    });

    test('testDifferentStringsDoNotUnify', () {
      expect(
        unify(const StringConstant('sing'), const StringConstant('plur')),
        isNull,
      );
    });

    test('testNumbersUnifyByValue', () {
      expect(
        unify(NumericConstant.integer(42), NumericConstant.integer(42)),
        NumericConstant.integer(42),
      );
      expect(
        unify(NumericConstant.integer(42), NumericConstant.integer(43)),
        isNull,
      );
      expect(
        unify(NumericConstant.integer(5), NumericConstant.real(5.0)),
        isNotNull,
      );
      expect(
        unify(NumericConstant.real(3.14), NumericConstant.real(3.14)),
        isNotNull,
      );
      expect(
        unify(
          NumericConstant.parse('42').orElseThrow(),
          NumericConstant.integer(42),
        ),
        isNotNull,
      );
    });

    test('testDifferentKindsWithSameDisplayDoNotUnify', () {
      expect(
        unify(const StringConstant('42'), NumericConstant.integer(42)),
        isNull,
      );
      expect(
        unify(BooleanConstant.trueValue, const StringConstant('true')),
        isNull,
      );
      expect(
        unify(BooleanConstant.trueValue, NumericConstant.integer(1)),
        isNull,
      );
    });

    test('testBooleans', () {
      expect(
        unify(BooleanConstant.trueValue, BooleanConstant.trueValue),
        BooleanConstant.trueValue,
      );
      expect(
        unify(BooleanConstant.falseValue, BooleanConstant.falseValue),
        BooleanConstant.falseValue,
      );
      expect(
        unify(BooleanConstant.trueValue, BooleanConstant.falseValue),
        isNull,
      );
    });
  });

  group('variables', () {
    test('testVariableBindsToConstants', () {
      for (final constant in <Value>[
        const StringConstant('sing'),
        BooleanConstant.trueValue,
        NumericConstant.integer(42),
      ]) {
        final bindings = <String, Value>{};
        expect(unify(Variable.of('?x'), constant, bindings), constant);
        expect(bindings['x'], constant);
      }
    });

    test('testDifferentVariablesUnify', () {
      final bindings = <String, Value>{};
      final result = unify(Variable.of('?x'), Variable.of('?y'), bindings);

      expect(result, isA<Variable>());
      expect(bindings['x'], Variable.of('?y'));
    });

    test('testSameVariableUnifiesWithItself', () {
      expect(unify(Variable.of('?x'), Variable.of('?x')), Variable.of('?x'));
    });

    test('testDereferencingFollowsBindings', () {
      final bindings = <String, Value>{
        'x': Variable.of('?y'),
        'y': const StringConstant('value'),
      };
      expect(
        unify(Variable.of('?x'), const StringConstant('value'), bindings),
        const StringConstant('value'),
      );
    });

    test('testOccursCheck', () {
      final v = Variable.of('?x');
      expect(unify(v, structure({'feature': v})), isNull);
      expect(
        unify(
          v,
          structure({
            'outer': structure({'inner': v}),
          }),
        ),
        isNull,
      );
    });
  });

  group('feature structures', () {
    test('testDisjointFeaturesUnify', () {
      expect(
        merge(
          structure({'num': 'sing', 'person': '3'}),
          structure({'case': 'nom'}),
        ),
        structure({'num': 'sing', 'person': '3', 'case': 'nom'}),
      );
    });

    test('testOverlappingFeaturesUnify', () {
      expect(
        merge(
          structure({'num': 'sing', 'person': '3'}),
          structure({'num': 'sing'}),
        ),
        structure({'num': 'sing', 'person': '3'}),
      );
    });

    test('testConflictingValuesFail', () {
      expect(
        merge(structure({'num': 'sing'}), structure({'num': 'plur'})),
        isNull,
      );
    });

    test('testVariablesAreBound', () {
      expect(
        merge(
          structure({'num': Variable.of('?n')}),
          structure({'num': 'sing'}),
        ),
        structure({'num': 'sing'}),
      );
    });

    test('testEmptyStructuresUnify', () {
      expect(
        merge(Structure.empty, Structure.builder().build())!.isEmpty,
        isTrue,
      );
    });

    test('testNestedStructures', () {
      final left = structure({
        'num': 'sing',
        'agr': structure({'case': 'nom', 'gender': 'masc'}),
      });
      final right = structure({
        'agr': structure({'case': 'nom'}),
      });
      expect(merge(left, right), left);
      expect(
        merge(
          structure({
            'agr': structure({'case': 'nom'}),
          }),
          structure({
            'agr': structure({'case': 'acc'}),
          }),
        ),
        isNull,
      );
    });

    test('testNumericFeatures', () {
      expect(
        merge(structure({'count': 5}), structure({'count': 5})),
        structure({'count': 5}),
      );
    });
  });

  group('complex scenarios', () {
    test('testSharedVariableAcrossFeatures', () {
      final v = Variable.of('?x');
      expect(
        merge(
          structure({'subj_num': v, 'verb_num': v}),
          structure({'subj_num': 'sing'}),
        ),
        structure({'subj_num': 'sing', 'verb_num': 'sing'}),
      );
    });

    test('testTransitiveBindings', () {
      final bindings = <String, Value>{};
      unify(Variable.of('?x'), Variable.of('?y'), bindings);
      unify(Variable.of('?y'), Variable.of('?z'), bindings);

      expect(
        unify(Variable.of('?z'), const StringConstant('value'), bindings),
        const StringConstant('value'),
      );
    });

    test('testMultipleVariablesNested', () {
      final left = structure({
        'agr': structure({
          'num': Variable.of('?n'),
          'person': Variable.of('?p'),
        }),
      });
      final right = structure({
        'agr': structure({'num': 'plur'}),
      });

      final agr = merge(left, right)!.get('agr')! as Structure;
      expect(agr.get('num'), const StringConstant('plur'));
    });

    test('testSubstitutionReplacesEveryOccurrence', () {
      final v = Variable.of('?x');
      final left = structure({
        'a': v,
        'b': v,
        'nested': structure({'c': v}),
      });

      expect(
        merge(left, structure({'a': 'value'})),
        structure({
          'a': 'value',
          'b': 'value',
          'nested': structure({'c': 'value'}),
        }),
      );
    });

    test('testMixedTypes', () {
      final left = structure({
        'str': 'text',
        'num': 42,
        'var': Variable.of('?x'),
        'nested': structure({'inner': 'value'}),
      });
      final unified = merge(left, structure({'var': 'bound', 'extra': 'new'}))!;

      expect(unified.size, 5);
      expect(unified.get('var'), const StringConstant('bound'));
      expect(unified.get('num'), isA<NumericConstant>());
      expect(unified.get('nested'), isA<Structure>());
    });
  });
}
