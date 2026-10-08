/// Events of a parse, delivered to a [ParseObserver].
library;

import '../features/value.dart';
import '../lexer/graph.dart';
import 'parse_result.dart';

/// How many events have been built; for testing that none is built for
/// [ParseObserver.none]. Not exported.
int get built => ParseEvent._built;

/// Receives the events of a parse for visualization, logging or debugging
/// (Java's nine callbacks are one [observe] over the sealed [ParseEvent]).
/// Events are immutable, so an observer may keep them.
abstract base class ParseObserver {
  /// For subclasses.
  const ParseObserver();

  /// The observer that receives nothing; with it, no event is built.
  static const ParseObserver none = _None();

  /// Called for each event; does nothing unless overridden.
  void observe(ParseEvent event) {}
}

final class _None extends ParseObserver {
  const _None();
}

/// An event of a parse. Positions are token graph vertex ids, and every
/// event carries public data only (PAR-12).
sealed class ParseEvent {
  ParseEvent() {
    _built++;
  }

  static var _built = 0;
}

/// Parsing begins: the [graph] being parsed as the symbol [start].
final class Started extends ParseEvent {
  /// An event for parsing [graph] as [start].
  Started(this.graph, this.start);

  /// The token graph being parsed.
  final Graph graph;

  /// The start symbol.
  final String start;
}

/// Parsing ends with [result], after [elapsed], lexing included.
final class Ended extends ParseEvent {
  /// An event for a parse ending with [result] after [elapsed].
  Ended(this.result, this.elapsed);

  /// The result of the parse.
  final ParseResult result;

  /// The time the parse took, lexing included.
  final Duration elapsed;
}

/// The production with id [production] for [symbol] was predicted at
/// [position].
final class Predicted extends ParseEvent {
  /// An event for predicting [production] for [symbol] at [position].
  Predicted(this.position, this.symbol, this.production);

  /// The vertex id of the prediction.
  final int position;

  /// The predicted symbol.
  final String symbol;

  /// The id of the predicted production.
  final int production;
}

/// A token of [category] with [text] was consumed from [position].
final class Scanned extends ParseEvent {
  /// An event for consuming a token of [category] with [text] from
  /// [position].
  Scanned(this.position, this.category, this.text);

  /// The vertex id the token starts at.
  final int position;

  /// The token's category, or null for a caller token with none.
  final String? category;

  /// The token's text.
  final String text;
}

/// A constituent of [symbol] from [origin] to [position] was completed by
/// the production with id [production], with total [penalty].
final class Completed extends ParseEvent {
  /// An event for completing [symbol] from [origin] to [position] by
  /// [production], with total [penalty].
  Completed(
    this.origin,
    this.position,
    this.symbol,
    this.production,
    this.penalty,
  );

  /// The vertex id the constituent starts at.
  final int origin;

  /// The vertex id the constituent ends at.
  final int position;

  /// The completed symbol.
  final String symbol;

  /// The id of the completing production.
  final int production;

  /// The constituent's total penalty.
  final int penalty;
}

/// The features [target] written on an element were unified with a child's
/// [completed] features, ending at [position]: the [result] if unification
/// succeeded, or null, and the [bindings] after it. [waiting] is the
/// waiting production's left-hand features.
final class Unified extends ParseEvent {
  /// An event for unifying [target] with [completed] at [position].
  Unified(
    this.position,
    this.waiting,
    this.completed,
    this.target,
    this.result,
    Map<String, Value> bindings,
  ) : bindings = Map.unmodifiable(bindings);

  /// The vertex id the child ends at.
  final int position;

  /// The waiting production's left-hand features.
  final Structure waiting;

  /// The completed child's features.
  final Structure completed;

  /// The features written on the element.
  final Structure target;

  /// The unified features, or null if unification failed.
  final Structure? result;

  /// The variable bindings after unification.
  final Map<String, Value> bindings;
}

/// The constraints [expression] of a production of [symbol] ending at
/// [position] were evaluated: whether every required expression [passed],
/// and the weights of false soft groups when it did (Java
/// `ConstraintEval`).
final class Evaluated extends ParseEvent {
  /// An event for evaluating [expression] for [symbol] at [position].
  Evaluated(
    this.position,
    this.symbol,
    this.expression,
    this.passed,
    this.penalty,
  );

  /// The vertex id the production ends at.
  final int position;

  /// The production's symbol.
  final String symbol;

  /// The constraints, as text.
  final String expression;

  /// Whether every required expression held.
  final bool passed;

  /// The summed weights of false soft groups, when [passed].
  final int penalty;
}

/// The agenda of [position] was finished with [states] in its chart (Java
/// `Position`).
final class Finished extends ParseEvent {
  /// An event for finishing the agenda of [position] with [states].
  Finished(this.position, this.states);

  /// The vertex id whose agenda was finished.
  final int position;

  /// The number of states in the vertex's chart.
  final int states;
}

/// No token matched at [position], so the lexer produced an error token
/// with [token] (S-L5); [expected] are the elements the chart expected.
final class Unexpected extends ParseEvent {
  /// An event for an error token with [token] at [position].
  Unexpected(this.position, this.token, Set<String> expected)
    : expected = Set.unmodifiable(expected);

  /// The vertex id of the error token.
  final int position;

  /// The error token's text.
  final String token;

  /// The elements the chart expected at [position].
  final Set<String> expected;
}
