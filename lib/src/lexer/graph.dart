/// The token graph (S-L1).
library;

import '../features/value.dart';

/// A token graph node: a character offset and the lexical state stack in
/// force there (S-L1).
final class Vertex {
  /// A node; [states], bottom to top, is copied and never empty.
  Vertex(this.id, this.offset, List<String> states)
    : states = List.unmodifiable(states) {
    if (states.isEmpty) {
      throw ArgumentError.value(states, 'states', 'is never empty');
    }
  }

  /// The position in the graph's node list, which is a topological order.
  final int id;

  /// The character offset.
  final int offset;

  /// The state stack, bottom to top; never empty.
  final List<String> states;

  @override
  bool operator ==(Object other) =>
      other is Vertex &&
      id == other.id &&
      offset == other.offset &&
      _same(states, other.states);

  @override
  int get hashCode => Object.hash(id, offset, Object.hashAll(states));

  @override
  String toString() => 'Vertex($id, $offset, $states)';
}

bool _same(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

/// A token graph edge: one token from [from] to [to] (S-L1).
final class Edge {
  /// An edge. The id and cost are never negative, and the token starts
  /// between its two nodes.
  Edge({
    required this.id,
    required this.from,
    required this.to,
    required this.start,
    required this.text,
    required this.category,
    required this.features,
    required this.cost,
  }) {
    if (id < 0 || cost < 0) {
      throw ArgumentError('edge id and cost must not be negative: $id, $cost');
    }
    if (start < from.offset || start > to.offset) {
      throw ArgumentError(
        'edge $id starts at $start, outside ${from.offset}..${to.offset}',
      );
    }
  }

  /// The category of an edge for a character no lexeme matches (S-L5).
  static const error = 'error';

  /// The position in the graph's edge order.
  final int id;

  /// The source node.
  final Vertex from;

  /// The target node; its offset is the token's end and its state stack
  /// reflects the token's transition.
  final Vertex to;

  /// The character offset where the token starts, after any skipped text.
  final int start;

  /// The token text.
  final String text;

  /// The token category: a named lexeme's symbol, an anonymous lexeme's
  /// source text, [error] for an unmatched character (S-L5), a caller's
  /// category, or null for a caller token with none (S-L6).
  final String? category;

  /// The token's features.
  final Structure features;

  /// The lexeme cost plus the weights of false soft groups in the lexeme's
  /// constraints; never negative (S-L1).
  final int cost;

  /// The character offset where the token ends.
  int get end => to.offset;

  @override
  String toString() => 'Edge($id, ${from.id}->${to.id}, $category, "$text")';
}

/// A token graph (S-L1): a directed acyclic graph of tokens. [nodes] is a
/// topological order (by offset), the first node is the start, and every
/// path from the start to a final node is one tokenization of the input.
/// The constructor enforces these invariants, so a graph a caller builds
/// cannot break the parser.
final class Graph {
  /// A graph of [nodes], with [outgoing] edges by node id and the ids of the
  /// [finals]; all are copied. Throws an [ArgumentError] if a node's id is
  /// not its index, an edge does not leave the node whose list holds it or
  /// lead to a later node of this graph, two edges share an id, or a final
  /// id is not a node.
  Graph(List<Vertex> nodes, List<List<Edge>> outgoing, Set<int> finals)
    : nodes = List.unmodifiable(nodes),
      outgoing = List.unmodifiable([
        for (final edges in outgoing) List<Edge>.unmodifiable(edges),
      ]),
      finals = Set.unmodifiable(finals) {
    if (nodes.isEmpty || outgoing.length != nodes.length) {
      throw ArgumentError(
        'a graph needs a start node and one edge list per node',
      );
    }
    _validate();
  }

  /// Every node, in topological order; a node's id is its index.
  final List<Vertex> nodes;

  /// The outgoing edges by node id.
  final List<List<Edge>> outgoing;

  /// The ids of the nodes at the end of the input.
  final Set<int> finals;

  void _validate() {
    for (var index = 0; index < nodes.length; index++) {
      if (nodes[index].id != index) {
        throw ArgumentError('node ${nodes[index].id} is at index $index');
      }
    }
    final ids = <int>{};
    for (var index = 0; index < nodes.length; index++) {
      for (final edge in outgoing[index]) {
        final to = edge.to.id;
        if (edge.from != nodes[index]) {
          throw ArgumentError('edge ${edge.id} does not leave node $index');
        }
        if (to <= index || to >= nodes.length || edge.to != nodes[to]) {
          throw ArgumentError(
            'edge ${edge.id} does not lead to a later node of the graph',
          );
        }
        if (!ids.add(edge.id)) {
          throw ArgumentError('edge id ${edge.id} is used twice');
        }
      }
    }
    for (final id in finals) {
      if (id < 0 || id >= nodes.length) {
        throw ArgumentError('final $id is not a node');
      }
    }
  }

  /// The start node.
  Vertex get start => nodes.first;

  /// The edges leaving [node].
  List<Edge> edgesOf(Vertex node) => outgoing[node.id];

  /// Whether [node] is at the end of the input.
  bool isFinal(Vertex node) => finals.contains(node.id);

  /// Every edge, in node order.
  List<Edge> get edges => [for (final edges in outgoing) ...edges];
}
