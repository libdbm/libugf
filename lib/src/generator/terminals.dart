/// Generators of terminal text.
library;

import 'dart:math';

import '../features/value.dart';
import '../patterns.dart';
import '../result.dart';
import 'vocabulary.dart';

/// Generates text for a terminal: a literal's text, or text a regex
/// matches. [generate] returns null when it cannot.
abstract base class TerminalGenerator {
  /// For subclasses.
  const TerminalGenerator.base();

  /// A generator applying [generate].
  factory TerminalGenerator(
    String? Function(String symbol, Structure features, String? context)
    generate,
  ) = _Function;

  /// Text for [symbol] (a literal's text or a regex pattern) satisfying
  /// [features]; [context] is the lexical symbol it is generated for, such
  /// as `noun` for `noun --> [a-z]+`.
  String? generate(String symbol, Structure features, [String? context]);
}

final class _Function extends TerminalGenerator {
  const _Function(this._generate) : super.base();

  final String? Function(String symbol, Structure features, String? context)
  _generate;

  @override
  String? generate(String symbol, Structure features, [String? context]) =>
      _generate(symbol, features, context);
}

/// Returns every symbol as it is.
final class LiteralTerminalGenerator extends TerminalGenerator {
  /// The generator returning every symbol as it is.
  const LiteralTerminalGenerator() : super.base();

  @override
  String generate(String symbol, Structure features, [String? context]) =>
      symbol;
}

/// Tries each of its generators in order until one produces text.
final class CompositeTerminalGenerator extends TerminalGenerator {
  /// A generator trying [generators] in order.
  CompositeTerminalGenerator(List<TerminalGenerator> generators)
    : _generators = List.unmodifiable(generators),
      super.base();

  final List<TerminalGenerator> _generators;

  @override
  String? generate(String symbol, Structure features, [String? context]) {
    for (final generator in _generators) {
      if (generator.generate(symbol, features, context) case final text?) {
        return text;
      }
    }
    return null;
  }
}

/// Generates text for regex patterns from functions registered by pattern.
final class RegexTerminalGenerator extends TerminalGenerator {
  RegexTerminalGenerator._(this._generators, this._fallback) : super.base();

  /// A builder for a regex generator.
  static RegexTerminalGeneratorBuilder builder() =>
      RegexTerminalGeneratorBuilder._();

  /// A generator for common numeric patterns.
  static RegexTerminalGenerator numbers(Random random) => builder()
      .register('[0-9]+', (features) => '${random.nextInt(100)}')
      .register('[0-9]', (features) => '${random.nextInt(10)}')
      .register('[1-9][0-9]*', (features) => '${1 + random.nextInt(99)}')
      .fallback(const LiteralTerminalGenerator())
      .build();

  final Map<String, String Function(Structure features)> _generators;
  final TerminalGenerator _fallback;

  /// The generator registered for exactly [symbol] if there is one;
  /// otherwise the first registered generator whose output [symbol] matches
  /// in full, so an equivalent pattern written differently still works
  /// (GEN-9); otherwise the fallback.
  @override
  String? generate(String symbol, Structure features, [String? context]) {
    if (_generators[symbol] case final generator?) {
      return generator(features);
    }
    final pattern = switch (Patterns.fragment(symbol)) {
      Success(value: final dart) => RegExp('(?:$dart)\$', unicode: true),
      Failure() => null,
    };
    if (pattern != null) {
      for (final generator in _generators.values) {
        final candidate = generator(features);
        if (pattern.matchAsPrefix(candidate)?.end == candidate.length) {
          return candidate;
        }
      }
    }
    return _fallback.generate(symbol, features, context);
  }
}

/// Builds a [RegexTerminalGenerator].
final class RegexTerminalGeneratorBuilder {
  RegexTerminalGeneratorBuilder._();

  final _generators = <String, String Function(Structure features)>{};
  TerminalGenerator _fallback = const LiteralTerminalGenerator();

  /// Registers [generator] for exactly [pattern].
  RegexTerminalGeneratorBuilder register(
    String pattern,
    String Function(Structure features) generator,
  ) {
    _generators[pattern] = generator;
    return this;
  }

  /// Sets the generator for patterns with no registered generator.
  RegexTerminalGeneratorBuilder fallback(TerminalGenerator fallback) {
    _fallback = fallback;
    return this;
  }

  /// Creates the generator.
  RegexTerminalGenerator build() =>
      RegexTerminalGenerator._(Map.of(_generators), _fallback);
}

/// Generates text for regex patterns from a [Vocabulary]: a random word the
/// pattern matches whose features unify with the requested ones. A literal
/// is returned as it is.
final class VocabularyGenerator extends TerminalGenerator {
  /// A generator over a vocabulary; with `fallback`, a regex with no
  /// matching word is returned as it is.
  VocabularyGenerator(this._vocabulary, this._random, {this._fallback = false})
    : super.base();

  final Vocabulary _vocabulary;
  final Random _random;
  final bool _fallback;

  static final _regex = RegExp(r'[\[\]+*?|(){}\\^$.]');

  @override
  String? generate(String symbol, Structure features, [String? context]) {
    if (!_regex.hasMatch(symbol)) {
      return symbol;
    }
    final matches = _vocabulary.byPattern(symbol, features);
    if (matches.isNotEmpty) {
      return matches[_random.nextInt(matches.length)];
    }
    return _fallback ? symbol : null;
  }
}

/// Generates text for a `{TOKEN}` element from its [label] and the
/// [bindings] so far. Java's interface, kept for callers; the generator
/// itself produces no caller tokens.
abstract interface class TokenMatchGenerator {
  /// Text for the `{TOKEN}` element labelled [label], given the [bindings]
  /// so far, or null.
  String? generate(String? label, Map<String, Value> bindings);
}
