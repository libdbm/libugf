/// Builds the token graph for an input (S-L1 to S-L5).
library;

import 'dart:collection';

import '../arithmetic.dart';
import '../compiler/compiled.dart';
import '../constraints/evaluator.dart';
import '../constraints/predicates.dart';
import '../constraints/verdict.dart';
import '../features/value.dart';
import '../result.dart';
import 'graph.dart';
import 'token_source.dart';

/// Builds the token graph for an input from a [Compiled] grammar's lexemes
/// (S-L1 to S-L5).
///
/// Nodes are discovered in offset order. From each node, every lexeme
/// allowed in the node's state is tried at the next offset after skipped
/// text; matches that fail a required constraint are dropped, and of the
/// rest only those of maximal length become edges, in lexeme declaration
/// order (S-L2). Each edge's target node carries the state stack after the
/// lexeme's transition (S-L3). A lexeme's constraints refer only to its own
/// text and labelled parts, so they are evaluated in full here: false soft
/// groups become edge cost. If nothing matches, a one-code-point
/// [Edge.error] edge is added (S-L5).
///
/// Before each token, whitespace and matches of the grammar's `skip`
/// categories are discarded, repeatedly, until neither matches (S-L4). Skip
/// lexemes respect their states but never apply transitions and never
/// become edges.
final class Lexer implements TokenSource {
  /// A lexer for a compiled grammar. Literal lexemes are indexed by their first code
  /// unit; the rest are tried everywhere.
  Lexer(this._compiled) {
    for (final lexeme in _compiled.lexemes) {
      if (!lexeme.anonymous && _compiled.skips.contains(lexeme.category)) {
        _skips.add(lexeme);
      } else if (lexeme.literal case final literal? when literal.isNotEmpty) {
        (_literals[literal.codeUnitAt(0)] ??= []).add(lexeme);
      } else {
        _general.add(lexeme);
      }
    }
  }

  /// The penalty of a token's constraints overflowed (S-C10).
  static const overflow = 'limit.overflow';

  /// A lexical state stack would exceed the depth limit.
  static const depth = 'limit.depth';

  /// The token graph would exceed the vertex limit.
  static const nodes = 'limit.nodes';

  /// Lexing passed its deadline.
  static const deadline = 'limit.deadline';

  /// The caller cancelled lexing.
  static const interrupt = 'limit.interrupt';

  final Compiled _compiled;
  final _literals = <int, List<Lexeme>>{};
  final _general = <Lexeme>[];
  final _skips = <Lexeme>[];

  /// The token graph of [input], or an [overflow] failure. Within limits:
  /// at most [nodes] vertices and state stacks at most [depth] deep (zero
  /// means unlimited), finishing within [deadline] (zero means none), and
  /// stopping when [cancel] returns true, which is polled once per vertex.
  @override
  Result<Graph, ErrorDetails> tokenize(
    String input, {
    int nodes = 0,
    int depth = 0,
    Duration deadline = Duration.zero,
    bool Function()? cancel,
  }) {
    final clock = Stopwatch()..start();
    final frontier = SplayTreeMap<int, List<_Key>>();
    final discovered = <_Key>{};
    final pending = <_Pending>[];
    final finals = <_Key>[];

    void discover(_Key key) {
      if (discovered.add(key)) {
        (frontier[key.offset] ??= []).add(key);
      }
    }

    discover(_Key(0, const ['DEFAULT']));
    while (frontier.isNotEmpty) {
      final offset = frontier.firstKey()!;
      for (final key in frontier.remove(offset)!) {
        if (cancel != null && cancel()) {
          return Failure(
            ErrorDetails.of(Lexer.interrupt, 'lexing was cancelled'),
          );
        }
        if (deadline > Duration.zero && clock.elapsed > deadline) {
          return Failure(
            ErrorDetails.of(Lexer.deadline, 'lexing passed the deadline'),
          );
        }
        if (nodes > 0 && discovered.length > nodes) {
          return Failure(
            ErrorDetails.of(
              Lexer.nodes,
              'the token graph has more than $nodes nodes '
              '(lexical state branching?)',
            ),
          );
        }
        final position = _skip(input, key.offset, key.states);
        if (position == input.length) {
          finals.add(key);
          continue;
        }
        final matches = _matches(input, key, position);
        if (matches == null) {
          return Failure(
            ErrorDetails.of(
              overflow,
              'token penalty overflow at offset $position',
            ),
          );
        }
        if (matches.isEmpty) {
          final length = _width(input, position);
          final target = _Key(position + length, key.states);
          pending.add((
            from: key,
            to: target,
            start: position,
            text: input.substring(position, position + length),
            category: Edge.error,
            features: Structure.empty,
            cost: 0,
          ));
          discover(target);
          continue;
        }
        for (final match in matches) {
          final lexeme = match.lexeme;
          final target = _Key(
            position + match.length,
            _apply(key.states, lexeme.transition),
          );
          if (depth > 0 && target.states.length > depth) {
            return Failure(
              ErrorDetails.of(
                Lexer.depth,
                'a lexical state stack is deeper than $depth '
                'at offset ${target.offset}',
              ),
            );
          }
          pending.add((
            from: key,
            to: target,
            start: position,
            text: input.substring(position, position + match.length),
            category: lexeme.category,
            features: lexeme.features,
            cost: match.cost,
          ));
          discover(target);
        }
      }
    }
    return Success(_build(discovered, pending, finals));
  }

  /// The number of code units in the code point at [position].
  static int _width(String input, int position) {
    final unit = input.codeUnitAt(position);
    final lead = unit >= 0xD800 && unit <= 0xDBFF;
    if (lead && position + 1 < input.length) {
      final next = input.codeUnitAt(position + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        return 2;
      }
    }
    return 1;
  }

  /// The match of [pattern] starting at [position], seeing the whole input,
  /// so lookaround reads past the position and `^` and `$` mean the input's
  /// start and end.
  static RegExpMatch? _at(RegExp pattern, String input, int position) =>
      pattern.matchAsPrefix(input, position) as RegExpMatch?;

  /// The offset after any whitespace and skip-category matches at [offset]
  /// (S-L4).
  int _skip(String input, int offset, List<String> states) {
    final state = states.last;
    var position = offset;
    var moved = true;
    while (moved && position < input.length) {
      moved = false;
      if (_compiled.whitespace case final whitespace?) {
        final match = _at(whitespace, input, position);
        if (match != null && match.end > position) {
          position = match.end;
          moved = true;
        }
      }
      for (final lexeme in _skips) {
        if (position >= input.length ||
            lexeme.states.isNotEmpty && !lexeme.states.contains(state)) {
          continue;
        }
        final match = _at(lexeme.pattern, input, position);
        if (match != null &&
            match.end > position &&
            _allowed(lexeme, match, input, states, position)) {
          position = match.end;
          moved = true;
        }
      }
    }
    return position;
  }

  /// The accepted matches of maximal length at [position], in lexeme
  /// declaration order, or null if a token's penalty overflowed.
  List<_Match>? _matches(String input, _Key key, int position) {
    final state = key.states.last;
    final environment = Environment.of(_compiled.predicates)
        .lexical(key.states, position);
    final accepted = <_Match>[];
    var longest = 0;
    final candidates = [..._general, ...?_literals[input.codeUnitAt(position)]];
    for (final lexeme in candidates) {
      if (lexeme.states.isNotEmpty && !lexeme.states.contains(state)) {
        continue;
      }
      final match = _at(lexeme.pattern, input, position);
      if (match == null || match.end == position) {
        continue;
      }
      final length = match.end - position;
      if (length < longest) {
        continue;
      }
      final end =
          !lexeme.plan.isEmpty &&
          _skip(input, match.end, _apply(key.states, lexeme.transition)) ==
              input.length;
      final bound = _bind(
        environment,
        lexeme,
        match,
        input.substring(position, match.end),
        end,
      );
      final int cost;
      switch (Evaluator.evaluate(lexeme.plan, bound.test)) {
        case Rejected():
          continue;
        case Overflow():
          return null;
        case Accepted(:final penalty):
          final total = sum(penalty, lexeme.cost);
          if (total == null) {
            return null;
          }
          cost = total;
      }
      if (length > longest) {
        longest = length;
        accepted.clear();
      }
      accepted.add((lexeme: lexeme, length: length, cost: cost));
    }
    // Ids are unique, so this order has no ties.
    accepted.sort((a, b) => a.lexeme.id.compareTo(b.lexeme.id));
    return accepted;
  }

  /// Whether a skip lexeme's constraints accept this match (S-L4).
  bool _allowed(
    Lexeme lexeme,
    RegExpMatch match,
    String input,
    List<String> states,
    int position,
  ) {
    if (lexeme.plan.isEmpty) {
      return true;
    }
    final environment = Environment.of(_compiled.predicates)
        .lexical(states, position);
    // Skip categories apply no transitions (S-L4).
    final end = _skip(input, match.end, states) == input.length;
    final bound = _bind(
      environment,
      lexeme,
      match,
      input.substring(position, match.end),
      end,
    );
    return Evaluator.evaluate(lexeme.plan, bound.test) is Accepted;
  }

  /// Binds the lexeme's symbol to the whole token and each label to its
  /// part. Positional predicates read the token's start offset, and whether
  /// only skipped text follows it (S-C7).
  static Environment _bind(
    Environment environment,
    Lexeme lexeme,
    RegExpMatch match,
    String text,
    bool end,
  ) {
    if (lexeme.plan.isEmpty) {
      return environment;
    }
    final values = <String, Value>{
      lexeme.category: Binding.of(text, lexeme.features),
      Environment.origin: Structure.of({
        '${environment.position}': BooleanConstant.trueValue,
      }),
      Environment.end: BooleanConstant.of(end),
    };
    for (var index = 0; index < lexeme.labels.length; index++) {
      if (match.namedGroup(Lexeme.group(index)) case final part?) {
        values[lexeme.labels[index]] = Binding.of(part);
      }
    }
    return environment.merge(values);
  }

  /// Applies a transition: push `S`, pop `_` (never the bottom), reset
  /// `!S`, or replace the top with `^S`.
  static List<String> _apply(List<String> states, String? transition) {
    if (transition == null) {
      return states;
    }
    if (transition == '_') {
      return states.length > 1 ? states.sublist(0, states.length - 1) : states;
    }
    if (transition.startsWith('!')) {
      return [transition.substring(1)];
    }
    if (transition.startsWith('^')) {
      return [...states.sublist(0, states.length - 1), transition.substring(1)];
    }
    return [...states, transition];
  }

  /// Assigns node ids in offset order, a topological order since every edge
  /// moves forward, keeping discovery order between nodes at one offset.
  /// The edges leaving a node keep the order they were found in.
  static Graph _build(
    Set<_Key> keys,
    List<_Pending> pending,
    List<_Key> finals,
  ) {
    final sorted = _stable(keys.toList(), (key) => key.offset);
    final nodes = <_Key, Vertex>{};
    for (final key in sorted) {
      nodes[key] = Vertex(nodes.length, key.offset, key.states);
    }
    final outgoing = [for (final _ in sorted) <Edge>[]];
    final ordered = _stable(pending, (edge) => nodes[edge.from]!.id);
    var id = 0;
    for (final edge in ordered) {
      final from = nodes[edge.from]!;
      outgoing[from.id].add(
        Edge(
          id: id++,
          from: from,
          to: nodes[edge.to]!,
          start: edge.start,
          text: edge.text,
          category: edge.category,
          features: edge.features,
          cost: edge.cost,
        ),
      );
    }
    return Graph(nodes.values.toList(), outgoing, {
      for (final key in finals) nodes[key]!.id,
    });
  }
}

/// [items] sorted by [key], keeping their order between equal keys
/// ([List.sort] is not stable).
List<T> _stable<T>(List<T> items, int Function(T item) key) {
  final indices = [for (var index = 0; index < items.length; index++) index];
  indices.sort((a, b) {
    final order = key(items[a]).compareTo(key(items[b]));
    return order != 0 ? order : a.compareTo(b);
  });
  return [for (final index in indices) items[index]];
}

/// A node before ids are assigned: its offset and full state stack.
final class _Key {
  _Key(this.offset, this.states);

  final int offset;
  final List<String> states;

  @override
  bool operator ==(Object other) {
    if (other is! _Key ||
        offset != other.offset ||
        states.length != other.states.length) {
      return false;
    }
    for (var index = 0; index < states.length; index++) {
      if (states[index] != other.states[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(offset, Object.hashAll(states));
}

/// An edge before ids are assigned.
typedef _Pending = ({
  _Key from,
  _Key to,
  int start,
  String text,
  String category,
  Structure features,
  int cost,
});

/// An accepted match of [lexeme].
typedef _Match = ({Lexeme lexeme, int length, int cost});
