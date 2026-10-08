import 'dart:math';

import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Grammar grammar(String source) => GrammarLoader.parse(source).orElseThrow();

GrammarGenerator generator(String source, Policy policy, int seed) =>
    GrammarGenerator.builder(grammar(source))
        .random(Random(seed))
        .policy(policy)
        .build()
        .orElseThrow();

ErrorDetails failure<T>(Result<T, ErrorDetails> result) =>
    (result as Failure<T, ErrorDetails>).error;

/// Ported from Java `GrammarGeneratorTests` at unifica 8d8c01a: the
/// builder, policy and limit cases. The guarantees (agreement, requested
/// features, constraints, round trip) are Task 33's.
void main() {
  group('policy', () {
    test('testPolicyDefaults', () {
      final policy = Policy.defaults;

      expect(
        (
          policy.depth,
          policy.attempts,
          policy.repetitions,
          policy.length,
          policy.steps,
        ),
        (20, 10, 3, 10000, 100000),
      );
      expect(policy.joiner, same(Joiner.spaced));
      expect(Policy.defaults.copy(depth: 3).depth, 3);
      expect(() => Policy(depth: 0), throwsArgumentError);
      expect(() => Policy(repetitions: -1), throwsArgumentError);
    });

    test('testJoiners', () {
      expect(Joiner.space.join(['a', '', 'b', 'c']), 'a b c');
      expect(
        Joiner.spaced.join(['<', 'div', '>', 'hi', '</', 'div', '>']),
        '<div>hi</div>',
      );
      expect(Joiner.spaced.join(['f', '(', 'x', ',', 'y', ')']), 'f(x , y)');
      expect(Joiner.spaced.join(['<', 'br', '/>']), '<br/>');
      expect(Joiner.spaced.join(['a', '=', 'b']), 'a=b');
      expect(Joiner.spaced.join(['the', 'dogs', 'bark']), 'the dogs bark');
    });
  });

  group('builder', () {
    test('testBuildFailsForAnInvalidGrammar', () {
      final invalid = GrammarLoader.unvalidated('start S; S --> T;')
          .orElseThrow();

      expect(
        failure(GrammarGenerator.builder(invalid).build()).code,
        Compiler.invalid,
      );
    });

    test('testBuildsWithVocabulary', () {
      final vocabulary = Vocabulary.builder()
          .add(
            'hello',
            Structure.of({'type': const StringConstant('greeting')}),
          )
          .add('world', Structure.of({'type': const StringConstant('noun')}))
          .build();

      final sentence =
          GrammarGenerator.builder(
                grammar('start sentence; sentence --> [a-z]+;'),
              )
              .vocabulary(vocabulary)
              .random(Random(42))
              .build()
              .orElseThrow()
              .generateOne('sentence', Structure.empty)
              .orElseThrow();

      expect(['hello', 'world'], contains(sentence));
    });

    test('testVocabularyMatchesByPattern', () {
      final vocabulary = Vocabulary.builder()
          .add('dog', Structure.empty)
          .add('cat', Structure.empty)
          .add('elephant', Structure.empty)
          .build();
      final generated = GrammarGenerator.builder(
        grammar('start word; word --> [a-z]{3};'),
      ).vocabulary(vocabulary).random(Random(42)).build().orElseThrow();

      final words = {
        for (var index = 0; index < 100; index++)
          if (generated.generateOne('word', Structure.empty) case Success(
            :final value,
          ))
            value,
      };

      expect(words.intersection({'dog', 'cat'}), isNotEmpty);
      expect(words, isNot(contains('elephant')));
    });

    test('testFallsBackToLiteral', () {
      final generated =
          GrammarGenerator.builder(grammar("start punct; punct --> '.';"))
              .vocabulary(
                Vocabulary.builder().add('word', Structure.empty).build(),
              )
              .build()
              .orElseThrow();

      expect(
        generated.generateOne('punct', Structure.empty).orElseThrow(),
        '.',
      );
    });

    test('testBuildsWithMultipleVocabularies', () {
      final generated =
          GrammarGenerator.builder(grammar('start word; word --> [a-z]+;'))
              .vocabulary(
                Vocabulary.builder().add('dog', Structure.empty).build(),
              )
              .vocabulary(
                Vocabulary.builder().add('run', Structure.empty).build(),
              )
              .random(Random(42))
              .build()
              .orElseThrow();

      final words = {
        for (var index = 0; index < 20; index++)
          generated.generateOne('word', Structure.empty).orElseThrow(),
      };

      expect(words, isNotEmpty);
      expect(words.difference({'dog', 'run'}), isEmpty);
    });

    test('testRespectsDepth', () {
      final generated =
          GrammarGenerator.builder(
                grammar("start expr; expr --> expr '+' expr; expr --> '1';"),
              )
              .policy(Policy.defaults.copy(depth: 3))
              .random(Random(42))
              .build()
              .orElseThrow();

      expect(
        generated.generate('expr', Structure.empty, 5).orElseThrow(),
        hasLength(5),
      );
    });

    test('testGeneratesMultiple', () {
      final generated = GrammarGenerator.builder(
        grammar("start word; word --> 'hello';"),
      ).terminal(const LiteralTerminalGenerator()).build().orElseThrow();

      expect(
        generated.generate('word', Structure.empty, 5).orElseThrow(),
        List.filled(5, 'hello'),
      );
    });

    test('testDeterministicForASeed', () {
      List<String> sentences(int seed) => generator(
        "start S; S --> W W W; W --> 'a' | 'b' | 'c' | X; X --> [0-9]{2};",
        Policy.defaults,
        seed,
      ).generate('S', Structure.empty, 10).orElseThrow();

      expect(sentences(7), sentences(7));
      expect(sentences(7), isNot(sentences(8)));
    });
  });

  group('limits', () {
    test('testBatchReportsCounts', () {
      final batch = generator(
        "start S; S --> A | B; A --> 'a'; B --> C; C --> D; D --> 'd';",
        Policy(depth: 20, attempts: 1, repetitions: 3, length: 100, steps: 3),
        7,
      ).batch('S', Structure.empty, 20);

      expect(batch.requested, 20);
      expect(batch.sentences, isNotEmpty);
      expect(batch.failures, isNotEmpty);
      expect(
        batch.sentences.length + batch.failures.values.fold(0, (a, b) => a + b),
        20,
      );
    });

    test('testValidationLimitReported', () {
      final result =
          GrammarGenerator.builder(grammar("start S; S --> 'a' 'b' 'c';"))
              .limits(Limits.none.copy(states: 1))
              .build()
              .orElseThrow()
              .generateOne('S', Structure.empty);

      expect(failure(result).code, GrammarGenerator.failed);
      expect(failure(result).message, contains('states'));
    });

    test('testLengthCheckedWhileBuilding', () {
      final generated = generator(
        "start S; S --> 'x' S | 'x';",
        Policy(depth: 10000, attempts: 1, length: 10, steps: 1000000),
        3,
      );

      for (var index = 0; index < 20; index++) {
        if (generated.generateOne('S', Structure.empty) case Success(
          :final value,
        )) {
          expect(value.length, lessThanOrEqualTo(10));
        }
      }
    });

    test('testLengthFailureReported', () {
      final result = generator(
        "start S; S --> 'x' 'x' 'x';",
        Policy(depth: 10, attempts: 1, length: 2, steps: 1000),
        1,
      ).generateOne('S', Structure.empty);

      expect(failure(result).message, contains('exceed'));
    });
  });
}
