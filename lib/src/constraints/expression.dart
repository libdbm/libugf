/// Constraint expressions (S-C1).
library;

import '../features/value.dart';

/// A constraint expression, evaluated for Boolean truth only (S-C1).
///
/// A [Weighted] node records a weight written in grammar source
/// (`pred():3`, `(...):7`); a `Plan` turns weighted top-level conjuncts into
/// soft groups (S-C2, S-C6), and no weight survives inside a plan's
/// expressions.
sealed class Expression {
  const Expression();
}

/// Conjunction: true when every term is true.
final class And extends Expression {
  /// The conjunction of [terms].
  const And(this.terms);

  /// The conjuncts, in order.
  final List<Expression> terms;

  @override
  bool operator ==(Object other) => other is And && _same(terms, other.terms);

  @override
  int get hashCode => Object.hash(And, Object.hashAll(terms));

  @override
  String toString() => 'And($terms)';
}

/// Disjunction: true when any term is true.
final class Or extends Expression {
  /// The disjunction of [terms].
  const Or(this.terms);

  /// The disjuncts, in order.
  final List<Expression> terms;

  @override
  bool operator ==(Object other) => other is Or && _same(terms, other.terms);

  @override
  int get hashCode => Object.hash(Or, Object.hashAll(terms));

  @override
  String toString() => 'Or($terms)';
}

/// A weight on an expression, as written in grammar source; truth ignores
/// it.
final class Weighted extends Expression {
  /// [term] with [weight].
  const Weighted(this.term, this.weight);

  /// The weighted expression.
  final Expression term;

  /// The weight.
  final int weight;

  @override
  bool operator ==(Object other) =>
      other is Weighted && other.term == term && other.weight == weight;

  @override
  int get hashCode => Object.hash(Weighted, term, weight);

  @override
  String toString() => 'Weighted($term, $weight)';
}

/// Negation.
final class Not extends Expression {
  /// The negation of [term].
  const Not(this.term);

  /// The negated expression.
  final Expression term;

  @override
  bool operator ==(Object other) => other is Not && other.term == term;

  @override
  int get hashCode => Object.hash(Not, term);

  @override
  String toString() => 'Not($term)';
}

/// A predicate call, such as `equals(a, 'b')`.
final class Call extends Expression {
  /// A call of the predicate [name] with [args].
  const Call(this.name, this.args);

  /// The predicate name.
  final String name;

  /// The arguments, in order.
  final List<Value> args;

  @override
  bool operator ==(Object other) =>
      other is Call && other.name == name && _same(args, other.args);

  @override
  int get hashCode => Object.hash(Call, name, Object.hashAll(args));

  @override
  String toString() => '$name(${args.join(', ')})';
}

/// A truth value, produced when part of an expression has already been
/// evaluated (S-C7).
final class Literal extends Expression {
  const Literal._(this.value);

  /// True.
  static const trueValue = Literal._(true);

  /// False.
  static const falseValue = Literal._(false);

  /// The literal for [value].
  static Literal of(bool value) => value ? trueValue : falseValue;

  /// The truth value.
  final bool value;

  @override
  bool operator ==(Object other) => other is Literal && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

bool _same(List<Object> left, List<Object> right) {
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
