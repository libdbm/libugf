import 'package:test/test.dart';
import 'package:libugf/libugf.dart';

void main() {
  group('StringConstant', () {
    test('creates with value', () {
      const s = StringConstant('hello');
      expect(s.value, equals('hello'));
      expect(s.isAtomic, isTrue);
      expect(s.isVariable, isFalse);
    });

    test('factory constructor', () {
      final s = StringConstant.of('world');
      expect(s.value, equals('world'));
    });

    test('equality', () {
      const a = StringConstant('test');
      const b = StringConstant('test');
      const c = StringConstant('other');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('display', () {
      const s = StringConstant('hello');
      expect(s.display(), equals('hello'));
    });
  });

  group('NumericConstant', () {
    test('testCreatesInteger', () {
      final n = NumericConstant.integer(42);
      expect(n.value, 42);
      expect(n.floating, isFalse);
      expect(n.asInt, 42);
      expect(n.isAtomic, isTrue);
    });

    test('testCreatesReal', () {
      final n = NumericConstant.real(3.14);
      expect(n.value, 3.14);
      expect(n.floating, isTrue);
      expect(n.asDouble, 3.14);
    });

    test('testFloatingIsStoredNotInferred', () {
      // On the web 1.0 is an int; the flag must come from construction.
      expect(NumericConstant.real(1.0).floating, isTrue);
      expect(NumericConstant.integer(1).floating, isFalse);
      expect(NumericConstant(2.7).value, 2);
      expect(NumericConstant(2.7).floating, isFalse);
    });

    test('testParsesLiterals', () {
      expect(
        NumericConstant.parse('123').orElseThrow(),
        NumericConstant.integer(123),
      );
      expect(NumericConstant.parse('123').orElseThrow().floating, isFalse);
      expect(NumericConstant.parse(' -456 ').orElseThrow().value, -456);
      expect(NumericConstant.parse('3.14').orElseThrow().floating, isTrue);
      expect(NumericConstant.parse('1.5e10').orElseThrow().value, 1.5e10);
      expect(NumericConstant.parse('1e10').orElseThrow().floating, isTrue);
      expect(NumericConstant.parse('.5').orElseThrow().value, 0.5);
    });

    test('testInvalidLiteralIsAFailure', () {
      for (final literal in ['', 'abc', '1.2.3', '--1', '1e']) {
        final result = NumericConstant.parse(literal);
        expect(
          result,
          isA<Failure<NumericConstant, ErrorDetails>>(),
          reason: literal,
        );
        expect(
          (result as Failure<NumericConstant, ErrorDetails>).error.code,
          'number.invalid',
        );
      }
    });

    test('testIntegerLiteralOutOfRangeIsAFailure', () {
      // D5: 64-bit on the VM and wasm; on the web exact only to 2^53 - 1.
      final limit = identical(0, 0.0)
          ? '9007199254740991'
          : '9223372036854775807';
      final beyond = identical(0, 0.0)
          ? '9007199254740992'
          : '9223372036854775808';
      expect(
        NumericConstant.parse(limit),
        isA<Success<NumericConstant, ErrorDetails>>(),
      );
      expect(
        NumericConstant.parse('-$limit'),
        isA<Success<NumericConstant, ErrorDetails>>(),
      );
      expect(
        NumericConstant.parse(beyond),
        isA<Failure<NumericConstant, ErrorDetails>>(),
      );
      expect(
        NumericConstant.parse('-1$beyond'),
        isA<Failure<NumericConstant, ErrorDetails>>(),
      );
    });

    test('testIsIntegerAndIsFloating', () {
      expect(NumericConstant.isInteger('123'), isTrue);
      expect(NumericConstant.isInteger('-456'), isTrue);
      expect(NumericConstant.isInteger('3.14'), isFalse);
      expect(NumericConstant.isInteger(''), isFalse);
      expect(NumericConstant.isFloating('3.14'), isTrue);
      expect(NumericConstant.isFloating('1e10'), isTrue);
      expect(NumericConstant.isFloating('123'), isFalse);
    });

    // Ported from Java UnificationTests#testNumericEquality (S-F4).
    test('testNumericEquality', () {
      final values = [
        NumericConstant.integer(1),
        NumericConstant.parse('1').orElseThrow(),
        NumericConstant.parse('1.0').orElseThrow(),
        NumericConstant.real(1.0),
      ];
      for (final a in values) {
        for (final b in values) {
          expect(a, b, reason: '$a vs $b');
          expect(a.hashCode, b.hashCode, reason: '$a vs $b');
        }
      }
      expect(NumericConstant.integer(1), isNot(NumericConstant.real(1.5)));
      expect(NumericConstant.real(0.0), NumericConstant.real(-0.0));
      expect(
        NumericConstant.real(0.0).hashCode,
        NumericConstant.real(-0.0).hashCode,
      );
      expect(
        NumericConstant.real(double.nan),
        NumericConstant.real(double.nan),
      );
      expect(
        NumericConstant.real(double.nan).hashCode,
        NumericConstant.real(double.nan).hashCode,
      );
      expect(NumericConstant.integer(1), isNot(const StringConstant('1')));
      expect(
        NumericConstant.real(double.infinity),
        isNot(NumericConstant.integer(1)),
      );
    });

    test('testLargeIntegersCompareExactly', () {
      // Exact only where integers are 64-bit (VM, wasm); on the web both are
      // the same double.
      if (identical(0, 0.0)) {
        return;
      }
      expect(
        NumericConstant.integer(int.parse('9007199254740993')),
        isNot(NumericConstant.real(9007199254740992.0)),
      );
      expect(
        NumericConstant.integer(int.parse('9007199254740992')),
        NumericConstant.real(9007199254740992.0),
      );
      expect(
        NumericConstant.integer(int.parse('-9223372036854775808')),
        NumericConstant.real(-9223372036854775808.0),
      );
      expect(
        NumericConstant.integer(int.parse('9223372036854775807')),
        isNot(NumericConstant.real(9223372036854775808.0)),
      );
    });

    test('testText', () {
      expect(NumericConstant.integer(1).text, isNull);
    });
  });

  group('BooleanConstant', () {
    test('testSingletonInstances', () {
      expect(BooleanConstant.of(true), same(BooleanConstant.trueValue));
      expect(BooleanConstant.of(false), same(BooleanConstant.falseValue));
    });

    test('testParsesStrings', () {
      expect(
        BooleanConstant.parse('true').orElseThrow(),
        BooleanConstant.trueValue,
      );
      expect(
        BooleanConstant.parse('TRUE').orElseThrow(),
        BooleanConstant.trueValue,
      );
      expect(
        BooleanConstant.parse('false').orElseThrow(),
        BooleanConstant.falseValue,
      );
    });

    test('testInvalidStringIsAFailure', () {
      final result = BooleanConstant.parse('yes');
      expect(
        (result as Failure<BooleanConstant, ErrorDetails>).error.code,
        'boolean.invalid',
      );
    });

    test('testIsBoolean', () {
      expect(BooleanConstant.isBoolean('true'), isTrue);
      expect(BooleanConstant.isBoolean('FALSE'), isTrue);
      expect(BooleanConstant.isBoolean('yes'), isFalse);
    });

    test('testIsAtomic', () {
      expect(BooleanConstant.trueValue.isAtomic, isTrue);
      expect(BooleanConstant.trueValue.isVariable, isFalse);
      expect(BooleanConstant.trueValue.text, isNull);
    });
  });

  group('text', () {
    test('testTextOfStringsAndBindingsOnly', () {
      expect(const StringConstant('hi').text, 'hi');
      expect(Binding.of('dogs').text, 'dogs');
      expect(const Variable('x').text, isNull);
      expect(FeaturePath(['w', 'f']).text, isNull);
      expect(Structure.empty.text, isNull);
    });
  });

  group('Variable', () {
    test('creates with name', () {
      const v = Variable('x');
      expect(v.name, equals('x'));
      expect(v.isVariable, isTrue);
      expect(v.isAtomic, isFalse);
    });

    test('factory removes ? prefix', () {
      final v = Variable.of('?x');
      expect(v.name, equals('x'));
    });

    test('factory handles name without prefix', () {
      final v = Variable.of('y');
      expect(v.name, equals('y'));
    });

    test('display includes ? prefix', () {
      const v = Variable('n');
      expect(v.display(), equals('?n'));
    });

    test('equality', () {
      const a = Variable('x');
      const b = Variable('x');
      const c = Variable('y');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('FeaturePath', () {
    test('creates from list', () {
      final p = FeaturePath(['W', 'cat', 'num']);
      expect(p.parts, equals(['W', 'cat', 'num']));
      expect(p.root, equals('W'));
      expect(p.path, equals(['cat', 'num']));
    });

    test('parses from string', () {
      final p = FeaturePath.parse('X.feat.sub');
      expect(p.parts, equals(['X', 'feat', 'sub']));
    });

    test('isSimple', () {
      final simple = FeaturePath(['X']);
      final complex = FeaturePath(['X', 'cat']);
      expect(simple.isSimple, isTrue);
      expect(complex.isSimple, isFalse);
    });

    test('isVariable', () {
      final p = FeaturePath(['X', 'cat']);
      expect(p.isVariable, isTrue);
      expect(p.isAtomic, isFalse);
    });

    test('throws on empty parts', () {
      expect(() => FeaturePath([]), throwsArgumentError);
    });

    test('equality', () {
      final a = FeaturePath(['X', 'cat']);
      final b = FeaturePath(['X', 'cat']);
      final c = FeaturePath(['Y', 'cat']);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('display', () {
      final p = FeaturePath(['W', 'cat', 'num']);
      expect(p.display(), equals('W.cat.num'));
    });
  });

  group('Structure', () {
    test('testEmpty', () {
      expect(Structure.empty.isEmpty, isTrue);
      expect(Structure.empty.size, 0);
    });

    test('testOfMap', () {
      final s = Structure.of({
        'cat': const StringConstant('noun'),
        'num': const StringConstant('sing'),
      });
      expect(s.size, 2);
      expect(s['cat'], const StringConstant('noun'));
      expect(s.get('num'), const StringConstant('sing'));
      expect(s.has('cat'), isTrue);
      expect(s.has('case'), isFalse);
    });

    test('testIsImmutable', () {
      final inner = Structure.of({'x': const StringConstant('inner')});
      final outer = Structure.of({'nested': inner});
      final changed = inner.plus('x', const StringConstant('modified'));

      expect(changed['x'], const StringConstant('modified'));
      expect(inner['x'], const StringConstant('inner'));
      expect(
        (outer['nested']! as Structure)['x'],
        const StringConstant('inner'),
      );
    });

    test('testIsVariableAndIsAtomic', () {
      expect(Structure.empty.isVariable, isFalse);
      expect(Structure.empty.isAtomic, isFalse);
    });

    test('testEquality', () {
      final a = Structure.of({'cat': const StringConstant('noun')});
      final b = Structure.of({'cat': const StringConstant('noun')});
      final c = Structure.of({'cat': const StringConstant('verb')});
      expect(a, b);
      expect(a, isNot(c));
    });

    test('testDisplay', () {
      expect(
        Structure.of({'cat': const StringConstant('noun')}).display(),
        '{cat: noun}',
      );
    });
  });

  group('Binding', () {
    test('testCreatesWithTextOnly', () {
      final b = Binding.of('hello');
      expect(b.text, 'hello');
      expect(b.features.isEmpty, isTrue);
    });

    test('testCreatesWithFeatures', () {
      final f = Structure.of({'cat': const StringConstant('noun')});
      final b = Binding.of('word', f);
      expect(b.text, 'word');
      expect(b.features, f);
    });

    test('testIsVariableAndIsAtomic', () {
      final b = Binding.of('test');
      expect(b.isVariable, isFalse);
      expect(b.isAtomic, isFalse);
    });

    test('testDisplay', () {
      expect(Binding.of('hello').display(), "'hello'");
      expect(
        Binding.of(
          'word',
          Structure.of({'cat': const StringConstant('n')}),
        ).display(),
        "'word'{cat: n}",
      );
    });

    test('testEquality', () {
      expect(Binding.of('test'), Binding.of('test'));
      expect(Binding.of('test'), isNot(Binding.of('other')));
    });
  });
}
