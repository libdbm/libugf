/// One parse over a token graph.
library;

import 'dart:collection';
import 'dart:math';

import '../arithmetic.dart';
import '../compiler/compiled.dart';
import '../compiler/element.dart';
import '../constraints/evaluator.dart';
import '../constraints/expression.dart';
import '../constraints/plan.dart';
import '../constraints/predicates.dart';
import '../constraints/verdict.dart';
import '../features/unifier.dart';
import '../features/value.dart';
import '../features/values.dart';
import '../lexer/graph.dart';
import '../result.dart';
import 'diagnostics.dart';
import 'events.dart';
import 'parse_result.dart';
import 'parse_tree.dart';
import 'sequence.dart';
import 'options.dart';
import 'statistics.dart';
import 'stop.dart';

part 'collector.dart';
part 'memo.dart';
part 'selector.dart';
part 'state.dart';

/// How many diagnostic collectors sessions have created; for testing that
/// none is created when diagnostics are off. Not exported.
int get collectors => _Collector._created;

/// One parse: the chart and agenda for a single input (PAR-5).
///
/// Vertices are processed in id order, a topological order. Each vertex's
/// chart indexes waiting states by the symbol they expect and completed
/// states by symbol and origin, so completion joins a waiting state with a
/// constituent whichever arrives first (PAR-1).
final class Session {
  /// A session parsing [graph], whose offsets index [_input], as [root]
  /// with [compiled]'s productions. [_referenced] holds, by production id,
  /// the labels its constraints read; only those enter state keys. With
  /// [_canonical] false, states are identified by their raw bindings (for
  /// testing S-P9).
  Session(
    this._compiled,
    this._root,
    this._graph,
    this._input,
    this._referenced,
    this._options,
    this._clock, [
    this._canonical = true,
  ]) : _charts = [for (final _ in _graph.nodes) _Chart()],
       _memo = _Memo(_compiled.predicates);

  final Options _options;

  /// Receives events; none is built for [ParseObserver.none] (PAR-8).
  ParseObserver get _observer => _options.observer;

  bool get _watched => !identical(_observer, ParseObserver.none);

  /// Created only when diagnostics are enabled.
  late final _collector = _options.diagnostics
      ? _Collector(
          _compiled,
          _graph,
          _root,
          _charts,
          _options.limits.diagnostics,
        )
      : null;

  /// Started when the parse began, lexing included.
  final Stopwatch _clock;

  /// Why the parse is stopping, once a limit is reached.
  Stop? _stop;

  var _states = 0;
  var _linked = 0;
  var _built = 0;
  var _checks = 0;
  var _processed = 0;
  var _completions = 0;
  var _unifications = 0;
  var _evaluations = 0;

  final Compiled _compiled;

  /// The input the graph's offsets index, or null for a caller graph.
  final String? _input;
  final Map<int, Set<String>> _referenced;
  final bool _canonical;

  /// Each edge's features renamed apart, by edge identity (S-F5).
  final _renamedEdges = Map<Edge, Structure>.identity();

  /// The suffix counter for renaming constituents apart (S-F5).
  var _fresh = 0;

  final _Memo _memo;

  /// The token indexes at which each vertex is reached, computed on first
  /// use.
  List<Structure>? _positions;

  /// The categories of the tokens leaving each vertex, by vertex id.
  final _following = <int, Structure>{};

  /// The auxiliary root production: the start symbol, or another symbol.
  final Production _root;

  final Graph _graph;
  final List<_Chart> _charts;

  /// Why a parse whose penalty overflowed stopped.
  static const overflow = Stop(
    Stop.penalty,
    -1,
    -1,
    'a penalty sum overflowed 64 bits (S-C10)',
  );

  /// Whether a token edge can be advanced over as [element]: a named symbol
  /// matches its category, an anonymous terminal its anonymous category, and
  /// `{TOKEN}` any token but an error.
  static bool matches(Element element, Edge edge) => switch (element) {
    Named(:final name) => name == edge.category,
    Anonymous(:final category) => category == edge.category,
    Any() => edge.category != Edge.error,
  };

  /// Why a cancelled parse stopped.
  static const cancelled = Stop(
    Stop.interrupt,
    -1,
    -1,
    'the parse was cancelled',
  );

  /// Runs the parse.
  ParseResult run() {
    if (_collector case final collector?) {
      for (final edge in _graph.edges) {
        if (edge.category == Edge.error) {
          collector.tokenization(edge);
        }
      }
    }
    if (_watched) {
      _observer.observe(Started(_graph, (_root.rhs.single as Named).name));
    }
    final start = _graph.start;
    _add(_State(_root, 0, start, start, Bindings.empty, const {}, -1, 0));
    final limit = _options.limits.agenda;
    for (final vertex in _graph.nodes) {
      if (_options.cancel?.call() ?? false) {
        _stop = cancelled;
        return _result(Outcome.cancelled);
      }
      final chart = _charts[vertex.id];
      while (chart.agenda.isNotEmpty && _stop == null) {
        final state = chart.agenda.removeFirst();
        if (state.superseded) {
          continue;
        }
        _processed++;
        if (_halted()) {
          break;
        }
        if (limit > 0 && _processed > limit) {
          _stop = Stop(
            Stop.agenda,
            _processed,
            limit,
            'processed $_processed agenda entries, more than the limit of '
            '$limit',
          );
          break;
        }
        _process(state, vertex);
      }
      if (_stop != null) {
        return _result(_stopped);
      }
      if (_watched) {
        _observer.observe(Finished(vertex.id, chart.states.length));
        for (final edge in _graph.edgesOf(vertex)) {
          if (edge.category == Edge.error) {
            _observer.observe(
              Unexpected(vertex.id, edge.text, {
                for (final state in chart.states.values)
                  if (!state.complete) _Collector._element(state.next),
              }),
            );
          }
        }
      }
    }
    return _select();
  }

  /// The outcome for [_stop]: a cancellation, or else a limit.
  Outcome get _stopped =>
      _stop!.resource == Stop.interrupt ? Outcome.cancelled : Outcome.limit;

  /// Checks cancellation and the deadline every 1,024 calls, setting
  /// [_stop]; true when the parse must end.
  bool _halted() {
    if ((++_checks & 1023) != 0) {
      return false;
    }
    if (_options.cancel?.call() ?? false) {
      _stop = cancelled;
      return true;
    }
    final deadline = _options.limits.deadline;
    if (deadline > Duration.zero && _clock.elapsed > deadline) {
      final elapsed = _clock.elapsedMilliseconds;
      _stop = Stop(
        Stop.deadline,
        elapsed,
        deadline.inMilliseconds,
        'ran $elapsed ms, longer than the deadline of '
        '${deadline.inMilliseconds} ms',
      );
      return true;
    }
    return false;
  }

  /// Counts a created or replacing state; false, with [_stop] set, past the
  /// state limit.
  bool _created() {
    _states++;
    final limit = _options.limits.states;
    if (limit > 0 && _states > limit) {
      _stop = Stop(
        Stop.states,
        _states,
        limit,
        'created $_states chart states, more than the limit of $limit',
      );
      return false;
    }
    return true;
  }

  /// Counts [count] recorded links; false, with [_stop] set, past the link
  /// limit.
  bool _link(int count) {
    _linked += count;
    final limit = _options.limits.links;
    if (limit > 0 && _linked > limit) {
      _stop = Stop(
        Stop.links,
        _linked,
        limit,
        'recorded $_linked packed derivations, more than the limit of $limit',
      );
      return false;
    }
    return true;
  }

  /// Counts a tree node; false, with [_stop] set, past the tree limit.
  bool _grow() {
    _built++;
    final limit = _options.limits.tree;
    if (limit > 0 && _built > limit) {
      _stop = Stop(
        Stop.tree,
        _built,
        limit,
        'the selected tree has more than $limit nodes',
      );
      return false;
    }
    return true;
  }

  ParseResult _result(
    Outcome outcome, {
    ParseTree? tree,
    int penalty = 0,
    bool ambiguous = false,
    bool tied = false,
  }) {
    final result = ParseResult(
      outcome,
      tree: tree,
      penalty: penalty,
      ambiguous: ambiguous,
      tied: tied,
      stop: _stop,
      diagnostics: _collector?.diagnostics,
      statistics: Statistics(
        nodes: _graph.nodes.length,
        edges: _graph.edges.length,
        states: _states,
        agenda: _processed,
        completions: _completions,
        unifications: _unifications,
        evaluations: _evaluations,
        calls: _memo.calls,
        hits: _memo.hits,
        elapsed: _clock.elapsed,
      ),
    );
    if (_watched) {
      _observer.observe(Ended(result, _clock.elapsed));
    }
    return result;
  }

  void _process(_State state, Vertex vertex) {
    if (state.complete) {
      _complete(state, vertex);
      return;
    }
    final chart = _charts[vertex.id];
    switch (state.next) {
      case Named(:final name):
        (chart.waiting[name] ??= []).add(state);
        _predict(name, vertex);
        // Constituents of the symbol that start and end here (nullable)
        // arrived first.
        final empty = chart.completed[name]?[vertex.id] ?? const [];
        for (final constituent in [...empty]) {
          if (!constituent.superseded) {
            _advance(state, constituent, vertex);
          }
        }
        _scan(state, vertex);
      case Anonymous() || Any():
        _scan(state, vertex);
    }
  }

  void _predict(String symbol, Vertex vertex) {
    if (!_charts[vertex.id].predicted.add(symbol)) {
      return;
    }
    for (final production in _compiled.productionsFor(symbol)) {
      if (_watched) {
        _observer.observe(Predicted(vertex.id, symbol, production.id));
      }
      _add(
        _State(production, 0, vertex, vertex, Bindings.empty, const {}, -1, 0),
      );
    }
  }

  void _scan(_State state, Vertex vertex) {
    final element = state.next;
    for (final edge in _graph.edgesOf(vertex)) {
      if (matches(element, edge)) {
        if (_watched) {
          _observer.observe(Scanned(vertex.id, edge.category, edge.text));
        }
        _advance(state, _Token(edge), edge.to);
      }
    }
  }

  void _complete(_State constituent, Vertex vertex) {
    if (_watched && !identical(constituent.production, _root)) {
      _observer.observe(
        Completed(
          constituent.origin.id,
          vertex.id,
          constituent.symbol,
          constituent.production.id,
          constituent.penalty,
        ),
      );
    }
    final chart = _charts[vertex.id];
    ((chart.completed[constituent.symbol] ??= {})[constituent.origin.id] ??= [])
        .add(constituent);
    final waiting =
        _charts[constituent.origin.id].waiting[constituent.symbol] ?? const [];
    for (final state in [...waiting]) {
      if (!state.superseded) {
        _advance(state, constituent, vertex);
      }
    }
  }

  /// Advances [state] over [child] to [target].
  void _advance(_State state, _Child child, Vertex target) {
    if (_stop != null) {
      return;
    }
    _completions++;
    final element = state.next;
    final (Structure features, int cost, int from) = switch (child) {
      final _State constituent => (
        constituent.features,
        constituent.penalty,
        constituent.start,
      ),
      _Token(:final edge) => (_features(edge), edge.cost, edge.start),
    };

    // S-F5: the features written on the element unify with the child's,
    // under this use's bindings.
    var bindings = state.bindings;
    final written = switch (element) {
      Named(:final features) || Any(:final features) => features,
      Anonymous() => Structure.empty,
    };
    if (written.isNotEmpty) {
      _unifications++;
      final unified = Unifier.structures(written, features, bindings);
      if (_watched) {
        _observer.observe(
          Unified(
            target.id,
            state.production.features,
            features,
            written,
            switch (unified) {
              Success(:final value) => value.value,
              Failure() => null,
            },
            switch (unified) {
              Success(:final value) => value.bindings.values,
              Failure() => const {},
            },
          ),
        );
      }
      switch (unified) {
        case Success(:final value):
          bindings = value.bindings;
        case Failure(:final error):
          _collector?.unification(
            _Collector._element(element),
            state.production.features,
            features,
            written,
            error.message,
            target,
            from,
          );
          return;
      }
    }

    var labels = state.labels;
    if (element.label case final label?
        when _referenced[state.production.id]?.contains(label) ?? false) {
      labels = {...labels, label: Binding.of(_text(child), features)};
    }

    final penalty = sum(state.penalty, cost);
    if (penalty == null) {
      _stop = overflow;
      return;
    }
    final next = _State(
      state.production,
      state.dot + 1,
      state.origin,
      target,
      bindings,
      labels,
      state.start >= 0 ? state.start : from,
      penalty,
    );
    next.links.add((previous: state, child: child));
    _add(next);
  }

  /// A token's features, with any variables renamed apart per edge (S-F5).
  Structure _features(Edge edge) => _renamedEdges.putIfAbsent(
    edge,
    () => _rename(edge.features, "'e${edge.id}"),
  );

  /// [structure] with [suffix] appended to the name of every variable.
  static Structure _rename(Structure structure, String suffix) => Values.rename(
    structure,
    (variable) => Variable('${variable.name}$suffix'),
  ) as Structure;

  /// A constituent's text: the input from its first token's start to its
  /// last token's end (S-C9).
  /// Without the input, a constituent's text is its token texts joined by
  /// single spaces.
  String _text(_Child child) {
    final input = _input;
    return switch (child) {
      _Token(:final edge) =>
        input != null ? input.substring(edge.start, edge.end) : edge.text,
      final _State state when state.start < 0 => '',
      final _State state when input != null => input.substring(
        state.start,
        state.end.offset,
      ),
      final _State state => _leaves(state).join(' '),
    };
  }

  /// The token texts along [state]'s first derivation.
  static List<String> _leaves(_State state) {
    final tokens = <String>[];
    final visited = Set<_State>.identity();
    final stack = <_Child>[state];
    while (stack.isNotEmpty) {
      switch (stack.removeLast()) {
        case _Token(:final edge):
          tokens.add(edge.text);
        case final _State current:
          if (!visited.add(current)) {
            continue;
          }
          // Children are pushed last to first, so they are visited in order.
          for (
            var step = current;
            step.links.isNotEmpty;
            step = step.links.first.previous
          ) {
            stack.add(step.links.first.child);
          }
      }
    }
    return tokens;
  }

  /// Adds [state] to its end vertex's chart, keeping only the cheapest of
  /// equivalent states.
  void _add(_State state) {
    final chart = _charts[state.end.id];
    final key = state.key(_canonical);
    final existing = chart.states[key];
    if (state.complete) {
      if (existing != null) {
        // Same key, same span: same features and the same constraint
        // verdict (PAR-3).
        state.features = existing.features;
        state.own = existing.own;
      } else if (!_finish(state)) {
        return;
      }
      final penalty = sum(state.penalty, state.own);
      if (penalty == null) {
        _stop = overflow;
        return;
      }
      state.penalty = penalty;
    }
    if (existing == null) {
      if (!_created() || !_link(state.links.length)) {
        return;
      }
      chart.states[key] = state;
      chart.agenda.add(state);
    } else if (state.penalty < existing.penalty) {
      if (!_created() || !_link(state.links.length)) {
        return;
      }
      existing.superseded = true;
      chart.states[key] = state;
      chart.agenda.add(state);
    } else if (state.penalty == existing.penalty) {
      for (final link in state.links) {
        if (!existing.links.any(
          (other) =>
              identical(other.previous, link.previous) &&
              _same(other.child, link.child),
        )) {
          if (!_link(1)) {
            return;
          }
          existing.links.add(link);
        }
      }
    }
  }

  /// Sets a newly complete state's features and own penalty, and evaluates
  /// its constraints; false if a required expression is false (S-C3) or a
  /// penalty overflowed.
  ///
  /// The constituent's features are its left-hand features under the
  /// bindings, with the remaining variables renamed apart from every other
  /// constituent's (S-F5).
  bool _finish(_State state) {
    final production = state.production;
    state.features = _rename(
      Unifier.substitute(production.features, state.bindings) as Structure,
      "'${_fresh++}",
    );
    var own = production.cost;
    if (!production.plan.isEmpty) {
      _evaluations++;
      // Later entries replace earlier ones.
      final values = <String, Value>{
        for (final MapEntry(key: name, :value) in state.bindings.values.entries)
          name: Unifier.substitute(value, state.bindings),
        ...state.labels,
        Environment.origin: _position(state.origin),
        Environment.end: BooleanConstant.of(_graph.isFinal(state.end)),
        Environment.next: _next(state.end),
        production.symbol: Binding.of(_text(state), state.features),
      };
      // S-C7: lexical predicates see the start vertex's state stack and the
      // first token's start, after skipped text; an empty constituent's
      // vertex offset.
      final environment = Environment.of(_compiled.predicates)
          .lexical(
            state.origin.states,
            state.start < 0 ? state.origin.offset : state.start,
          )
          .merge(values);
      final verdict = Evaluator.evaluate(
        production.plan,
        (call) => _memo.test(environment, call),
      );
      if (_watched) {
        _observer.observe(
          Evaluated(
            state.end.id,
            production.symbol,
            _Collector.plan(production.plan),
            verdict is Accepted,
            switch (verdict) {
              Accepted(:final penalty) => penalty,
              _ => 0,
            },
          ),
        );
      }
      switch (verdict) {
        case Rejected(:final failed):
          _collector?.constraint(state, failed);
          return false;
        case Overflow():
          _stop = overflow;
          return false;
        case Accepted(:final penalty):
          final total = sum(own, penalty);
          if (total == null) {
            _stop = overflow;
            return false;
          }
          own = total;
      }
    }
    state.own = own;
    return true;
  }

  /// The token indexes at which [vertex] is reached, one feature each
  /// (S-C7): the number of tokens on every path from the start. Computed for
  /// the whole graph on first use; vertex ids are a topological order, so
  /// every predecessor is visited first.
  Structure _position(Vertex vertex) {
    final positions = _positions ??= () {
      final indexes = [for (final _ in _graph.nodes) <int>{}];
      indexes[_graph.start.id].add(0);
      for (final from in _graph.nodes) {
        for (final edge in _graph.edgesOf(from)) {
          for (final index in indexes[from.id]) {
            indexes[edge.to.id].add(index + 1);
          }
        }
      }
      return [
        for (final set in indexes)
          Structure.of({
            for (final index in set.toList()..sort())
              '$index': BooleanConstant.trueValue,
          }),
      ];
    }();
    return positions[vertex.id];
  }

  /// The categories of the tokens leaving [vertex], one feature each; a
  /// token with no category adds none (S-L6).
  Structure _next(Vertex vertex) => _following.putIfAbsent(
    vertex.id,
    () => Structure.of({
      for (final edge in _graph.edgesOf(vertex))
        ?edge.category: BooleanConstant.trueValue,
    }),
  );

  ParseResult _select() {
    final roots = <_State>[];
    for (final vertex in _graph.nodes) {
      if (_graph.isFinal(vertex)) {
        for (final state in _charts[vertex.id].states.values) {
          if (identical(state.production, _root) &&
              state.complete &&
              !state.superseded) {
            roots.add(state);
          }
        }
      }
    }
    if (roots.isEmpty) {
      _collector?.rejected();
      return _result(Outcome.rejected);
    }
    final penalty = roots
        .map((state) => state.penalty)
        .reduce((a, b) => a < b ? a : b);
    final tied = [
      for (final state in roots)
        if (state.penalty == penalty) state,
    ];
    final selector = _Selector(_graph, _halted, _grow);
    try {
      final chosen = selector.choose(tied);
      final ambiguous = tied.length > 1 || selector.ambiguous(chosen);
      final tree = selector.tree(chosen);
      if (_collector case final collector? when ambiguous) {
        if (tied.length > 1) {
          collector.ambiguity(_compiled.start, Span(0, tree.start, tree.end));
        }
        selector.ties(chosen, _root, collector.ambiguity);
      }
      return _result(
        Outcome.accepted,
        tree: tree,
        penalty: penalty,
        ambiguous: ambiguous,
        tied: selector.tied,
      );
    } on _Exhausted {
      return _result(_stopped);
    }
  }
}

/// The chart for one vertex.
final class _Chart {
  final states = <_Key, _State>{};
  final waiting = <String, List<_State>>{};
  final completed = <String, Map<int, List<_State>>>{};
  final agenda = Queue<_State>();
  final predicted = <String>{};
}
