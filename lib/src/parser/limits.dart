/// Resource limits for one parse.
library;

/// Resource limits for one parse (PAR-6), covering lexing, parsing, tree
/// selection and diagnostics. A count of zero means unlimited, and a zero
/// deadline means none. A parse that reaches a limit ends with
/// `Outcome.limit` and a `Stop` naming the resource.
final class Limits {
  /// Limits; none may be negative.
  Limits({
    this.states = 0,
    this.agenda = 0,
    this.links = 0,
    this.nodes = 0,
    this.depth = 0,
    this.tree = 0,
    this.diagnostics = 0,
    this.deadline = Duration.zero,
  }) {
    if (states < 0 ||
        agenda < 0 ||
        links < 0 ||
        nodes < 0 ||
        depth < 0 ||
        tree < 0 ||
        diagnostics < 0 ||
        deadline.isNegative) {
      throw ArgumentError('limits must not be negative');
    }
  }

  const Limits._(
    this.states,
    this.agenda,
    this.links,
    this.nodes,
    this.depth,
    this.tree,
    this.diagnostics,
    this.deadline,
  );

  /// No limits.
  static const none = Limits._(0, 0, 0, 0, 0, 0, 0, Duration.zero);

  /// The limits `Options` uses by default, as Java's: roughly seven times
  /// the largest chart, and forty-six times the largest token graph, of any
  /// port sample, and one minute.
  static const defaults = Limits._(
    10000000,
    10000000,
    20000000,
    1000000,
    1000,
    10000000,
    10000,
    Duration(minutes: 1),
  );

  /// The most chart states a parse may create, counting replacements of a
  /// state by a cheaper one.
  final int states;

  /// The most agenda entries a parse may process.
  final int agenda;

  /// The most packed derivation links a parse may record.
  final int links;

  /// The most token graph vertices, from the lexer or from a caller's or
  /// enhancer's graph.
  final int nodes;

  /// The deepest lexical state stack the lexer may build.
  final int depth;

  /// The most nodes the selected tree may have.
  final int tree;

  /// The most diagnostic records retained when diagnostics are enabled.
  final int diagnostics;

  /// The longest a parse may take, lexing included.
  final Duration deadline;

  /// These limits with the given ones replaced.
  Limits copy({
    int? states,
    int? agenda,
    int? links,
    int? nodes,
    int? depth,
    int? tree,
    int? diagnostics,
    Duration? deadline,
  }) => Limits(
    states: states ?? this.states,
    agenda: agenda ?? this.agenda,
    links: links ?? this.links,
    nodes: nodes ?? this.nodes,
    depth: depth ?? this.depth,
    tree: tree ?? this.tree,
    diagnostics: diagnostics ?? this.diagnostics,
    deadline: deadline ?? this.deadline,
  );
}
