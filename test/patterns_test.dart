import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

RegExp compile(String source) => Patterns.compile(source).orElseThrow();

/// Whether [source], compiled, matches all of [input].
bool full(String source, String input) {
  final match = compile(source).matchAsPrefix(input);
  return match != null && match.end == input.length;
}

String failure(Result<Object, ErrorDetails> result) =>
    (result as Failure<Object, ErrorDetails>).error.code;

/// Ported from Java `PatternsTests` at unifica 8d8c01a, then the Dart
/// translation of SPEC R-COMP-8.
void main() {
  group('subset', () {
    test('testSubsetAccepted', () {
      for (final source in [
        'abc',
        r'a\.b\*\[\]\{\}\(\)\|\?\+\^\$\/\-\\',
        r'\n\r\t\f\x41é',
        r'\d\D\w\W\s\S\bx\B',
        r'\p{L}\p{Lu}\P{Nd}[\p{M}\p{N}\p{Pc}]',
        r'[a-z][^\]\[\-][-a]',
        '[a-]',
        '[^-a]',
        '[a-z0-9_-]',
        r'[\--\/]',
        r'[\x41-\x5Aà-ÿ]',
        r'[a\-\w]',
        r'[\w-]',
        '.',
        '(a)(?:b)(?=c)(?!d)(?<=e)(?<!f)',
        'a|b',
        'a*b+c?d{2}e{2,}f{2,3}',
        'a*?b+?c??d{2}?e{2,}?f{2,3}?',
        '(?s).',
        r'^a$',
        r'[\u0080-￿]',
      ]) {
        expect(
          Patterns.compile(source),
          isA<Success<RegExp, ErrorDetails>>(),
          reason: source,
        );
      }
    });

    test('testOutsideSubsetRejected', () {
      for (final source in [
        r'(a)\1',
        '(?<name>a)',
        'a*+',
        'a++',
        'a?+',
        'a{2}+',
        '(?>a)',
        '[a[b]]',
        '[a&&b]',
        '[]a]',
        r'[\w-a]',
        r'[a-\w]',
        r'[\p{L}-z]',
        r'[a-\p{L}]',
        '[a-b-c]',
        r'\Qa\E',
        r'\A',
        r'\z',
        r'\Z',
        r'\G',
        r'\R',
        r'\h',
        r'\v',
        r'\e',
        r'\cA',
        r'\0',
        r'\x{41}',
        r'\pL',
        r'\p{Alpha}',
        r'\p{IsLatin}',
        r'\p{javaLowerCase}',
        '(?i)abc',
        '(?is).',
        '(?si).',
        'a(?s)b',
        '(?i:a)',
        '(?m)a',
        '(?x)a',
        '(?u)a',
        'a{',
        'a}',
        'a]',
        r'[\b]',
        r'\',
      ]) {
        expect(
          failure(Patterns.compile(source)),
          Patterns.subset,
          reason: source,
        );
      }
    });

    test('testDollarIsEndOfInput', () {
      expect(compile(r'a$').hasMatch('a'), isTrue);
      expect(compile(r'a$').hasMatch('a\n'), isFalse);
      expect(full(r'[$]', r'$'), isTrue);
      expect(full(r'\$', r'$'), isTrue);
    });

    test('testFragmentsTakeNoFlags', () {
      expect(Patterns.fragment(r'a$').orElseThrow(), r'a$');
      expect(failure(Patterns.fragment('(?s).')), Patterns.subset);
    });

    test('testSyntaxErrorsAreReported', () {
      expect(failure(Patterns.compile('(a')), Patterns.subset);
    });

    test('testMessagesNameTheOffsetAndRule', () {
      final error =
          (Patterns.compile('ab++') as Failure<RegExp, ErrorDetails>).error;
      expect(
        error.message,
        'possessive quantifiers are not portable at offset 3 (S-L7)',
      );
    });
  });

  group('translation', () {
    test('testDotExcludesJavaLineTerminators', () {
      for (final terminator in ['\n', '\r', '\u0085', ' ', ' ']) {
        expect(full('.', terminator), isFalse, reason: terminator);
      }
      expect(full('.', 'x'), isTrue);
      expect(full('.', '\u{1F600}'), isTrue);
      expect(full('[.]', '.'), isTrue);
      expect(full('[.]', 'x'), isFalse);
    });

    test('testLeadingDotAllMatchesEveryCodePoint', () {
      for (final terminator in ['\n', '\r', '\u0085', ' ', ' ']) {
        expect(full('(?s).', terminator), isTrue, reason: terminator);
      }
    });

    test('testWhitespaceIsAscii', () {
      for (final space in [' ', '\t', '\n', '\x0B', '\f', '\r']) {
        expect(full(r'\s', space), isTrue);
        expect(full(r'\S', space), isFalse);
      }
      for (final other in [' ', ' ', '\u0085', 'a']) {
        expect(full(r'\s', other), isFalse);
        expect(full(r'\S', other), isTrue);
      }
    });

    test('testWhitespaceInClasses', () {
      expect(full(r'[a\s]', 'a'), isTrue);
      expect(full(r'[a\s]', '\t'), isTrue);
      expect(full(r'[a\s]', ' '), isFalse);
      expect(full(r'[^a\s]', 'b'), isTrue);
      expect(full(r'[^a\s]', ' '), isFalse);
      expect(full(r'[^a\s]', ' '), isTrue);
      expect(full(r'[\s-]', '-'), isTrue);
    });

    test('testComplementWhitespaceInClasses', () {
      expect(full(r'[a\S]', 'a'), isTrue);
      expect(full(r'[a\S]', 'b'), isTrue);
      expect(full(r'[a\S]', ' '), isFalse);
      expect(full(r'[^a\S]', ' '), isTrue);
      expect(full(r'[^a\S]', 'a'), isFalse);
      expect(full(r'[^a\S]', 'b'), isFalse);
      expect(full(r'[\S]', 'b'), isTrue);
      expect(full(r'[\S]', ' '), isFalse);
      expect(full(r'[^\S]', ' '), isTrue);
      expect(full(r'[^\S]', 'b'), isFalse);
      expect(full(r'[a\S]+', 'ab'), isTrue);
    });

    test('testEscapedPunctuationMatchesItself', () {
      const punctuation =
          r'\^$.|?*+()[]{}/-!"#%&'
          "'"
          r',:;<=>@_`~';
      for (final character in punctuation.split('')) {
        expect(full('\\$character', character), isTrue, reason: character);
        expect(full('[\\$character]', character), isTrue, reason: character);
      }
    });

    test('testDashesInClasses', () {
      expect(full(r'[\w-]', '-'), isTrue);
      expect(full(r'[\w-]', 'a'), isTrue);
      expect(full('[a-]', '-'), isTrue);
      expect(full('[^-a]', 'b'), isTrue);
      expect(full(r'[\--\/]', '.'), isTrue);
    });

    test('testUnchangedConstructs', () {
      expect(full(r'\p{L}+', 'éß'), isTrue);
      expect(full(r'\p{Lu}', 'é'), isFalse);
      expect(full(r'\w+', 'a_1'), isTrue);
      expect(full(r'\w', 'é'), isFalse);
      expect(full(r'\d', '٣'), isFalse);
      expect(compile(r'\bab\b').hasMatch('x ab y'), isTrue);
      expect(full(r'\x41é', 'Aé'), isTrue);
      expect(compile('(?<=a)b').hasMatch('ab'), isTrue);
      expect(full('a{2,3}?', 'aa'), isTrue);
    });

    test('testDefaultWhitespace', () {
      expect(Patterns.whitespace, r'[ \t\n\x0B\f\r]+');
      expect(full(Patterns.whitespace, ' \t\n'), isTrue);
      expect(RegExp(Patterns.whitespace, unicode: true).hasMatch(' '), isFalse);
    });

    test('testPortableReturnsTheDartForm', () {
      expect(Patterns.portable('a.b').orElseThrow(), r'a[^\n\r\u0085  ]b');
      expect(Patterns.portable(r'\!').orElseThrow(), '!');
      expect(Patterns.portable(r'\.').orElseThrow(), r'\.');
    });
  });
}
