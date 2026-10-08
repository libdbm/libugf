/// Sources of token graphs.
library;

import '../parser/token.dart';
import '../result.dart';
import 'graph.dart';

/// Produces the token graph for an input (S-L1). The [Lexer] of a compiled
/// grammar is one source; caller-supplied tokens, such as POS-tagged words,
/// are another (S-L6).
abstract interface class TokenSource {
  /// The error code for caller tokens that do not form a token graph.
  static const tokens = 'graph.tokens';

  /// A source that ignores its input and yields a linear graph of [tokens]
  /// (S-L6). Tokens must be in order and must not overlap; otherwise
  /// tokenizing fails with [TokenSource.tokens].
  static TokenSource of(List<Token> tokens) => _Linear([
    for (final token in tokens) [token],
  ]);

  /// A source that ignores its input and yields a graph where `cells[i]`
  /// are alternative tokens sharing the boundaries of position `i` (S-L6).
  /// Every cell must be non-empty, its tokens must have the same start and
  /// end, and cells must be in order without overlapping; otherwise
  /// tokenizing fails with [TokenSource.tokens]. The order of a cell's
  /// tokens is the caller's order, the last S-P3 rule.
  static TokenSource alternatives(List<List<Token>> cells) => _Linear(cells);

  /// The token graph of [input].
  Result<Graph, ErrorDetails> tokenize(String input);
}

final class _Linear implements TokenSource {
  _Linear(List<List<Token>> cells)
    : _cells = [for (final cell in cells) List.unmodifiable(cell)];

  final List<List<Token>> _cells;

  @override
  Result<Graph, ErrorDetails> tokenize(String input) {
    final problems = <String>[];
    int? previous;
    for (var index = 0; index < _cells.length; index++) {
      final cell = _cells[index];
      if (cell.isEmpty) {
        problems.add('cell $index has no tokens');
        continue;
      }
      final first = cell.first;
      if (previous != null && first.start < previous) {
        problems.add('cell $index starts at ${first.start}, before $previous');
      }
      if (first.end < first.start) {
        problems.add('cell $index ends before it starts');
      }
      if (cell.any(
        (token) => token.start != first.start || token.end != first.end,
      )) {
        problems.add('cell $index has tokens with different spans');
      }
      previous = previous == null || first.end > previous
          ? first.end
          : previous;
    }
    if (problems.isNotEmpty) {
      return Failure(
        ErrorDetails(
          TokenSource.tokens,
          'Caller tokens do not form a token graph',
          problems,
        ),
      );
    }
    const states = ['DEFAULT'];
    final vertices = [
      Vertex(0, _cells.isEmpty ? 0 : _cells.first.first.start, states),
    ];
    final outgoing = <List<Edge>>[];
    var id = 0;
    for (final cell in _cells) {
      final from = vertices.last;
      final to = Vertex(vertices.length, cell.first.end, states);
      vertices.add(to);
      // Caller tokens carry their own offsets; the edge text is the token
      // text.
      outgoing.add([
        for (final token in cell)
          Edge(
            id: id++,
            from: from,
            to: to,
            start: token.start,
            text: token.text,
            category: token.category,
            features: token.features,
            cost: 0,
          ),
      ]);
    }
    outgoing.add(const []);
    return Success(Graph(vertices, outgoing, {vertices.length - 1}));
  }
}
