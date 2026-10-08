import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

const states = ['DEFAULT'];

Edge edge(int id, Vertex from, Vertex to, int cost) => Edge(
  id: id,
  from: from,
  to: to,
  start: from.offset,
  text: 'x',
  category: 'X',
  features: Structure.empty,
  cost: cost,
);

/// Ported from Java `GraphTests` at unifica 8d8c01a: construction and
/// validation. The caller-token tests are Task 25's.
void main() {
  test('testGraphAccessors', () {
    final first = Vertex(0, 0, states);
    final second = Vertex(1, 1, states);
    final only = edge(0, first, second, 2);
    final graph = Graph(
      [first, second],
      [
        [only],
        [],
      ],
      {1},
    );

    expect(graph.start, first);
    expect(graph.edgesOf(first), [only]);
    expect(graph.edges, [only]);
    expect(graph.isFinal(second), isTrue);
    expect(graph.isFinal(first), isFalse);
    expect(only.end, 1);
    expect(() => graph.nodes.add(first), throwsUnsupportedError);
    expect(() => graph.edgesOf(first).add(only), throwsUnsupportedError);
  });

  test('testUncategorizedEdge', () {
    final from = Vertex(0, 0, states);
    final to = Vertex(1, 1, states);

    expect(
      Edge(
        id: 0,
        from: from,
        to: to,
        start: 0,
        text: 'x',
        category: null,
        features: Structure.empty,
        cost: 0,
      ).category,
      isNull,
    );
  });

  test('testStateStackNeverEmpty', () {
    expect(() => Vertex(0, 0, const []), throwsArgumentError);
    final stack = ['DEFAULT'];
    final node = Vertex(0, 0, stack);
    stack.add('IN');
    expect(node.states, ['DEFAULT']);
  });

  test('testNegativeCostRejected', () {
    final from = Vertex(0, 0, states);
    final to = Vertex(1, 1, states);

    expect(() => edge(0, from, to, -7), throwsArgumentError);
    expect(() => edge(-1, from, to, 0), throwsArgumentError);
  });

  test('testTokenSpanOutsideNodesRejected', () {
    final from = Vertex(0, 2, states);
    final to = Vertex(1, 3, states);

    expect(
      () => Edge(
        id: 0,
        from: from,
        to: to,
        start: 1,
        text: 'x',
        category: 'X',
        features: Structure.empty,
        cost: 0,
      ),
      throwsArgumentError,
    );
  });

  test('testNodeIdMustBeItsIndex', () {
    expect(() => Graph([Vertex(8, 0, states)], [[]], {8}), throwsArgumentError);
  });

  test('testGraphNeedsAStartAndOneListPerNode', () {
    expect(() => Graph(const [], const [], const {}), throwsArgumentError);
    expect(
      () => Graph([Vertex(0, 0, states)], const [], const {}),
      throwsArgumentError,
    );
  });

  test('testFinalMustBeANode', () {
    expect(() => Graph([Vertex(0, 0, states)], [[]], {3}), throwsArgumentError);
  });

  test('testEdgeMustMoveForward', () {
    // Equal offsets keep the edge itself valid; only its direction in the
    // graph is wrong.
    final first = Vertex(0, 0, states);
    final second = Vertex(1, 0, states);
    final back = edge(0, second, first, 0);

    expect(
      () => Graph(
        [first, second],
        [
          [],
          [back],
        ],
        {1},
      ),
      throwsArgumentError,
    );
  });

  test('testEdgeMustLeaveItsListsNode', () {
    final first = Vertex(0, 0, states);
    final second = Vertex(1, 1, states);
    final third = Vertex(2, 2, states);
    final misplaced = edge(0, second, third, 0);

    expect(
      () => Graph(
        [first, second, third],
        [
          [misplaced],
          [],
          [],
        ],
        {2},
      ),
      throwsArgumentError,
    );
  });

  test('testEdgeTargetMustBeInTheGraph', () {
    final first = Vertex(0, 0, states);
    final stranger = Vertex(1, 1, const ['OTHER']);
    final member = Vertex(1, 1, states);

    expect(
      () => Graph(
        [first, member],
        [
          [edge(0, first, stranger, 0)],
          [],
        ],
        {1},
      ),
      throwsArgumentError,
    );
  });

  test('testEdgeIdsUnique', () {
    final first = Vertex(0, 0, states);
    final second = Vertex(1, 1, states);

    expect(
      () => Graph(
        [first, second],
        [
          [edge(0, first, second, 0), edge(0, first, second, 0)],
          [],
        ],
        {1},
      ),
      throwsArgumentError,
    );
  });
}
