/// Token with features and position information.
library;

import '../features/value.dart';

/// A token produced during lexical analysis.
///
/// Contains the matched text, feature structure, and position information.
/// Language-specific attributes (e.g., POS tag, lemma) are stored as features.
final class Token {
  /// The matched text.
  final String text;

  /// The token's features.
  final Structure features;

  /// The offset of the first character.
  final int start;

  /// The offset just past the last character.
  final int end;

  /// The token's category, which a named symbol or anonymous terminal can
  /// match, or null: a token with no category matches only `{TOKEN}`
  /// (S-L6).
  final String? category;

  /// A token of [text] from [start] to [end].
  const Token(this.text, this.features, this.start, this.end, [this.category]);

  /// Creates a token with just text (no features).
  factory Token.simple(String text, int start, int end) {
    return Token(text, Structure.empty, start, end);
  }

  /// Returns true if this token has features.
  bool get hasFeatures => features.isNotEmpty;

  /// Gets a feature value by key.
  Value? feature(String key) => features[key];

  /// Gets a string feature value by key.
  String? string(String key, [String? defaultValue]) {
    final value = features[key];
    return value is StringConstant ? value.value : defaultValue;
  }

  /// Gets a boolean feature value by key.
  bool boolean(String key, [bool defaultValue = false]) {
    final value = features[key];
    return value is BooleanConstant ? value.value : defaultValue;
  }

  /// Gets an integer feature value by key.
  int integer(String key, [int defaultValue = 0]) {
    final value = features[key];
    return value is NumericConstant ? value.value.toInt() : defaultValue;
  }

  /// Gets a double feature value by key.
  double floating(String key, [double defaultValue = 0.0]) {
    final value = features[key];
    return value is NumericConstant ? value.value.toDouble() : defaultValue;
  }

  @override
  String toString() {
    final buffer = StringBuffer(text);

    if (hasFeatures) {
      buffer.write('{');
      var first = true;
      for (final key in features.keys) {
        if (!first) buffer.write(', ');
        final value = features[key];
        buffer.write('$key=');
        if (value is StringConstant) {
          buffer.write(value.value);
        } else {
          buffer.write('...');
        }
        first = false;
      }
      buffer.write('}');
    }

    buffer.write('[$start,$end]');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Token &&
          text == other.text &&
          start == other.start &&
          end == other.end &&
          features == other.features &&
          category == other.category;

  @override
  int get hashCode => Object.hash(text, start, end, features, category);
}

/// Builder for Token construction.
final class TokenBuilder {
  /// The matched text.
  final String text;

  /// The offset of the first character.
  final int start;

  /// The offset just past the last character.
  final int end;
  Structure _features = Structure.empty;

  /// A builder for a token of [text] from [start] to [end].
  TokenBuilder(this.text, this.start, this.end);

  /// Sets the feature structure.
  TokenBuilder features(Structure features) {
    _features = features;
    return this;
  }

  /// Sets a single feature.
  TokenBuilder feature(String key, Value value) {
    _features = _features.plus(key, value);
    return this;
  }

  /// Builds the token.
  Token build() => Token(text, _features, start, end);
}
