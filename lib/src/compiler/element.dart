/// The elements of a compiled syntactic production.
library;

import '../features/value.dart';

/// An element of a compiled syntactic production's right-hand side.
sealed class Element {
  const Element();

  /// The label that binds this element in the production's constraints, or
  /// null.
  String? get label;
}

/// A named symbol (Java `Element.Symbol`). It is satisfied by a syntactic
/// production of [name], or by a token whose category is [name]: a named
/// lexeme, which appears in the tree as a node (S-P8).
final class Named extends Element {
  /// A symbol [name], with an optional [label] and [features], empty by
  /// default.
  Named(this.name, [this.label, Structure? features])
    : features = features ?? Structure.empty;

  /// The symbol's name.
  final String name;

  @override
  final String? label;

  /// The features a production or token must unify with.
  final Structure features;

  @override
  bool operator ==(Object other) =>
      other is Named &&
      name == other.name &&
      label == other.label &&
      features == other.features;

  @override
  int get hashCode => Object.hash(Named, name, label, features);

  @override
  String toString() => 'Named($name, $label, ${features.display()})';
}

/// A token of an anonymous category: an inline literal or regex (Java
/// `Element.Terminal`, S-G3). It appears as a leaf.
final class Anonymous extends Element {
  /// A token of [category], with an optional [label].
  const Anonymous(this.category, [this.label]);

  /// The anonymous category.
  final String category;

  @override
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is Anonymous && category == other.category && label == other.label;

  @override
  int get hashCode => Object.hash(Anonymous, category, label);

  @override
  String toString() => 'Anonymous($category, $label)';
}

/// Any token, `{TOKEN}` (Java `Element.Token`), whose features must unify
/// with [features] (S-F5); a token with features of its own that conflict
/// does not fill it.
final class Any extends Element {
  /// Any token, with an optional [label] and [features], empty by default.
  Any([this.label, Structure? features])
    : features = features ?? Structure.empty;

  @override
  final String? label;

  /// The features a token must unify with.
  final Structure features;

  @override
  bool operator ==(Object other) =>
      other is Any && label == other.label && features == other.features;

  @override
  int get hashCode => Object.hash(Any, label, features);

  @override
  String toString() => 'Any($label, ${features.display()})';
}
