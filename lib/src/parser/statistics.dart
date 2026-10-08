/// Counters for one parse.
library;

/// Counters for one parse (PRF-1).
final class Statistics {
  /// Counters; each is 0 unless given.
  const Statistics({
    this.nodes = 0,
    this.edges = 0,
    this.states = 0,
    this.agenda = 0,
    this.completions = 0,
    this.unifications = 0,
    this.evaluations = 0,
    this.calls = 0,
    this.hits = 0,
    this.elapsed = Duration.zero,
  });

  /// Token graph vertices.
  final int nodes;

  /// Token graph edges.
  final int edges;

  /// Chart states created.
  final int states;

  /// Agenda entries processed.
  final int agenda;

  /// Attempts to advance a waiting state over a constituent or a token.
  final int completions;

  /// Unifications performed.
  final int unifications;

  /// Constraint plans evaluated.
  final int evaluations;

  /// Predicate calls made.
  final int calls;

  /// Predicate calls answered from the per-parse memo (PRF-2).
  final int hits;

  /// The time the parse took.
  final Duration elapsed;
}
