/// The tree of a successful parse.
library;

import '../features/value.dart';

/// A parse tree: an interior [Node] or a [Leaf] (S-P8). [display] and
/// [text] are iterative, so deep trees cannot exhaust the stack.
sealed class ParseTree {
  const ParseTree();

  /// The offset where the tree starts in the input.
  int get start;

  /// The offset where the tree ends in the input.
  int get end;

  /// The texts of this tree's leaves, concatenated.
  String get text {
    final buffer = StringBuffer();
    final stack = <ParseTree>[this];
    while (stack.isNotEmpty) {
      switch (stack.removeLast()) {
        case Leaf(text: final leaf):
          buffer.write(leaf);
        case Node(:final children):
          stack.addAll(children.reversed);
      }
    }
    return buffer.toString();
  }

  /// The tree in a readable form: one line per node, indented by depth.
  String display() {
    final buffer = StringBuffer();
    final stack = <(ParseTree, int)>[(this, 0)];
    while (stack.isNotEmpty) {
      final (tree, depth) = stack.removeLast();
      buffer.write('  ' * depth);
      switch (tree) {
        case Node(
          :final symbol,
          :final label,
          :final features,
          :final children,
        ):
          buffer.write(symbol);
          if (label != null) {
            buffer.write(':$label');
          }
          if (features.isNotEmpty) {
            buffer.write(' ${features.display()}');
          }
          buffer.writeln();
          for (final child in children.reversed) {
            stack.add((child, depth + 1));
          }
        case Leaf(:final text, :final features, :final start, :final end):
          buffer.write("'$text'");
          if (features.isNotEmpty) {
            buffer.write(' ${features.display()}');
          }
          buffer.writeln(' [$start,$end]');
      }
    }
    return buffer.toString();
  }
}

/// An interior node. [start] and [end] are explicit, so an empty
/// constituent reports its real position.
final class Node extends ParseTree {
  /// A node; [children] is copied.
  Node(
    this.symbol,
    List<ParseTree> children, {
    this.label,
    Structure? features,
    required this.start,
    required this.end,
  }) : children = List.unmodifiable(children),
       features = features ?? Structure.empty;

  /// The symbol of the production.
  final String symbol;

  /// The label written on the element, or null.
  final String? label;

  /// The children, in input order.
  final List<ParseTree> children;

  /// The constituent's features.
  final Structure features;

  @override
  final int start;

  @override
  final int end;

  @override
  bool operator ==(Object other) =>
      other is Node &&
      symbol == other.symbol &&
      label == other.label &&
      features == other.features &&
      start == other.start &&
      end == other.end &&
      _same(children, other.children);

  @override
  int get hashCode => Object.hash(
    symbol,
    label,
    features,
    start,
    end,
    Object.hashAll(children),
  );
}

/// A token: an anonymous or caller token, or the text under a named lexical
/// category's node (S-P8).
final class Leaf extends ParseTree {
  /// A leaf of [text] from [start] to [end].
  Leaf(this.text, this.start, this.end, [Structure? features])
    : features = features ?? Structure.empty;

  @override
  final String text;

  @override
  final int start;

  @override
  final int end;

  /// The token's features.
  final Structure features;

  @override
  bool operator ==(Object other) =>
      other is Leaf &&
      text == other.text &&
      start == other.start &&
      end == other.end &&
      features == other.features;

  @override
  int get hashCode => Object.hash(text, start, end, features);
}

bool _same(List<ParseTree> left, List<ParseTree> right) {
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
