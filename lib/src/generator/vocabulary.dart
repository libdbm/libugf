/// Words with features, for generation.
library;

import '../features/unifier.dart';
import '../features/value.dart';
import '../patterns.dart';
import '../result.dart';

/// A word and its features (Java `Vocabulary.Entry`).
final class Word {
  /// A word [text] with [features].
  const Word(this.text, this.features);

  /// The word.
  final String text;

  /// The word's features.
  final Structure features;
}

/// Words with features, looked up by features (words whose features unify
/// with the given ones) or by pattern (words whose text the pattern matches
/// in full, and whose features unify).
final class Vocabulary {
  Vocabulary._(List<Word> entries) : all = List.unmodifiable(entries);

  /// An empty vocabulary.
  factory Vocabulary.empty() => Vocabulary._(const []);

  /// A builder for a vocabulary.
  static VocabularyBuilder builder() => VocabularyBuilder._();

  /// The most patterns whose matching entries are cached; the least
  /// recently used are dropped.
  static const patterns = 256;

  /// Every entry, in the order added.
  final List<Word> all;

  final _cache = <String, List<Word>>{};

  /// The number of cached patterns, at most [patterns].
  int get cached => _cache.length;

  /// The words whose features unify with [target].
  List<String> byFeatures(Structure target) => _filter(all, target);

  /// The words whose text [pattern] matches in full, as a grammar regex
  /// (S-L7), and whose features unify with [target]. A pattern outside the
  /// subset matches nothing.
  List<String> byPattern(String pattern, Structure target) {
    var candidates = _cache.remove(pattern);
    if (candidates == null) {
      final compiled = _compile(pattern);
      candidates = compiled == null
          ? const <Word>[]
          : [
              for (final word in all)
                if (compiled.matchAsPrefix(word.text)?.end == word.text.length)
                  word,
            ];
      if (_cache.length >= patterns) {
        _cache.remove(_cache.keys.first);
      }
    }
    _cache[pattern] = candidates;
    return _filter(candidates, target);
  }

  static RegExp? _compile(String pattern) =>
      switch (Patterns.fragment(pattern)) {
        Success(value: final dart) => () {
          try {
            return RegExp('(?:$dart)\$', unicode: true);
          } on FormatException {
            return null;
          }
        }(),
        Failure() => null,
      };

  static List<String> _filter(List<Word> candidates, Structure target) => [
    for (final word in candidates)
      if (target.isEmpty ||
          Unifier.structures(word.features, target) is Success)
        word.text,
  ];
}

/// Builds a [Vocabulary].
final class VocabularyBuilder {
  VocabularyBuilder._();

  final _entries = <Word>[];

  /// Adds the word [text] with [features].
  VocabularyBuilder add(String text, Structure features) {
    _entries.add(Word(text, features));
    return this;
  }

  /// Adds every entry of [other].
  VocabularyBuilder merge(Vocabulary other) {
    _entries.addAll(other.all);
    return this;
  }

  /// Creates the vocabulary.
  Vocabulary build() => Vocabulary._(_entries);
}
