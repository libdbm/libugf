/// The canonical JSON encoding of parse trees and feature values, kept from
/// the 1.x conformance tooling for the 2.0 corpus runner (SPEC D12).
library;

import 'package:libugf/libugf.dart';

/// Encodes a parse tree node or leaf.
Map<String, Object?> tree(ParseTree node) => switch (node) {
  Node() => {
    'symbol': node.symbol,
    'label': node.label,
    'features': structure(node.features),
    'children': [for (final child in node.children) tree(child)],
  },
  Leaf() => {
    'text': node.text,
    'start': node.start,
    'end': node.end,
    'features': structure(node.features),
  },
};

/// Encodes a feature structure with sorted keys.
Map<String, Object?> structure(Structure features) {
  final keys = features.keys.toList()..sort();
  return {for (final key in keys) key: value(features[key]!)};
}

/// Encodes a value with a one-letter type tag.
Map<String, Object?> value(Value item) => switch (item) {
  StringConstant() => {'s': item.value},
  NumericConstant(floating: true) => {'f': item.value.toDouble()},
  NumericConstant() => {'i': item.value.toInt()},
  BooleanConstant() => {'b': item.value},
  Variable() => {'v': item.name},
  Structure() => {'m': structure(item)},
  Binding() => {
    'binding': {'text': item.text, 'features': structure(item.features)},
  },
  FeaturePath() => {'path': List<Object?>.of(item.parts)},
};
