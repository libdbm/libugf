import 'dart:math';

import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Structure features(Map<String, String> values) => Structure.of({
  for (final MapEntry(:key, :value) in values.entries)
    key: StringConstant(value),
});

/// Ported from Java `VocabularyTests` at unifica 8d8c01a.
/// `testByPatternIsThreadSafe` does not apply: Dart isolates share no
/// memory, so a vocabulary is never used by two threads at once.
void main() {
  late Vocabulary vocabulary;

  setUp(() {
    vocabulary = Vocabulary.builder()
        .add('cat', features({'type': 'noun', 'num': 'sing'}))
        .add('cats', features({'type': 'noun', 'num': 'plur'}))
        .add('dog', features({'type': 'noun', 'num': 'sing'}))
        .add('dogs', features({'type': 'noun', 'num': 'plur'}))
        .add('run', features({'type': 'verb', 'num': 'plur', 'tense': 'pres'}))
        .add('runs', features({'type': 'verb', 'num': 'sing', 'tense': 'pres'}))
        .add('ran', features({'type': 'verb', 'tense': 'past'}))
        .add('the', features({'type': 'det'}))
        .add('a', features({'type': 'det'}))
        .build();
  });

  test('testEmptyVocabulary', () {
    final empty = Vocabulary.empty();

    expect(empty.all, isEmpty);
    expect(empty.byFeatures(features({'type': 'noun'})), isEmpty);
    expect(empty.byPattern('[a-z]+', Structure.empty), isEmpty);
  });

  test('testBuilding', () {
    final single = Vocabulary.builder()
        .add('word', features({'type': 'name'}))
        .build();
    expect(single.all.single.text, 'word');
    expect(
      single.all.single.features.get('type'),
      const StringConstant('name'),
    );

    final merged = Vocabulary.builder()
        .merge(
          Vocabulary.builder().add('one', features({'type': 'cat1'})).build(),
        )
        .merge(
          Vocabulary.builder().add('two', features({'type': 'cat2'})).build(),
        )
        .build();
    expect(merged.all, hasLength(2));
    expect(merged.byFeatures(features({'type': 'cat1'})), ['one']);
    expect(merged.byFeatures(features({'type': 'cat2'})), ['two']);
  });

  test('testWord', () {
    final word = Word('text', features({'k': 'v', 'type': 'noun'}));

    expect(word.text, 'text');
    expect(word.features.get('k'), const StringConstant('v'));
    expect(Word('text', features({'k': 'v'})).features.get('type'), isNull);
  });

  test('testFeatureLookup', () {
    expect(vocabulary.byFeatures(features({'type': 'noun'})), [
      'cat',
      'cats',
      'dog',
      'dogs',
    ]);
    expect(vocabulary.byFeatures(features({'type': 'noun', 'num': 'sing'})), [
      'cat',
      'dog',
    ]);
    expect(vocabulary.byFeatures(features({'type': 'unknown'})), isEmpty);
    expect(
      vocabulary.byFeatures(features({'type': 'noun', 'num': 'dual'})),
      isEmpty,
    );
    expect(vocabulary.byFeatures(Structure.empty), hasLength(9));
    expect(
      vocabulary.byFeatures(
        features({'type': 'verb', 'num': 'sing', 'tense': 'pres'}),
      ),
      ['runs'],
    );
  });

  test('testPatternLookup', () {
    expect(vocabulary.byPattern('c.*', Structure.empty), ['cat', 'cats']);
    expect(vocabulary.byPattern('.*s', features({'num': 'plur'})), [
      'cats',
      'dogs',
    ]);
    expect(vocabulary.byPattern('cat', Structure.empty), ['cat']);
    expect(
      vocabulary.byPattern('[a-z]+', Structure.empty),
      vocabulary.byPattern('[a-z]+', Structure.empty),
    );
    // A pattern outside the portable subset matches nothing.
    expect(vocabulary.byPattern('[a-z]++', Structure.empty), isEmpty);
  });

  test('testAllIsUnmodifiable', () {
    expect(vocabulary.all, hasLength(9));
    expect(() => vocabulary.all.clear(), throwsUnsupportedError);
  });

  test('testPatternCacheBounded', () {
    final small = Vocabulary.builder().add('dog', Structure.empty).build();
    for (var index = 0; index < Vocabulary.patterns + 50; index++) {
      small.byPattern('d[o]g|x$index', Structure.empty);
    }

    expect(small.cached, lessThanOrEqualTo(Vocabulary.patterns));
    expect(small.byPattern('d[o]g|x1', Structure.empty), ['dog']);
  });

  test('testRegexGeneratorMatchesEquivalentPattern', () {
    final generator = RegexTerminalGenerator.numbers(Random(1));

    final token = generator.generate('[0-9][0-9]*', Structure.empty)!;

    expect(RegExp(r'^[0-9]+$').hasMatch(token), isTrue);
    expect(generator.generate('[a-z]+', Structure.empty), '[a-z]+');
  });

  test('testTerminalGenerators', () {
    expect(
      const LiteralTerminalGenerator().generate('if', Structure.empty),
      'if',
    );
    final composite = CompositeTerminalGenerator([
      TerminalGenerator((symbol, features, context) => null),
      TerminalGenerator((symbol, features, context) => '$symbol in $context'),
    ]);
    expect(composite.generate('x', Structure.empty, 'noun'), 'x in noun');
    final words = VocabularyGenerator(vocabulary, Random(1));
    // Text without a regex metacharacter is a literal; as in Java, '.' is
    // treated as a pattern (it matches the one-letter word 'a').
    expect(words.generate(',', Structure.empty), ',');
    expect(words.generate('.', Structure.empty), 'a');
    expect([
      'cat',
      'dog',
    ], contains(words.generate('[a-z]{3}', features({'type': 'noun'}))));
    expect(words.generate('[0-9]+', Structure.empty), isNull);
    expect(
      VocabularyGenerator(
        vocabulary,
        Random(1),
        fallback: true,
      ).generate('[0-9]+', Structure.empty),
      '[0-9]+',
    );
  });
}
