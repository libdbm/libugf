/// Token graph enhancement before parsing.
library;

import '../lexer/graph.dart';

/// Transforms a token graph before parsing (LEX-8), for example to add
/// features or alternative categories from an external tagger.
abstract base class TokenEnhancer {
  /// For subclasses.
  const TokenEnhancer.base();

  /// An enhancer applying [enhance].
  factory TokenEnhancer(Graph Function(Graph graph) enhance) = _Function;

  /// The enhancer that returns its graph unchanged.
  static const TokenEnhancer identity = _Identity();

  /// The enhancers applied in order, first to last.
  static TokenEnhancer pipeline(List<TokenEnhancer> enhancers) {
    var result = identity;
    for (final enhancer in enhancers) {
      result = result.andThen(enhancer);
    }
    return result;
  }

  /// [graph], enhanced.
  Graph enhance(Graph graph);

  /// This enhancer followed by [after].
  TokenEnhancer andThen(TokenEnhancer after) => identical(this, identity)
      ? after
      : _Function((graph) => after.enhance(enhance(graph)));
}

final class _Identity extends TokenEnhancer {
  const _Identity() : super.base();

  @override
  Graph enhance(Graph graph) => graph;
}

final class _Function extends TokenEnhancer {
  _Function(this._enhance) : super.base();

  final Graph Function(Graph graph) _enhance;

  @override
  Graph enhance(Graph graph) => _enhance(graph);
}
