/// Expressions built from math.ug parse trees, and their evaluation: a port
/// of Java `MathExpr`, `MathBuilder` and `MathEvaluator`.
library;

import 'dart:math' as math;

import 'package:libugf/libugf.dart' show Leaf, Node, ParseTree;

/// An expression.
sealed class Expression {
  const Expression();
}

/// `left operator right`, with `+ - * / % ^`.
final class Binary extends Expression {
  const Binary(this.left, this.operator, this.right);

  final Expression left;
  final String operator;
  final Expression right;
}

/// `operator operand`, with `+ -`.
final class Unary extends Expression {
  const Unary(this.operator, this.operand);

  final String operator;
  final Expression operand;
}

final class Constant extends Expression {
  const Constant(this.value);

  final double value;
}

final class Variable extends Expression {
  const Variable(this.name);

  final String name;
}

/// `name(args)`.
final class Call extends Expression {
  const Call(this.name, this.args);

  final String name;
  final List<Expression> args;
}

/// The expression of a math.ug tree.
Expression build(ParseTree tree) => switch (tree) {
  Leaf() => throw ArgumentError('Cannot build from leaf: ${tree.text}'),
  Node(symbol: 'expr') => _binary(tree, 'expr', 'term', const {'+', '-'}),
  Node(symbol: 'term') => _binary(tree, 'term', 'factor', const {
    '*',
    '/',
    '%',
  }),
  Node(symbol: 'factor') => _factor(tree),
  Node(symbol: 'atom') => _atom(tree),
  Node(:final symbol) => throw ArgumentError('Unknown symbol: $symbol'),
};

/// `left --> right` or `left --> left operator right`.
Expression _binary(
  Node node,
  String left,
  String right,
  Set<String> operators,
) {
  final children = node.children;
  if (children.length == 1) {
    return build(children.single);
  }
  Expression? first;
  String? operator;
  Expression? second;
  for (final child in children) {
    switch (child) {
      case Node(:final symbol) when symbol == left:
        first = build(child);
      case Node(:final symbol) when symbol == right:
        second = build(child);
      case Leaf(:final text) when operators.contains(text):
        operator = text;
      default:
        break;
    }
  }
  if (first == null || operator == null || second == null) {
    throw ArgumentError('Invalid ${node.symbol} node');
  }
  return Binary(first, operator, second);
}

/// `atom`, `atom '^' factor`, `'-' factor` or `'+' factor`.
Expression _factor(Node node) {
  final children = node.children;
  if (children.length == 1) {
    return build(children.single);
  }
  if (children.first case Leaf(:final text) when text == '-' || text == '+') {
    return Unary(text, build(children.last));
  }
  return Binary(build(children.first), '^', build(children.last));
}

/// A number, a variable, a parenthesised expression, or a function call.
Expression _atom(Node node) {
  final children = node.children;
  if (children.length == 1) {
    final child = children.single as Node;
    return switch (child.symbol) {
      'number' => Constant(double.parse(child.text)),
      'variable' => Variable(child.text),
      _ => throw ArgumentError('Invalid atom node'),
    };
  }
  final args = [
    for (final child in children)
      if (child case Node(symbol: 'expr')) build(child),
  ];
  if (children.first case Node(symbol: 'function', :final text)) {
    return Call(text, args);
  }
  return args.single;
}

/// The value of [expression] with [variables] bound.
double evaluate(
  Expression expression, [
  Map<String, double> variables = const {},
]) => switch (expression) {
  Constant(:final value) => value,
  Variable(:final name) =>
    variables[name] ?? (throw StateError('Undefined variable: $name')),
  Binary(:final left, :final operator, :final right) => _apply(
    operator,
    evaluate(left, variables),
    evaluate(right, variables),
  ),
  Unary(:final operator, :final operand) =>
    operator == '-'
        ? -evaluate(operand, variables)
        : evaluate(operand, variables),
  Call(:final name, :final args) => _call(name, [
    for (final arg in args) evaluate(arg, variables),
  ]),
};

double _apply(String operator, double left, double right) => switch (operator) {
  '+' => left + right,
  '-' => left - right,
  '*' => left * right,
  '/' => right == 0 ? throw StateError('Division by zero') : left / right,
  '%' => left.remainder(right),
  '^' => math.pow(left, right).toDouble(),
  _ => throw ArgumentError('Unknown operator: $operator'),
};

double _call(String name, List<double> args) => switch ((name, args)) {
  ('sin', [final x]) => math.sin(x),
  ('cos', [final x]) => math.cos(x),
  ('tan', [final x]) => math.tan(x),
  ('sqrt', [final x]) => math.sqrt(x),
  ('abs', [final x]) => x.abs(),
  ('log', [final x]) => math.log(x) / math.ln10,
  ('ln', [final x]) => math.log(x),
  ('exp', [final x]) => math.exp(x),
  ('pow', [final x, final y]) => math.pow(x, y).toDouble(),
  ('min', [final x, final y]) => math.min(x, y),
  ('max', [final x, final y]) => math.max(x, y),
  _ => throw StateError(
    'Function $name with arity ${args.length} not supported',
  ),
};

/// [expression] fully parenthesised.
String display(Expression expression) => switch (expression) {
  Constant(:final value) => '$value',
  Variable(:final name) => name,
  Binary(:final left, :final operator, :final right) =>
    '(${display(left)} $operator ${display(right)})',
  Unary(:final operator, :final operand) => '$operator${display(operand)}',
  Call(:final name, :final args) => '$name(${args.map(display).join(', ')})',
};
