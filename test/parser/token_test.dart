import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Structure features(Map<String, String> values) => Structure.of({
  for (final MapEntry(:key, :value) in values.entries)
    key: StringConstant(value),
});

/// Ported from Java `TokenTests` at unifica 8d8c01a.
void main() {
  test('testFactories', () {
    final plain = Token.simple('hello', 0, 5);
    expect((plain.text, plain.start, plain.end), ('hello', 0, 5));
    expect(plain.string('cat'), isNull);
    expect(plain.features, Structure.empty);
    expect(plain.category, isNull);

    final tagged = Token('dog', features({'pos': 'noun'}), 0, 3);
    expect(tagged.features, features({'pos': 'noun'}));
    expect(tagged.category, isNull);
  });

  test('testCategoryIsExplicit', () {
    expect(Token('x', Structure.empty, 0, 1, 'NN').category, 'NN');
    expect(Token('x', features({'cat': 'NN'}), 0, 1).category, isNull);
    expect(
      Token('x', Structure.empty, 0, 1, 'NN'),
      isNot(Token('x', Structure.empty, 0, 1, 'VB')),
    );
  });

  test('testBuilder', () {
    final token = TokenBuilder('word', 0, 4)
        .feature('cat', const StringConstant('NN'))
        .feature('num', const StringConstant('sing'))
        .build();
    expect(token.string('cat'), 'NN');
    expect(token.string('num'), 'sing');

    final replaced = TokenBuilder(
      'he',
      0,
      2,
    ).features(features({'cat': 'PRP', 'case': 'nom'})).build();
    expect(replaced.string('case'), 'nom');
  });

  test('testFeatureAccess', () {
    final token = Token('running', features({'lemma': 'run'}), 0, 7);

    expect(token.feature('lemma'), isA<StringConstant>());
    expect(token.string('lemma'), 'run');
    expect(token.string('missing'), isNull);
    expect(token.hasFeatures, isTrue);
    expect(Token.simple('word', 0, 4).hasFeatures, isFalse);
  });

  test('testToString', () {
    expect(Token.simple('hello', 0, 5).toString(), contains('[0,5]'));
    final tagged = Token('dog', features({'cat': 'NN', 'num': 'sing'}), 0, 3);
    expect(tagged.toString(), contains('cat=NN'));
    expect(tagged.toString(), contains('num=sing'));
  });
}
