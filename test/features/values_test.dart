import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Variable suffixed(Variable variable) => Variable("${variable.name}'1");

/// Ported from Java `ValuesTests` at unifica 8d8c01a.
void main() {
  test('testRenamesNestedVariables', () {
    final value = Structure.of({
      'a': const Variable('X'),
      'b': Structure.of({'c': const Variable('Y')}),
    });

    final renamed = Values.rename(value, suffixed) as Structure;

    expect(renamed.get('a'), const Variable("X'1"));
    expect((renamed.get('b')! as Structure).get('c'), const Variable("Y'1"));
  });

  test('testRenamesInsideBindings', () {
    final binding = Binding.of('dog', Structure.of({'n': const Variable('N')}));
    final value = Structure.of({'b': binding});

    final renamed = Values.rename(value, suffixed) as Structure;

    final inner = renamed.get('b')! as Binding;
    expect(inner.text, 'dog');
    expect(inner.features.get('n'), const Variable("N'1"));
  });

  test('testUnchangedValueIsSameInstance', () {
    final value = Structure.of({'a': const StringConstant('b')});

    expect(Values.rename(value, suffixed), same(value));
  });

  test('testSortedVisitOrder', () {
    final value = Structure.of({
      'z': const Variable('A'),
      'a': const Variable('B'),
    });
    final order = <String>[];

    Values.rename(value, (variable) {
      order.add(variable.name);
      return variable;
    });

    expect(order, ['B', 'A']);
  });

  test('testRenamesALeaf', () {
    expect(Values.rename(const Variable('X'), suffixed), const Variable("X'1"));
    expect(
      Values.rename(const StringConstant('s'), suffixed),
      const StringConstant('s'),
    );
  });

  test('testDeepValue', () {
    Value value = const Variable('X');
    for (var depth = 0; depth < 100000; depth++) {
      value = Structure.of({'n': value});
    }

    var renamed = Values.rename(value, suffixed);

    while (renamed is Structure) {
      renamed = renamed.get('n')!;
    }
    expect(renamed, const Variable("X'1"));
  });
}
