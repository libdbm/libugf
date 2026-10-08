import 'dart:math';

import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

const agreement =
    'start S; S --> N{num: \$X} V{num: \$X};'
    " N{num: sg} --> 'dog'; N{num: pl} --> 'dogs'; V{num: sg} --> 'runs'; V{num: pl} --> 'run';";

GrammarGenerator generator(String source, int seed) =>
    GrammarGenerator.builder(GrammarLoader.unvalidated(source).orElseThrow())
        .random(Random(seed))
        .build()
        .orElseThrow();

/// The generation guarantees of Java `GrammarGeneratorTests` at unifica
/// 8d8c01a (S-N1, S-N2, GEN-8). The round trip over files is in
/// `round_trip_test.dart`.
void main() {
  test('testSiblingAgreement', () {
    final sentences = generator(
      agreement,
      1,
    ).generate('S', Structure.empty, 50).orElseThrow();

    expect(sentences, hasLength(50));
    expect(sentences.toSet(), {'dog runs', 'dogs run'});
  });

  test('testRequestedFeatures', () {
    const source =
        'start S; S{num: \$X} --> N{num: \$X} V{num: \$X};'
        " N{num: sg} --> 'dog'; N{num: pl} --> 'dogs'; V{num: sg} --> 'runs'; V{num: pl} --> 'run';";
    final plural = Structure.of({'num': const StringConstant('pl')});

    final sentences = generator(
      source,
      2,
    ).generate('S', plural, 20).orElseThrow();

    expect(sentences, isNotEmpty);
    expect(sentences, everyElement('dogs run'));
  });

  test('testConstraintOnLabels', () {
    final sentences = generator(
      "start S; S --> W:w where starts_with(w, 'a'); W --> 'apple'; W --> 'banana'; W --> 'avocado';",
      3,
    ).generate('S', Structure.empty, 30).orElseThrow();

    expect(sentences, isNotEmpty);
    expect(sentences.every((sentence) => sentence.startsWith('a')), isTrue);
  });

  test('testConstraintsCheckedDuringExpansion', () {
    // S-N2: a sentence that violates a required constraint is abandoned
    // while it is built, never generated and then rejected by the final
    // parse.
    final batch =
        GrammarGenerator.builder(
              GrammarLoader.unvalidated(
                "start S; S --> W:w where starts_with(w, 'a'); W --> 'apple'; W --> 'banana';",
              ).orElseThrow(),
            )
            .random(Random(3))
            .policy(Policy(attempts: 1))
            .build()
            .orElseThrow()
            .batch('S', Structure.empty, 40);

    expect(batch.sentences, everyElement('apple'));
    expect(batch.failures, isNotEmpty);
    expect(
      batch.failures.keys.where((reason) => reason.contains('does not parse')),
      isEmpty,
    );
  });

  test('testEachUseHasItsOwnVariables', () {
    // S-F5: the two uses of P bind their own $X, so their numbers differ.
    final sentences = generator(
      'start S; S --> P P; P{n: \$X} --> D{n: \$X} N{n: \$X};'
      " D{n: sg} --> 'a'; D{n: pl} --> 'some'; N{n: sg} --> 'dog'; N{n: pl} --> 'dogs';",
      6,
    ).generate('S', Structure.empty, 40).orElseThrow();

    expect(
      sentences.toSet(),
      containsAll(['a dog some dogs', 'some dogs a dog']),
    );
    expect(sentences.any((sentence) => sentence.contains('a dogs')), isFalse);
  });

  test('testFailureReported', () {
    const source =
        'start S; S{num: \$X} --> N{num: \$X} V{num: \$X};'
        " N{num: sg} --> 'dog'; N{num: pl} --> 'dogs'; V{num: sg} --> 'runs'; V{num: pl} --> 'run';";

    final result = generator(
      source,
      4,
    ).generateOne('S', Structure.of({'num': const StringConstant('dual')}));

    final error = (result as Failure<String, ErrorDetails>).error;
    expect(error.code, GrammarGenerator.failed);
    expect(error.message, isNotEmpty);
  });

  test('testSeedOrderIndependent', () {
    final grammar = GrammarLoader.unvalidated(
      'start S; S --> W W W; W --> [a-z]+;',
    ).orElseThrow();
    final vocabulary = Vocabulary.builder()
        .add('alpha', Structure.empty)
        .add('beta', Structure.empty)
        .add('gamma', Structure.empty)
        .add('delta', Structure.empty)
        .build();

    final first = GrammarGenerator.builder(grammar)
        .vocabulary(vocabulary)
        .random(Random(7))
        .build()
        .orElseThrow();
    final second = GrammarGenerator.builder(grammar)
        .random(Random(7))
        .vocabulary(vocabulary)
        .build()
        .orElseThrow();

    expect(
      first.generate('S', Structure.empty, 10).orElseThrow(),
      second.generate('S', Structure.empty, 10).orElseThrow(),
    );
  });

  test('testPolicyDepthAndJoiner', () {
    final sentences =
        GrammarGenerator.builder(
              GrammarLoader.unvalidated("start S; S --> 'a' S | 'b';")
                  .orElseThrow(),
            )
            .random(Random(5))
            .policy(Policy.defaults.copy(depth: 3, joiner: Joiner.space))
            .build()
            .orElseThrow()
            .generate('S', Structure.empty, 20)
            .orElseThrow();

    expect(
      sentences.every((sentence) => sentence.split(' ').length <= 3),
      isTrue,
    );
  });
}
