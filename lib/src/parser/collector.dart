part of 'session.dart';

/// Collects the diagnostics of one parse (PAR-8): tokenization, unification
/// and constraint failures, ambiguities, and for a rejected input the chart
/// as a lattice. At most [_cap] records are kept. A session creates one only
/// when diagnostics are enabled.
final class _Collector {
  _Collector(this._compiled, this._graph, this._root, this._charts, this._cap) {
    _created++;
  }

  /// How many collectors were created, for testing that none is when
  /// diagnostics are off.
  static var _created = 0;

  final Compiled _compiled;
  final Graph _graph;

  /// The auxiliary root production, left out of the lattice.
  final Production _root;
  final List<_Chart> _charts;

  /// The most records kept; zero for no limit.
  final int _cap;

  final diagnostics = ParseDiagnostics();
  final _rejections = <int, List<PathFailure>>{};
  var _records = 0;

  /// A readable rendering of a plan: required expressions, then weighted
  /// soft groups.
  static String plan(Plan plan) => [
    for (final expression in plan.required) _display(expression),
    for (final soft in plan.soft)
      '(${_display(soft.expression)}):${soft.weight}',
  ].join(', ');

  static String _display(Expression expression) => switch (expression) {
    And(:final terms) => terms.map(_display).join(', '),
    Or(:final terms) => '(${terms.map(_display).join(' | ')})',
    Not(:final term) => '!${_display(term)}',
    Call(:final name, :final args) =>
      '$name(${args.map((arg) => arg.display()).join(', ')})',
    Literal(:final value) => '$value',
    Weighted(:final term, :final weight) => '(${_display(term)}):$weight',
  };

  static String _production(Production production) => [
    '${production.symbol} -->',
    for (final element in production.rhs) _element(element),
  ].join(' ');

  static String _element(Element element) => switch (element) {
    Named(:final name) => name,
    Anonymous(:final category) => category,
    Any() => '{TOKEN}',
  };

  static Span _span(_State state) => Span(
    state.origin.id,
    state.start >= 0 ? state.start : state.origin.offset,
    state.end.offset,
  );

  /// Whether a record may be kept under the cap; counts it.
  bool _record() {
    if (_cap > 0 && _records >= _cap) {
      return false;
    }
    _records++;
    return true;
  }

  /// An error edge: text the lexer could not tokenize.
  void tokenization(Edge edge) {
    if (_record()) {
      diagnostics.recordTokenization(
        TokenizationError(
          edge.start,
          edge.text,
          'a token',
          Span(edge.from.id, edge.start, edge.end),
        ),
      );
    }
  }

  /// A child whose features do not unify with those written on its element
  /// (S-F5).
  void unification(
    String symbol,
    Structure parent,
    Structure child,
    Structure expected,
    String message,
    Vertex target,
    int start,
  ) {
    if (_record()) {
      diagnostics.recordUnification(
        UnificationFailure(
          symbol,
          parent,
          child,
          expected,
          message,
          target.id,
          Span(target.id, start >= 0 ? start : target.offset, target.offset),
        ),
      );
    }
  }

  /// A complete state rejected by a required constraint; also kept for the
  /// lattice.
  void constraint(_State state, Expression failed) {
    if (!_record()) {
      return;
    }
    final production = state.production;
    final reason = 'required constraint is false: ${_display(failed)}';
    final span = _span(state);
    diagnostics.recordConstraint(
      ConstraintFailure(
        production.symbol,
        _display(failed),
        reason,
        state.origin.id,
        span: span,
      ),
    );
    (_rejections[state.end.id] ??= []).add(
      PathFailure(
        LatticeItem(
          _production(production),
          state.dot,
          state.origin.id,
          state.penalty,
          ItemState.rejected,
          '${state.bindings.values}',
        ),
        span,
        reason,
        Cause.constraint,
      ),
    );
  }

  /// A constituent with more than one equally cheap derivation (S-P4).
  void ambiguity(String symbol, Span span) {
    if (_record()) {
      diagnostics.recordAmbiguity(Ambiguity(symbol, span));
    }
  }

  /// No derivation covers the input: the furthest progress and the chart
  /// as a lattice.
  void rejected() {
    if (_record()) {
      final furthest = _furthest();
      final position = Span(furthest.id, furthest.offset, furthest.offset);
      diagnostics
        ..recordIssue(
          ParsingIssue(
            'no derivation of ${_compiled.start} covers the input',
            furthest.id,
            position,
          ),
        )
        ..lattice = _lattice(furthest, position);
    }
  }

  /// The chart as a lattice: one column per vertex that has states, with
  /// its items, the elements expected there, and dead ends (items whose
  /// next token never arrived). At most [_cap] items and failures are kept;
  /// columns are collected from the end backwards, so a truncated snapshot
  /// keeps those nearest the furthest progress.
  Lattice _lattice(Vertex furthest, Span position) {
    final columns = <Column>[];
    var kept = 0;
    var truncated = false;
    for (final vertex in _graph.nodes.reversed) {
      if (_cap > 0 && kept >= _cap) {
        truncated = true;
        break;
      }
      final states = _charts[vertex.id].states.values;
      // A column with no states can still hold a rejected completion, the
      // reason the parse stopped there.
      if (states.isEmpty && !_rejections.containsKey(vertex.id)) {
        continue;
      }
      final span = Span(vertex.id, vertex.offset, vertex.offset);
      final items = <LatticeItem>[];
      final expected = <String>{};
      final failures = <PathFailure>[];
      for (final state in states) {
        if (state.superseded || identical(state.production, _root)) {
          continue;
        }
        if (_cap > 0 && kept >= _cap) {
          truncated = true;
          break;
        }
        kept++;
        final item = LatticeItem(
          _production(state.production),
          state.dot,
          state.origin.id,
          state.penalty,
          state.complete ? ItemState.complete : ItemState.active,
          state.complete
              ? state.features.display()
              : '${state.bindings.values}',
        );
        items.add(item);
        if (state.complete) {
          continue;
        }
        final next = state.next;
        final described = _element(next);
        expected.add(described);
        final pending = next is Named && !_compiled.lexical(next.name);
        if (!pending &&
            !_graph
                .edgesOf(vertex)
                .any((edge) => Session.matches(next, edge))) {
          failures.add(
            PathFailure(item, span, 'expected $described', Cause.deadEnd),
          );
        }
      }
      for (final rejection in _rejections[vertex.id] ?? const <PathFailure>[]) {
        if (_cap > 0 && kept >= _cap) {
          truncated = true;
          break;
        }
        kept++;
        failures.add(rejection);
      }
      columns.add(Column(vertex.id, span, items, expected.toList(), failures));
    }
    return Lattice(
      columns.reversed.toList(),
      furthest.id,
      position,
      truncated: truncated,
    );
  }

  /// The furthest vertex any state reached.
  Vertex _furthest() {
    for (var index = _graph.nodes.length - 1; index >= 0; index--) {
      if (_charts[index].states.isNotEmpty) {
        return _graph.nodes[index];
      }
    }
    return _graph.start;
  }
}
