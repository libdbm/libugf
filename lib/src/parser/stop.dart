/// Why a parse stopped early.
library;

import 'parse_result.dart';

/// Why a parse ended with [Outcome.limit] or [Outcome.cancelled]: the
/// [resource] that ran out, the amount [observed] when the parse stopped or
/// -1 if it is not counted, the [allowed] limit or -1 if there is none, and
/// a readable [message].
final class Stop {
  /// A stop for [resource].
  const Stop(this.resource, this.observed, this.allowed, this.message);

  /// Chart states created (`Limits.states`).
  static const states = 'states';

  /// Agenda entries processed (`Limits.agenda`).
  static const agenda = 'agenda';

  /// Packed derivation links recorded (`Limits.links`).
  static const links = 'links';

  /// Token graph vertices (`Limits.nodes`).
  static const nodes = 'nodes';

  /// Lexical state stack depth (`Limits.depth`).
  static const depth = 'depth';

  /// Nodes of the selected tree (`Limits.tree`).
  static const tree = 'tree';

  /// The parse took longer than `Limits.deadline`.
  static const deadline = 'deadline';

  /// A penalty sum overflowed (S-C10).
  static const penalty = 'penalty';

  /// The lexer could not build the token graph.
  static const lexer = 'lexer';

  /// The caller cancelled the parse (`Options.cancel`).
  static const interrupt = 'interrupt';

  /// The resource that ran out: one of the constants above.
  final String resource;

  /// The amount observed when the parse stopped, or -1 if not counted.
  final int observed;

  /// The limit, or -1 if there is none.
  final int allowed;

  /// A readable description.
  final String message;

  @override
  String toString() => 'Stop($resource: $message)';
}
