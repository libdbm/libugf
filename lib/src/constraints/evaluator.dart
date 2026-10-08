/// Evaluation of constraint expressions and plans.
library;

import '../arithmetic.dart';
import 'expression.dart';
import 'plan.dart';
import 'verdict.dart';

/// Evaluates constraint expressions and plans. Truth is Boolean (S-C1); a
/// plan is rejected when a required expression is false (S-C3) and otherwise
/// costs the weights of its false soft groups, each once (S-C4).
abstract final class Evaluator {
  /// Whether [expression] is true, with [calls] deciding each predicate
  /// call. Terms are evaluated left to right and short-circuit; weights play
  /// no part.
  static bool truth(Expression expression, bool Function(Call call) calls) =>
      switch (expression) {
        And(:final terms) => terms.every((term) => truth(term, calls)),
        Or(:final terms) => terms.any((term) => truth(term, calls)),
        Not(:final term) => !truth(term, calls),
        Call() => calls(expression),
        Literal(:final value) => value,
        Weighted(:final term) => truth(term, calls),
      };

  /// Evaluates a production's constraints: rejected if any required
  /// expression is false (S-C3), in order; otherwise accepted with the sum of
  /// the weights of false soft groups, each charged once (S-C4). A sum beyond
  /// the platform's integers yields [Overflow] (S-C10).
  static Verdict evaluate(Plan plan, bool Function(Call call) calls) {
    for (final expression in plan.required) {
      if (!truth(expression, calls)) {
        return Rejected(expression);
      }
    }
    var penalty = 0;
    for (final group in plan.soft) {
      if (!truth(group.expression, calls)) {
        final total = sum(penalty, group.weight);
        if (total == null) {
          return const Overflow();
        }
        penalty = total;
      }
    }
    return Accepted(penalty);
  }

  /// Partially evaluates [expression] (S-C7): each call whose name is in
  /// [names] is replaced by its truth value, and the result is simplified
  /// with ordinary Boolean identities. Calls not in [names] are kept, so the
  /// residual has the same truth as the original under any evaluation of the
  /// remaining calls.
  static Expression residual(
    Expression expression,
    bool Function(Call call) calls,
    Set<String> names,
  ) {
    switch (expression) {
      case And(:final terms):
        final kept = <Expression>[];
        for (final term in terms) {
          final reduced = residual(term, calls, names);
          if (reduced == Literal.falseValue) {
            return Literal.falseValue;
          }
          if (reduced != Literal.trueValue) {
            kept.add(reduced);
          }
        }
        return _combine(kept, Literal.trueValue, And.new);
      case Or(:final terms):
        final kept = <Expression>[];
        for (final term in terms) {
          final reduced = residual(term, calls, names);
          if (reduced == Literal.trueValue) {
            return Literal.trueValue;
          }
          if (reduced != Literal.falseValue) {
            kept.add(reduced);
          }
        }
        return _combine(kept, Literal.falseValue, Or.new);
      case Not(:final term):
        final reduced = residual(term, calls, names);
        return reduced is Literal ? Literal.of(!reduced.value) : Not(reduced);
      case Call(:final name):
        return names.contains(name)
            ? Literal.of(calls(expression))
            : expression;
      case Literal():
        return expression;
      case Weighted(:final term):
        return residual(term, calls, names);
    }
  }

  /// An empty term list is the identity, a single term stands alone,
  /// otherwise a new node.
  static Expression _combine(
    List<Expression> terms,
    Expression identity,
    Expression Function(List<Expression>) node,
  ) => switch (terms.length) {
    0 => identity,
    1 => terms.first,
    _ => node(List.unmodifiable(terms)),
  };
}
