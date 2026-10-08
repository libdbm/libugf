@TestOn('vm')
library;

import 'dart:math';

import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

/// Ported from Java `MathGeneratorTest` at unifica 8d8c01a. Sequences come
/// from `dart:math` `Random`, so they differ from Java's (R-GEN-4).
void main() {
  late Grammar grammar;
  late GrammarGenerator generator;
  late Parser parser;

  RegexTerminalGenerator terminals(
    String number,
    String sign,
    String variable,
  ) => RegexTerminalGenerator.builder()
      .register('[0-9]+', (features) => number)
      .register('[+-]?', (features) => sign)
      .register('[a-zA-Z_][a-zA-Z0-9_]*', (features) => variable)
      .fallback(const LiteralTerminalGenerator())
      .build();

  GrammarGenerator simple(TerminalGenerator generator, int seed, int depth) =>
      GrammarGenerator.builder(grammar)
          .terminal(generator)
          .random(Random(seed))
          .policy(Policy.defaults.copy(depth: depth))
          .build()
          .orElseThrow();

  setUp(() {
    grammar = GrammarFiles.parse('test/resources/math.ug').orElseThrow();
    final random = Random(42);
    const variables = ['x', 'y', 'z', 'a', 'b'];
    final generated = RegexTerminalGenerator.builder()
        .register('[0-9]+', (features) => '${random.nextInt(100)}')
        .register(
          '[+-]?',
          (features) =>
              random.nextDouble() < 0.3 ? '' : (random.nextBool() ? '+' : '-'),
        )
        .register(
          '[a-zA-Z_][a-zA-Z0-9_]*',
          (features) => variables[random.nextInt(variables.length)],
        )
        .fallback(const LiteralTerminalGenerator())
        .build();
    generator = GrammarGenerator.builder(grammar)
        .terminal(generated)
        .random(random)
        .policy(Policy.defaults.copy(depth: 15))
        .build()
        .orElseThrow();
    parser = ParserFactory.create(grammar).orElseThrow();
  });

  test('testGenerateSingleExpression', () {
    expect(
      generator.generateOne('expr', Structure.empty).orElseThrow(),
      isNotEmpty,
    );
  });

  test('testGenerateSymbols', () {
    for (final (symbol, count) in [('expr', 10), ('atom', 10), ('term', 5)]) {
      final sentences = generator
          .generate(symbol, Structure.empty, count)
          .orElseThrow();
      expect(sentences, hasLength(count), reason: symbol);
      expect(sentences, everyElement(isNotEmpty), reason: symbol);
    }
  });

  test('testGenerateVariables', () {
    final variables = generator
        .generate('variable', Structure.empty, 5)
        .orElseThrow();

    expect(variables, hasLength(5));
    for (final variable in variables) {
      expect(
        RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(variable),
        isTrue,
        reason: variable,
      );
    }
  });

  test('testGenerateNumbers', () {
    final numbers = simple(
      terminals('42', '', 'x'),
      42,
      5,
    ).generate('number', Structure.empty, 5);

    expect(numbers.orElseThrow(), hasLength(5));
  });

  test('testGeneratedExpressionsAreParseable', () {
    final expressions = simple(
      terminals('42', '+', 'x'),
      42,
      3,
    ).generate('expr', Structure.empty, 5).orElse(const []);

    for (final expression in expressions) {
      expect(parser.parse(expression).success, isTrue, reason: expression);
    }
  });

  test('testRoundTripParseAndGenerate', () {
    final atoms = simple(
      terminals('5', '', 'x'),
      999,
      2,
    ).generate('atom', Structure.empty, 20).orElse(const []);

    // Every returned sentence was verified by parsing as atom; as an
    // expression too, at least 16 of 20 parse, as in Java.
    expect(
      atoms.where((atom) => parser.parse(atom).success).length,
      greaterThanOrEqualTo(16),
    );
  });

  test('testDeterministicGeneration', () {
    String? expression() {
      final random = Random(123);
      return GrammarGenerator.builder(grammar)
          .terminal(RegexTerminalGenerator.numbers(random))
          .random(random)
          .policy(Policy.defaults.copy(depth: 15))
          .build()
          .orElseThrow()
          .generateOne('expr', Structure.empty)
          .orElse('');
    }

    expect(expression(), expression());
  });

  test('testGenerateFunctions', () {
    final generated = simple(
      RegexTerminalGenerator.builder()
          .register('[0-9]+', (features) => '5')
          .register('[a-zA-Z_][a-zA-Z0-9_]*', (features) => 'x')
          .fallback(const LiteralTerminalGenerator())
          .build(),
      42,
      10,
    ).generate('expr', Structure.empty, 20).orElse(const []);

    expect(
      generated.any(
        (expression) => ['sin', 'cos', 'sqrt', 'log'].any(expression.contains),
      ),
      isTrue,
    );
  });
}
