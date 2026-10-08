import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

final lexical = Predicates.builder().lexical().build();

Call call(String name, [List<String> args = const []]) =>
    Call(name, [for (final arg in args) StringConstant(arg)]);

Environment lexing(int position, List<String> states) =>
    Environment.of(lexical).lexical(states, position);

/// Ported from Java `PredicatesTests` at unifica 8d8c01a: the registry,
/// environment and lexical predicates. The tests of the standard builtins
/// belong to Task 11.
void main() {
  test('testLexicalPredicateNames', () {
    expect(lexical.names(Phase.lexical), {
      'in_state',
      'state_depth',
      'state_contains',
      'at_char_start',
      'at_char_position',
    });
    expect(lexical.names(Phase.syntactic), isEmpty);
  });

  test('testInState', () {
    final environment = lexing(0, ['DEFAULT', 'IN']);

    expect(environment.test(call('in_state', ['IN'])), isTrue);
    expect(environment.test(call('in_state', ['X', 'IN'])), isTrue);
    expect(environment.test(call('in_state', ['DEFAULT'])), isFalse);
  });

  test('testStateDepthAndContains', () {
    final environment = lexing(0, ['DEFAULT', 'A', 'B']);

    expect(environment.test(call('state_depth', ['3'])), isTrue);
    expect(environment.test(call('state_depth', ['2'])), isFalse);
    expect(environment.test(call('state_contains', ['A'])), isTrue);
    expect(environment.test(call('state_contains', ['C'])), isFalse);
  });

  test('testCharacterPosition', () {
    expect(lexing(0, ['DEFAULT']).test(call('at_char_start')), isTrue);
    expect(lexing(4, ['DEFAULT']).test(call('at_char_start')), isFalse);
    expect(
      lexing(4, ['DEFAULT']).test(call('at_char_position', ['4'])),
      isTrue,
    );
  });

  test('testLexicalIntegers', () {
    final environment = lexing(4, ['DEFAULT']);
    bool at(Value value) => environment.test(Call('at_char_position', [value]));

    expect(at(NumericConstant.integer(4)), isTrue);
    expect(at(NumericConstant.real(4.0)), isTrue);
    expect(at(const StringConstant(' 4 ')), isTrue);
    expect(at(NumericConstant.real(4.5)), isFalse);
    expect(at(const StringConstant('1.5')), isFalse);
    expect(at(NumericConstant.real(double.nan)), isFalse);
    expect(at(NumericConstant.real(double.infinity)), isFalse);
    expect(at(const StringConstant('99999999999999999999999')), isFalse);
    expect(at(const StringConstant('abc')), isFalse);
    expect(at(const Variable('x')), isFalse);
    expect(
      environment.test(
        const Call('state_depth', [StringConstant('99999999999999999999999')]),
      ),
      isFalse,
    );
  });

  test('testArityLookup', () {
    final entry = lexical.entry('at_char_position')!;

    expect(entry.minimum, 1);
    expect(entry.maximum, 1);
    expect(entry.phase, Phase.lexical);
    expect(entry.accepts(1), isTrue);
    expect(entry.accepts(2), isFalse);
    expect(lexical.entry('in_state')!.accepts(3), isTrue);
    expect(lexical.entry('missing'), isNull);
  });

  test('testRegistryImmutableAfterBuild', () {
    final builder = Predicates.builder();
    final built = builder.build();

    builder.add('later', 0, 0, Phase.syntactic, (environment, args) => true);

    expect(built.entry('later'), isNull);
    expect(builder.build().entry('later'), isNotNull);
  });

  test('testLaterRegistrationReplacesEarlier', () {
    final predicates = Predicates.builder()
        .add('p', 0, 0, Phase.syntactic, (environment, args) => false)
        .add('p', 0, 0, Phase.syntactic, (environment, args) => true)
        .build();

    expect(Environment.of(predicates).test(call('p')), isTrue);
  });

  test('testUnknownCallIsProgrammingError', () {
    expect(
      () => Environment.of(lexical).test(call('missing')),
      throwsStateError,
    );
  });

  test('testExceptionsFromChecksPropagate', () {
    // S-T1: a grammar's predicates are trusted and not isolated.
    final predicates = Predicates.builder()
        .add(
          'boom',
          0,
          0,
          Phase.syntactic,
          (environment, args) => throw const FormatException('boom'),
        )
        .build();

    expect(
      () => Environment.of(predicates).test(call('boom')),
      throwsFormatException,
    );
  });

  test('testCustomPredicateSeesResolvedBindings', () {
    final predicates = Predicates.builder()
        .add(
          'is_dog',
          1,
          1,
          Phase.syntactic,
          (environment, args) =>
              const StringConstant('dog') == environment.resolve(args.first),
        )
        .build();
    final environment = Environment.of(predicates)
        .plus('x', const StringConstant('dog'))
        .plus(
          'np',
          Binding.of(
            'the dog',
            Structure.of({'head': const StringConstant('dog')}),
          ),
        );

    expect(environment.test(const Call('is_dog', [Variable('x')])), isTrue);
    expect(
      environment.test(
        Call('is_dog', [
          FeaturePath(['np', 'head']),
        ]),
      ),
      isTrue,
    );
    expect(
      environment.test(const Call('is_dog', [StringConstant('cat')])),
      isFalse,
    );
  });

  test('testResolve', () {
    // S-C11: an unbound variable or a path that leads nowhere resolves to
    // nothing.
    final environment = Environment.of(lexical)
        .plus('w', Binding.of('dog', Structure.of({'f': const Variable('X')})))
        .plus(
          's',
          Structure.of({
            'a': Structure.of({'b': const StringConstant('c')}),
          }),
        );

    expect(environment.resolve(const Variable('missing')), isNull);
    expect(environment.resolve(FeaturePath(['w', 'missing'])), isNull);
    expect(environment.resolve(FeaturePath(['unknown', 'f'])), isNull);
    expect(environment.resolve(FeaturePath(['w', 'f'])), const Variable('X'));
    expect(
      environment.resolve(FeaturePath(['s', 'a', 'b'])),
      const StringConstant('c'),
    );
    expect(environment.resolve(FeaturePath(['s', 'a', 'b', 'c'])), isNull);
    expect(
      environment.resolve(const StringConstant('v')),
      const StringConstant('v'),
    );
  });

  test('testEnvironmentIsImmutable', () {
    final base = Environment.of(lexical);

    base.plus('x', const StringConstant('v'));
    base.merge({'y': const StringConstant('w')});

    expect(base.get('x'), isNull);
    expect(base.get('y'), isNull);
    expect(
      base.merge({'y': const StringConstant('w')}).get('y'),
      const StringConstant('w'),
    );
  });

  test('testInitialLexicalState', () {
    final environment = Environment.of(lexical);

    expect(environment.states, ['DEFAULT']);
    expect(environment.state, 'DEFAULT');
    expect(environment.position, 0);
    expect(() => environment.lexical(const [], 0), throwsArgumentError);
  });

  test('testEvaluatorWithEnvironment', () {
    final environment = lexing(0, ['DEFAULT']);
    final expression = Or([
      call('in_state', ['IN']),
      call('at_char_start'),
    ]);

    expect(Evaluator.truth(expression, environment.test), isTrue);
    expect(
      Evaluator.residual(
        expression,
        environment.test,
        lexical.names(Phase.lexical),
      ),
      Literal.trueValue,
    );
  });
}
