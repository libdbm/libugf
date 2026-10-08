/// A production's constraints, split into required expressions and soft
/// groups.
library;

import '../result.dart';
import 'expression.dart';

/// A soft group: an expression with a positive weight. When the expression
/// is false the derivation is kept and the weight is added to its penalty,
/// once (S-C4).
final class Soft {
  /// The group [expression] charging [weight], which must be positive.
  Soft(this.expression, this.weight) {
    if (weight <= 0) {
      throw ArgumentError.value(weight, 'weight', 'must be positive');
    }
  }

  /// The group's expression, evaluated for truth only.
  final Expression expression;

  /// The penalty charged when the expression is false.
  final int weight;

  @override
  bool operator ==(Object other) =>
      other is Soft && other.expression == expression && other.weight == weight;

  @override
  int get hashCode => Object.hash(expression, weight);

  @override
  String toString() => 'Soft($expression, $weight)';
}

/// The constraints of a production: [required] expressions, every one of
/// which must be true (S-C3), and [soft] groups, each of which charges its
/// weight when false (S-C2, S-C4).
final class Plan {
  /// A plan with [required] expressions and [soft] groups, both copied.
  Plan(List<Expression> required, List<Soft> soft)
    : required = List.unmodifiable(required),
      soft = List.unmodifiable(soft);

  /// No constraints.
  static final empty = Plan(const [], const []);

  /// Expressions that reject the derivation when false.
  final List<Expression> required;

  /// Weighted groups that add to the penalty when false.
  final List<Soft> soft;

  /// Builds a plan from the top-level constraint expressions of a
  /// production.
  ///
  /// Unweighted conjunctions at the top are flattened; each remaining
  /// unweighted conjunct is required and each [Weighted] one is a soft group
  /// (S-C6). Weights inside a soft group are ignored (S-C5). A weight anywhere
  /// else (under `or` or `not`, or nested in a required expression) is a
  /// `constraint.weight` error (S-C6), and every such error is reported. A
  /// zero weight can never change a derivation, so that group is dropped.
  static Result<Plan, ErrorDetails> of(List<Expression> constraints) {
    final required = <Expression>[];
    final soft = <Soft>[];
    final errors = <String>[];
    for (final constraint in constraints) {
      _top(constraint, required, soft, errors);
    }
    return errors.isEmpty
        ? Success(Plan(required, soft))
        : Failure(ErrorDetails.from('constraint.weight', errors));
  }

  static void _top(
    Expression expression,
    List<Expression> required,
    List<Soft> soft,
    List<String> errors,
  ) {
    switch (expression) {
      case Weighted(:final term, :final weight):
        final stripped = _strip(term, true, errors);
        if (weight > 0) {
          soft.add(Soft(stripped, weight));
        }
      case And(:final terms):
        for (final term in terms) {
          _top(term, required, soft, errors);
        }
      default:
        required.add(_strip(expression, false, errors));
    }
  }

  /// [expression] without weights; [inside] is true within a soft group,
  /// where weights are ignored (S-C5).
  static Expression _strip(
    Expression expression,
    bool inside,
    List<String> errors,
  ) => switch (expression) {
    Weighted(:final term, :final weight) => () {
      if (!inside) {
        errors.add(
          'weight $weight on ${_display(term)} is under '
          "'or' or 'not'; a soft group must be a top-level conjunct",
        );
      }
      return _strip(term, true, errors);
    }(),
    And(:final terms) => And([
      for (final term in terms) _strip(term, inside, errors),
    ]),
    Or(:final terms) => Or([
      for (final term in terms) _strip(term, inside, errors),
    ]),
    Not(:final term) => Not(_strip(term, inside, errors)),
    Call() || Literal() => expression,
  };

  static String _display(Expression expression) =>
      expression is Call ? '${expression.name}(...)' : 'a group';

  /// Whether there are no constraints.
  bool get isEmpty => required.isEmpty && soft.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is Plan &&
      _same(other.required, required) &&
      _same(other.soft, soft);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(required), Object.hashAll(soft));

  @override
  String toString() => 'Plan($required, $soft)';

  static bool _same(List<Object> left, List<Object> right) {
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
}
