/// The result of a parse.
library;

import 'diagnostics.dart';
import 'parse_tree.dart';
import 'statistics.dart';
import 'stop.dart';

/// How a parse ended (S-P5). Only [accepted] carries a tree.
enum Outcome {
  /// A derivation of the start symbol covers the input.
  accepted,

  /// No derivation covers the input.
  rejected,

  /// A resource limit was reached, or a penalty overflowed.
  limit,

  /// The parse was cancelled.
  cancelled,
}

/// The result of a parse: how it ended, the selected tree and its penalty.
///
/// A penalty of 0 is a parse with no soft constraint violated. [ambiguous]
/// is true when two or more distinct derivations share the lowest penalty:
/// the penalties could not rank them, so [tree] is the one the selection
/// rules chose (S-P3), and a caller that must not guess should refuse it.
final class ParseResult {
  /// A result that ended with [outcome].
  const ParseResult(
    this.outcome, {
    this.tree,
    this.penalty = 0,
    this.ambiguous = false,
    this.tied = false,
    this.stop,
    this.statistics = const Statistics(),
    this.diagnostics,
  });

  /// How the parse ended.
  final Outcome outcome;

  /// The selected tree; null unless [outcome] is [Outcome.accepted].
  final ParseTree? tree;

  /// The penalty of [tree]; 0 when no soft constraint was violated.
  final int penalty;

  /// Whether two or more distinct derivations share the lowest penalty.
  final bool ambiguous;

  /// Whether only the last S-P3 rule, lexical production declaration order
  /// or the caller's order, chose the tree or a derivation inside it: the
  /// warning S-P3 asks for.
  final bool tied;

  /// Why a [Outcome.limit] or [Outcome.cancelled] parse ended; null
  /// otherwise.
  final Stop? stop;

  /// The counters of the parse.
  final Statistics statistics;

  /// What went wrong and where the parse was ambiguous, when
  /// `Options.diagnostics` is on; null otherwise.
  final ParseDiagnostics? diagnostics;

  /// Whether a required constraint failure was recorded.
  bool get hasConstraintFailures =>
      diagnostics?.constraints.isNotEmpty ?? false;

  /// Whether the parse was accepted.
  bool get success => outcome == Outcome.accepted;

  @override
  String toString() {
    final out = StringBuffer('ParseResult(${outcome.name}, penalty: $penalty');
    if (stop case final stopped?) {
      out.write(', stop: ${stopped.message}');
    }
    if (diagnostics case final recorded? when recorded.hasFailures) {
      out.write(', diagnostics:\n${recorded.report()}');
    }
    out.write(')');
    return out.toString();
  }
}
