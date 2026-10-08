@TestOn('vm')
library;

import 'dart:io';

import 'package:libugf/libugf.dart' show GrammarLoader, Parser, ParserFactory;
import 'package:test/test.dart';

import 'math.dart';

/// Ported from Java `MathParserTests` at unifica 8d8c01a. The two tests that
/// only printed results assert them.
void main() {
  late Parser parser;

  setUpAll(() {
    parser = GrammarLoader.parse(
      File('test/resources/math.ug').readAsStringSync(),
    ).flatMap((grammar) => ParserFactory.create(grammar)).orElseThrow();
  });

  Expression parse(String input) {
    final result = parser.parse(input);
    expect(result.tree, isNotNull, reason: 'Should parse: $input');
    return build(result.tree!);
  }

  double value(String input, [Map<String, double> variables = const {}]) =>
      evaluate(parse(input), variables);

  test('testParsesSimpleNumber', () {
    final expression = parse('42');

    expect(expression, isA<Constant>());
    expect((expression as Constant).value, 42.0);
    expect(evaluate(expression), 42.0);
  });

  test('testParsesAddition', () {
    expect(parse('2 + 3'), isA<Binary>());
    expect(value('2 + 3'), 5.0);
  });

  test('testParsesArithmetic', () {
    expect(value('10 - 4'), 6.0);
    expect(value('10 - -4'), 14.0);
    expect(value('3 * 7'), 21.0);
    expect(value('15 / 3'), 5.0);
    expect(value('2 ^ 8'), 256.0);
  });

  test('testParsesOperatorPrecedence', () {
    expect(value('2 + 3 * 4'), 14.0);
    expect(value('(2 + 3) * 4'), 20.0);
    expect(value('((1 + 2) * (3 + 4))'), 21.0);
  });

  test('testParsesUnaryOperators', () {
    expect(value('-5'), -5.0);
    expect(value('+5'), 5.0);
  });

  test('testParsesVariables', () {
    expect(value('x + y', {'x': 10.0, 'y': 5.0}), 15.0);
  });

  test('testParsesFunctions', () {
    expect(value('sqrt(16)'), 4.0);
    expect(value('abs(-42)'), 42.0);
    expect(value('pow(2,10)'), 1024.0);
    expect(value('max(5,12)'), 12.0);
    expect(value('sqrt(16)+2*3'), 10.0);
  });

  test('testVariousExpressions', () {
    const examples = {
      '2 + 3': ('(2.0 + 3.0)', 5.0),
      '10 - 4 * 2': ('(10.0 - (4.0 * 2.0))', 2.0),
      '( 2 + 3 ) * 4': ('((2.0 + 3.0) * 4.0)', 20.0),
      '2 ^ 8': ('(2.0 ^ 8.0)', 256.0),
      'sqrt ( 25 )': ('sqrt(25.0)', 5.0),
      'max ( 10 , 20 )': ('max(10.0, 20.0)', 20.0),
      '3 + 4 * 5 - 2': ('((3.0 + (4.0 * 5.0)) - 2.0)', 21.0),
      '- 5 + 10': ('(-5.0 + 10.0)', 5.0),
      'abs ( - 42 )': ('abs(-42.0)', 42.0),
    };

    for (final MapEntry(key: input, value: (pretty, result))
        in examples.entries) {
      final expression = parse(input);
      expect(display(expression), pretty, reason: input);
      expect(evaluate(expression), result, reason: input);
    }
  });

  test('testVariableBinding', () {
    final expression = parse('x * x + y * y');

    for (final (x, y, expected) in [
      (3.0, 4.0, 25.0),
      (5.0, 12.0, 169.0),
      (0.0, 0.0, 0.0),
    ]) {
      expect(evaluate(expression, {'x': x, 'y': y}), closeTo(expected, 0.001));
    }
  });

  test('testParsesWithoutSpaces', () {
    expect(value('5-5'), 0.0);
    expect(value('5--5'), 10.0);
    expect(value('5+-5'), 0.0);
    expect(value('10*-2'), -20.0);
  });

  test('testScientificNotation', () {
    expect(value('1.5e+2 + 0.5'), 150.5);
    expect(value('2.0e3'), 2000.0);
  });
}
