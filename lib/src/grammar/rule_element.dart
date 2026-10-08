/// Rule elements for grammar right-hand sides.
library;

import '../features/value.dart';

/// Quantifier for repetition elements.
enum Quantifier {
  /// Zero or more (*).
  star,

  /// One or more (+).
  plus,

  /// Optional (?).
  optional,
}

/// Element on the right-hand side of a grammar rule.
///
/// Can be: nonterminal, terminal, regex, repetition, alternation,
/// state annotation, or token match.
sealed class RuleElement {
  const RuleElement();
}

/// Non-terminal reference (e.g., "np", "clause").
final class Nonterminal extends RuleElement {
  /// The referenced symbol.
  final String name;

  /// The label binding the constituent in constraints, or null.
  final String? label;

  /// The features the constituent must unify with.
  final Structure features;

  /// A reference to [name], with an optional [label] and [features] (empty
  /// when null).
  Nonterminal(this.name, [this.label, Structure? features])
    : features = features ?? Structure.empty;

  /// A reference to [name] with [features] and an optional [label].
  Nonterminal.withFeatures(this.name, this.features, [this.label]);

  /// Creates a copy with the given label.
  Nonterminal withLabel(String label) =>
      Nonterminal.withFeatures(name, features, label);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Nonterminal &&
          name == other.name &&
          label == other.label &&
          features == other.features;

  @override
  int get hashCode => Object.hash(name, label, features);

  @override
  String toString() {
    final buffer = StringBuffer(name);
    if (features.isNotEmpty) {
      buffer.write(features.display());
    }
    if (label != null) {
      buffer.write(':$label');
    }
    return buffer.toString();
  }
}

/// Terminal string literal (e.g., 'is', 'the').
final class Terminal extends RuleElement {
  /// The literal text.
  final String text;

  /// The label binding the token in constraints, or null.
  final String? label;

  /// A literal [text] with an optional [label].
  const Terminal(this.text, [this.label]);

  /// Creates a copy with the given label.
  Terminal withLabel(String label) => Terminal(text, label);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Terminal && text == other.text && label == other.label;

  @override
  int get hashCode => Object.hash(text, label);

  @override
  String toString() => label == null ? "'$text'" : "'$text':$label";
}

/// Regular expression pattern (e.g., `[A-Z][a-z]*`), written in the portable
/// subset (S-L7). The compiler checks and compiles it.
final class Regex extends RuleElement {
  /// The pattern, in the portable subset.
  final String pattern;

  /// The label binding the token in constraints, or null.
  final String? label;

  /// A [pattern] with an optional [label].
  const Regex(this.pattern, [this.label]);

  /// Creates a copy with the given label.
  Regex withLabel(String label) => Regex(pattern, label);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Regex && pattern == other.pattern && label == other.label;

  @override
  int get hashCode => Object.hash(pattern, label);

  @override
  String toString() => label == null ? pattern : '$pattern:$label';
}

/// Repetition operator (*, +, ?).
final class Repetition extends RuleElement {
  /// The repeated element.
  final RuleElement element;

  /// How often [element] may occur.
  final Quantifier quantifier;

  /// [element] repeated as [quantifier] allows.
  const Repetition(this.element, this.quantifier);

  /// Creates a zero-or-more (*) repetition.
  const Repetition.star(this.element) : quantifier = Quantifier.star;

  /// Creates a one-or-more (+) repetition.
  const Repetition.plus(this.element) : quantifier = Quantifier.plus;

  /// Creates an optional (?) repetition.
  const Repetition.optional(this.element) : quantifier = Quantifier.optional;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Repetition &&
          element == other.element &&
          quantifier == other.quantifier;

  @override
  int get hashCode => Object.hash(element, quantifier);

  @override
  String toString() {
    final suffix = switch (quantifier) {
      Quantifier.star => '*',
      Quantifier.plus => '+',
      Quantifier.optional => '?',
    };
    return '($element)$suffix';
  }
}

/// A parenthesised sequence of elements, as a group or an alternation
/// option (S-G4).
final class Sequence extends RuleElement {
  /// The elements, in order.
  final List<RuleElement> elements;

  /// A sequence of [elements].
  Sequence(List<RuleElement> elements) : elements = List.unmodifiable(elements);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Sequence && _listEquals(elements, other.elements);

  @override
  int get hashCode => Object.hash(Sequence, Object.hashAll(elements));

  @override
  String toString() => '(${elements.join(' ')})';
}

/// Alternation (choice between options).
final class Alternation extends RuleElement {
  /// The options, in declaration order.
  final List<RuleElement> options;

  /// A choice between [options].
  Alternation(List<RuleElement> options) : options = List.unmodifiable(options);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Alternation && _listEquals(options, other.options);

  @override
  int get hashCode => Object.hash(Alternation, Object.hashAll(options));

  @override
  String toString() => '(${options.join(' | ')})';
}

/// State annotation for lexer state transitions (e.g., {CONTENT}).
final class StateAnnotation extends RuleElement {
  /// The state name.
  final String state;

  /// An annotation naming [state].
  const StateAnnotation(this.state);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateAnnotation && state == other.state;

  @override
  int get hashCode => state.hashCode;

  @override
  String toString() => '{$state}';
}

/// Token match - matches any token and binds its features.
///
/// Used with constraints to filter by token properties:
/// ```
/// noun --> {TOKEN}:W where equals(W.cat, "NN");
/// ```
///
/// The label binds the token's features for constraint evaluation.
final class TokenMatch extends RuleElement {
  /// The label binding the token's features in constraints, or null.
  final String? label;

  /// A match of any token, with an optional [label].
  const TokenMatch([this.label]);

  /// Creates a copy with the given label.
  TokenMatch withLabel(String label) => TokenMatch(label);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TokenMatch && label == other.label;

  @override
  int get hashCode => label.hashCode;

  @override
  String toString() {
    if (label != null) {
      return '{TOKEN}:$label';
    }
    return '{TOKEN}';
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
