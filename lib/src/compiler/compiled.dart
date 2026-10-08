/// A compiled grammar.
library;

import '../constraints/plan.dart';
import '../constraints/predicates.dart';
import '../features/value.dart';
import 'element.dart';

/// A compiled lexical category: one atomic pattern that produces a token of
/// [category] (S-G2).
final class Lexeme {
  /// A lexeme. [states] and [labels] are copied.
  Lexeme({
    required this.id,
    required this.category,
    required this.pattern,
    required this.features,
    required List<String> states,
    required this.transition,
    required this.plan,
    required this.cost,
    required List<String> labels,
    required this.anonymous,
    this.literal,
  }) : states = List.unmodifiable(states),
       labels = List.unmodifiable(labels);

  /// Stable identifier, in compilation order.
  final int id;

  /// The token category: the production's symbol, or for an anonymous
  /// category the source text of an inline literal (quoted) or regex.
  final String category;

  /// The complete pattern; labelled parts are named groups `l0`, `l1`, ...
  final RegExp pattern;

  /// The production's left-hand features, carried by every token.
  final Structure features;

  /// The lexical states the lexeme matches in; empty means every state.
  final List<String> states;

  /// The state transition applied after a match (`S`, `_`, `!S`, `^S`), or
  /// null.
  final String? transition;

  /// The production's constraints.
  final Plan plan;

  /// The production cost, added to every token's cost.
  final int cost;

  /// The labels of the named groups, in group-number order.
  final List<String> labels;

  /// True for an inline literal or regex (S-G3).
  final bool anonymous;

  /// The text when the pattern is one unlabelled literal (an inline literal,
  /// or a production of one), or null.
  final String? literal;

  /// The named group that holds the text of the [index]th label.
  static String group(int index) => 'l$index';

  @override
  String toString() => 'Lexeme($id, $category, ${pattern.pattern})';
}

/// A compiled syntactic production. No repetition, alternation, regex or
/// state annotation remains in a right-hand side (S-G4).
final class Production {
  /// A production. [rhs] is copied.
  Production({
    required this.id,
    required this.symbol,
    required this.features,
    required List<Element> rhs,
    required this.plan,
    required this.cost,
    required this.auxiliary,
  }) : rhs = List.unmodifiable(rhs);

  /// Stable identifier in compilation order; tie-breaking reads it (S-P3).
  final int id;

  /// The left-hand symbol.
  final String symbol;

  /// The left-hand features.
  final Structure features;

  /// The right-hand side.
  final List<Element> rhs;

  /// The production's constraints.
  final Plan plan;

  /// The production cost (S-P7).
  final int cost;

  /// True for a production introduced by lowering, which does not appear in
  /// trees (S-P8).
  final bool auxiliary;

  @override
  bool operator ==(Object other) =>
      other is Production &&
      id == other.id &&
      symbol == other.symbol &&
      features == other.features &&
      _same(rhs, other.rhs) &&
      plan == other.plan &&
      cost == other.cost &&
      auxiliary == other.auxiliary;

  @override
  int get hashCode => Object.hash(
    id,
    symbol,
    features,
    Object.hashAll(rhs),
    plan,
    cost,
    auxiliary,
  );

  static bool _same(List<Element> left, List<Element> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => 'Production($id, $symbol --> ${rhs.join(' ')})';
}

/// An immutable compiled grammar, shared by the lexer, the parser and the
/// generator.
final class Compiled {
  /// A compiled grammar. Every collection is copied.
  Compiled({
    required this.start,
    required List<Lexeme> lexemes,
    required List<Production> productions,
    required this.predicates,
    required this.whitespace,
    required Set<String> nullable,
    required Map<String, List<Production>> index,
    required Set<String> categories,
    required Set<String> skips,
  }) : lexemes = List.unmodifiable(lexemes),
       productions = List.unmodifiable(productions),
       nullable = Set.unmodifiable(nullable),
       index = Map.unmodifiable({
         for (final MapEntry(:key, :value) in index.entries)
           key: List<Production>.unmodifiable(value),
       }),
       categories = Set.unmodifiable(categories),
       skips = Set.unmodifiable(skips);

  /// The start symbol.
  final String start;

  /// Every lexeme, by id.
  final List<Lexeme> lexemes;

  /// Every syntactic production, by id.
  final List<Production> productions;

  /// The registry the grammar was compiled against.
  final Predicates predicates;

  /// Skipped between tokens (S-L4), or null for none.
  final RegExp? whitespace;

  /// The symbols that can derive the empty string.
  final Set<String> nullable;

  /// The productions by left-hand symbol, in id order.
  final Map<String, List<Production>> index;

  /// The categories of named lexemes, which a [Named] element can also
  /// match.
  final Set<String> categories;

  /// The categories whose matches are discarded between tokens (S-L4).
  final Set<String> skips;

  /// The productions for [symbol], in id order.
  List<Production> productionsFor(String symbol) => index[symbol] ?? const [];

  /// Whether [symbol] names a lexical category.
  bool lexical(String symbol) => categories.contains(symbol);
}
