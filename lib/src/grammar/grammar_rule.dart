/// Grammar rule representation.
library;

import '../constraints/expression.dart';
import '../features/value.dart';
import 'rule_element.dart';

/// Whether a production matches one atomic token or a sequence of
/// constituents (S-G1).
enum Kind {
  /// One atomic token.
  lexical,

  /// A sequence of constituents.
  syntactic,
}

/// Left-hand side of a grammar rule with optional features.
final class LHS {
  /// The defined symbol.
  final String symbol;

  /// The features of the constituent the rule builds.
  final Structure features;

  /// The left-hand side for [symbol], with [features] (empty when null).
  LHS(this.symbol, [Structure? features])
    : features = features ?? Structure.empty;

  /// Returns true if this LHS has any features defined.
  bool get hasFeatures => features.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LHS && symbol == other.symbol && features == other.features;

  @override
  int get hashCode => Object.hash(symbol, features);

  @override
  String toString() => hasFeatures ? '$symbol${features.display()}' : symbol;
}

/// A unification grammar production rule: `lhs --> rhs where constraints`.
final class GrammarRule {
  /// A production of [lhs] over [rhs].
  ///
  /// [constraints] are the top-level constraint expressions as written;
  /// weights are [Weighted] nodes until compilation builds the plan. [kind]
  /// defaults to [classify]. [cost] is non-negative and added to the penalty
  /// whenever the production is used (S-P7). [transition] is, for a lexical
  /// production, the state transition applied after a match (`S`, `_`, `!S`,
  /// `^S`).
  GrammarRule(
    this.lhs,
    List<RuleElement> rhs, {
    List<Expression> constraints = const [],
    Kind? kind,
    this.cost = 0,
    this.transition,
  }) : rhs = List.unmodifiable(rhs),
       constraints = List.unmodifiable(constraints),
       kind = kind ?? classify(rhs, transition: transition != null) {
    if (cost < 0) {
      throw ArgumentError.value(cost, 'cost', 'must not be negative');
    }
  }

  /// A production of the symbol [symbol] with no features.
  GrammarRule.simple(
    String symbol,
    List<RuleElement> rhs, [
    List<Expression> constraints = const [],
  ]) : this(LHS(symbol), rhs, constraints: constraints);

  /// The left-hand side.
  final LHS lhs;

  /// The right-hand side elements, in order.
  final List<RuleElement> rhs;

  /// The top-level constraint expressions, as written.
  final List<Expression> constraints;

  /// Whether the production is lexical or syntactic.
  final Kind kind;

  /// The penalty added whenever the production is used.
  final int cost;

  /// For a lexical production, the state transition applied after a match,
  /// or null.
  final String? transition;

  /// Classifies a production (S-G1). A nonterminal or `{TOKEN}` anywhere
  /// makes it syntactic, as does an empty right-hand side. Otherwise it is
  /// lexical if it has a [transition], contains a regex or a state
  /// annotation, or is exactly one plain literal; any other sequence of
  /// literals is syntactic.
  static Kind classify(List<RuleElement> rhs, {bool transition = false}) {
    if (rhs.isEmpty || rhs.any(_syntactic)) {
      return Kind.syntactic;
    }
    if (transition || rhs.any(_lexical)) {
      return Kind.lexical;
    }
    return rhs.length == 1 && rhs.first is Terminal
        ? Kind.lexical
        : Kind.syntactic;
  }

  static bool _syntactic(RuleElement element) => switch (element) {
    Nonterminal() || TokenMatch() => true,
    Alternation(:final options) => options.any(_syntactic),
    Sequence(:final elements) => elements.any(_syntactic),
    Repetition(:final element) => _syntactic(element),
    _ => false,
  };

  static bool _lexical(RuleElement element) => switch (element) {
    Regex() || StateAnnotation() => true,
    Alternation(:final options) => options.any(_lexical),
    Sequence(:final elements) => elements.any(_lexical),
    Repetition(:final element) => _lexical(element),
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GrammarRule &&
          lhs == other.lhs &&
          _listEquals(rhs, other.rhs) &&
          _listEquals(constraints, other.constraints) &&
          kind == other.kind &&
          cost == other.cost &&
          transition == other.transition;

  @override
  int get hashCode => Object.hash(
    lhs,
    Object.hashAll(rhs),
    Object.hashAll(constraints),
    kind,
    cost,
    transition,
  );

  @override
  String toString() {
    final buffer = StringBuffer('$lhs --> ')
      ..write(rhs.isEmpty ? '/* empty */' : rhs.join(' '));
    if (constraints.isNotEmpty) {
      buffer.write(' where ${constraints.join(', ')}');
    }
    if (transition != null) {
      buffer.write(' ==> $transition');
    }
    if (cost > 0) {
      buffer.write(' @$cost');
    }
    buffer.write(';');
    return buffer.toString();
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
