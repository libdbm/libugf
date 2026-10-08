part of 'session.dart';

/// A candidate derivation of a state: its last link, the derivations it
/// extends (of the link's previous state, and of its child constituent, if
/// any), and the keys that order derivations (S-P3).
final class _Best {
  const _Best(
    this.link,
    this.previous,
    this.inner,
    this.productions,
    this.ends,
    this.classes,
    this.tokens,
    this.tied,
  );

  static const empty = _Best(
    null,
    null,
    null,
    Sequence.empty,
    Sequence.empty,
    Sequence.empty,
    Sequence.empty,
    false,
  );

  final _Link? link;
  final _Best? previous;
  final _Best? inner;
  final Sequence productions;
  final Sequence ends;
  final Sequence classes;
  final Sequence tokens;

  /// Whether only the last S-P3 rule chose this derivation or one inside it.
  final bool tied;

  /// This derivation, marked as chosen by the last S-P3 rule.
  _Best tie() =>
      _Best(link, previous, inner, productions, ends, classes, tokens, true);
}

/// Chooses among the packed derivations of a finished chart and builds the
/// selected tree (S-P3, S-P4, S-P8), as Java's `ForestSelector` at
/// `8d8c01a`. Every traversal uses an explicit stack, so deep derivations
/// cannot exhaust the stack.
final class _Selector {
  _Selector(this._graph, this._halted, this._grow);

  final Graph _graph;

  /// True when the parse must stop; checked as selection and tree building
  /// proceed.
  final bool Function() _halted;

  /// Counts one tree node; false past the tree limit.
  final bool Function() _grow;

  /// The candidate derivations of each state resolved so far: those no
  /// other derivation of the state precedes whatever follows it (S-P3).
  /// They differ only where one key is a proper prefix of another, so what
  /// follows decides between them.
  final _memo = Map<_State, List<_Best>>.identity();

  /// States whose candidates are being resolved, to skip cyclic
  /// derivations.
  final _active = Set<_State>.identity();

  /// Each token's place in the full S-P3 token order, computed on first use.
  Map<Edge, int>? _ranks;

  /// Each token's place in the S-P3 order without its last rule.
  Map<Edge, int>? _classes;

  /// Whether only the last S-P3 rule chose among the root candidates.
  var _split = false;

  /// The chosen root derivation.
  _Best? _selected;

  static const _equal = 0;
  static const _open = 1 << 30;

  /// The full S-P3 order, ending with declaration or caller order.
  static int _compare(_Best a, _Best b) {
    final result = _coarse(a, b);
    return result != 0 ? result : a.tokens.compareTo(b.tokens);
  }

  /// Pre-order productions first, then constituent ends, then token
  /// categories and state stacks (S-P3), but not the last rule.
  static int _coarse(_Best a, _Best b) {
    var result = a.productions.compareTo(b.productions);
    if (result == 0) {
      result = a.ends.compareTo(b.ends);
    }
    return result != 0 ? result : a.classes.compareTo(b.classes);
  }

  /// The S-P3 token order without its last rule: category, with none
  /// first, then the state stack the token leads to, compared from the
  /// bottom. Strings compare by code point.
  static int _order(Edge a, Edge b) {
    if (a.category != b.category) {
      if (a.category == null || b.category == null) {
        return a.category == null ? -1 : 1;
      }
      return _text(a.category!, b.category!);
    }
    final mine = a.to.states;
    final theirs = b.to.states;
    for (var index = 0; index < min(mine.length, theirs.length); index++) {
      final result = _text(mine[index], theirs[index]);
      if (result != 0) {
        return result;
      }
    }
    return mine.length.compareTo(theirs.length);
  }

  /// Code point order (not UTF-16 unit order); a proper prefix comes first.
  static int _text(String a, String b) {
    final mine = a.runes.iterator;
    final theirs = b.runes.iterator;
    while (true) {
      final more = mine.moveNext();
      final others = theirs.moveNext();
      if (!more || !others) {
        return more == others ? 0 : (more ? 1 : -1);
      }
      if (mine.current != theirs.current) {
        return mine.current.compareTo(theirs.current);
      }
    }
  }

  /// Ranks every token in the S-P3 order. The last rule prefers the earlier
  /// of tokens leaving the same vertex, which the lexer emits in declaration
  /// order and caller sources in the caller's order.
  void _rank() {
    final positions = Map<Edge, int>.identity();
    for (final vertex in _graph.nodes) {
      final outgoing = _graph.edgesOf(vertex);
      for (var index = 0; index < outgoing.length; index++) {
        positions[outgoing[index]] = index;
      }
    }
    int full(Edge a, Edge b) {
      final result = _order(a, b);
      return result != 0 ? result : positions[a]!.compareTo(positions[b]!);
    }

    final edges = _graph.edges..sort(full);
    final ranks = _ranks = Map<Edge, int>.identity();
    final classes = _classes = Map<Edge, int>.identity();
    var rank = -1;
    var klass = -1;
    Edge? last;
    for (final current in edges) {
      if (last == null || full(last, current) != 0) {
        rank++;
      }
      if (last == null || _order(last, current) != 0) {
        klass++;
      }
      ranks[current] = rank;
      classes[current] = klass;
      last = current;
    }
  }

  /// Whether only the last S-P3 rule chose the selected derivation among
  /// the root candidates, or chose a derivation inside it.
  bool get tied => _split || _selected!.tied;

  /// How [a] and [b] are ordered whatever follows them: negative or
  /// positive if one precedes the other for every continuation, [_equal] if
  /// their keys are equal, and [_open] if a continuation decides. The second
  /// value is true when only the last S-P3 rule decides.
  static (int, bool) _dominance(_Best a, _Best b) {
    final mine = [a.productions, a.ends, a.classes, a.tokens];
    final theirs = [b.productions, b.ends, b.classes, b.tokens];
    for (var index = 0; index < mine.length; index++) {
      final result = mine[index].differ(theirs[index]);
      if (result != 0) {
        return (result, index == mine.length - 1);
      }
      if (mine[index].size != theirs[index].size) {
        return (_open, false);
      }
    }
    return (_equal, false);
  }

  /// Adds [candidate] to [pool], keeping only derivations no other one
  /// precedes.
  static void _offer(List<_Best> pool, _Best candidate) {
    var current = candidate;
    for (var index = 0; index < pool.length; index++) {
      final (result, last) = _dominance(current, pool[index]);
      if (result == _equal) {
        return;
      }
      if (result == _open) {
        continue;
      }
      if (result > 0) {
        // Only declaration or caller order put the existing derivation
        // first.
        if (last) {
          pool[index] = pool[index].tie();
        }
        return;
      }
      pool.removeAt(index--);
      if (last) {
        current = current.tie();
      }
    }
    pool.add(current);
  }

  /// Chooses the derivation that comes first among the candidates of the
  /// [tied] roots (S-P3). Nothing follows a root, so a proper prefix comes
  /// first. Returns its root.
  _State choose(List<_State> tied) {
    _State? chosen;
    final all = <_Best>[];
    for (final root in tied) {
      for (final candidate in _candidates(root)) {
        all.add(candidate);
        if (_selected == null || _compare(candidate, _selected!) < 0) {
          _selected = candidate;
          chosen = root;
        }
      }
    }
    for (final other in all) {
      if (_coarse(other, _selected!) == 0 && _compare(other, _selected!) != 0) {
        _split = true;
      }
    }
    return chosen!;
  }

  /// The candidate derivations of [state]. Nullable recursion makes the
  /// packed derivations cyclic; a link that leads back into a state still
  /// being resolved is skipped, which is safe because a cyclic derivation
  /// is never cheaper (S-P9).
  List<_Best> _candidates(_State state) {
    if (_memo[state] case final known?) {
      return known;
    }
    final stack = [_Selection(state)];
    _active.add(state);
    while (stack.isNotEmpty) {
      if (_halted()) {
        throw const _Exhausted();
      }
      final frame = stack.last;
      if (frame.index == frame.state.links.length) {
        stack.removeLast();
        _active.remove(frame.state);
        _memo[frame.state] = frame.pool.isEmpty
            ? const [_Best.empty]
            : frame.pool;
        continue;
      }
      final link = frame.state.links[frame.index];
      final child = link.child;
      if (_active.contains(link.previous) ||
          child is _State && _active.contains(child)) {
        frame.index++;
        continue;
      }
      final previous = _memo[link.previous];
      if (previous == null) {
        _active.add(link.previous);
        stack.add(_Selection(link.previous));
        continue;
      }
      switch (child) {
        case final _State constituent:
          final inner = _memo[constituent];
          if (inner == null) {
            _active.add(constituent);
            stack.add(_Selection(constituent));
            continue;
          }
          for (final before in previous) {
            var productions = before.productions;
            var ends = before.ends;
            if (!constituent.production.auxiliary) {
              productions = productions.then(
                Sequence.of(constituent.production.id),
              );
              ends = ends.then(Sequence.of(constituent.end.offset));
            }
            for (final after in inner) {
              _offer(
                frame.pool,
                _Best(
                  link,
                  before,
                  after,
                  productions.then(after.productions),
                  ends.then(after.ends),
                  before.classes.then(after.classes),
                  before.tokens.then(after.tokens),
                  before.tied || after.tied,
                ),
              );
            }
          }
        case _Token(:final edge):
          if (_ranks == null) {
            _rank();
          }
          for (final before in previous) {
            _offer(
              frame.pool,
              _Best(
                link,
                before,
                null,
                before.productions,
                before.ends.then(Sequence.of(edge.end)),
                before.classes.then(Sequence.of(_classes![edge]!)),
                before.tokens.then(Sequence.of(_ranks![edge]!)),
                before.tied,
              ),
            );
          }
      }
      frame.index++;
    }
    return _memo[state]!;
  }

  /// Whether any state on the chosen derivation of [state] has more than
  /// one equally cheap derivation (S-P4).
  bool ambiguous(_State state) {
    final stack = [(state, _selected!)];
    while (stack.isNotEmpty) {
      final (current, best) = stack.removeLast();
      if (current.links.length > 1) {
        return true;
      }
      if (best.link case final link?) {
        stack.add((link.previous, best.previous!));
        if (link.child case final _State constituent) {
          stack.add((constituent, best.inner!));
        }
      }
    }
    return false;
  }

  /// Reports each constituent on the chosen derivation of [chosen] that has
  /// more than one equally cheap derivation, once per symbol and span; a tie
  /// inside an auxiliary node is attributed to the nearest real symbol above
  /// it.
  void ties(
    _State chosen,
    Production root,
    void Function(String, Span) report,
  ) {
    final stack = [(chosen, _selected!, chosen)];
    final seen = <String>{};
    while (stack.isNotEmpty) {
      final (state, best, above) = stack.removeLast();
      final owner = state.production.auxiliary ? above : state;
      if (state.links.length > 1 &&
          state.complete &&
          !identical(owner.production, root)) {
        final start = owner.start >= 0 ? owner.start : owner.origin.offset;
        if (seen.add('${owner.symbol}@$start:${owner.end.offset}')) {
          report(owner.symbol, Span(owner.origin.id, start, owner.end.offset));
        }
      }
      if (best.link case final link?) {
        stack.add((link.previous, best.previous!, above));
        if (link.child case final _State constituent) {
          stack.add((constituent, best.inner!, owner));
        }
      }
    }
  }

  /// The tree of the selected derivation of [chosen], whose production is
  /// the auxiliary root: its one child, the start symbol's tree.
  ParseTree tree(_State chosen) => _build(chosen, _selected!, null).first;

  /// The trees for [state]: one node, or its children spliced if it is
  /// auxiliary (S-P8).
  List<ParseTree> _build(_State state, _Best best, String? label) {
    final stack = [_Construction(state, label, _path(best))];
    List<ParseTree>? finished;
    while (true) {
      final frame = stack.last;
      if (finished != null) {
        frame.children.addAll(finished);
        finished = null;
      }
      if (frame.index == frame.path.length) {
        stack.removeLast();
        finished = frame.finish();
        if (stack.isEmpty) {
          return finished;
        }
        continue;
      }
      if (_halted() || !_grow()) {
        throw const _Exhausted();
      }
      final element = frame.state.production.rhs[frame.index];
      final step = frame.path[frame.index++];
      switch (step.link!.child) {
        case final _State constituent:
          stack.add(
            _Construction(constituent, element.label, _path(step.inner!)),
          );
        case _Token(:final edge):
          frame.children.add(_token(edge, element));
      }
    }
  }

  /// The steps of a derivation, one per right-hand-side element, in order.
  static List<_Best> _path(_Best best) {
    final path = <_Best>[];
    for (
      _Best? current = best;
      current != null && current.link != null;
      current = current.previous
    ) {
      path.add(current);
    }
    return path.reversed.toList();
  }

  /// A named lexical token is a node with one leaf; an anonymous or caller
  /// token is a leaf (S-P8).
  static ParseTree _token(Edge edge, Element element) => switch (element) {
    Named(:final label) => Node(
      edge.category!,
      [Leaf(edge.text, edge.start, edge.end)],
      label: label,
      features: edge.features,
      start: edge.start,
      end: edge.end,
    ),
    _ => Leaf(edge.text, edge.start, edge.end, edge.features),
  };
}

/// Ends selection or tree building when the budget is spent; the session
/// catches it and reports its [Session._stop].
final class _Exhausted {
  const _Exhausted();
}

/// A state whose candidates are being collected: the next link and the
/// candidates so far.
final class _Selection {
  _Selection(this.state);

  final _State state;
  var index = 0;
  final pool = <_Best>[];
}

/// A state whose tree is being built: its chosen steps and the children
/// built so far.
final class _Construction {
  _Construction(this.state, this.label, this.path);

  final _State state;
  final String? label;
  final List<_Best> path;
  final children = <ParseTree>[];
  var index = 0;

  List<ParseTree> finish() {
    if (state.production.auxiliary) {
      return children;
    }
    // An empty constituent is positioned at its origin.
    final start = state.start >= 0 ? state.start : state.origin.offset;
    return [
      Node(
        state.symbol,
        children,
        label: label,
        features: state.features,
        start: start,
        end: state.start >= 0 ? state.end.offset : start,
      ),
    ];
  }
}
