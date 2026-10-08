import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Parser parser(String source) => Parser.of(
  Compiler.compile(
    GrammarLoader.unvalidated(source).orElseThrow(),
    Predicates.standard(),
  ).orElseThrow(),
);

Node root(ParseResult result) => result.tree! as Node;

ParseResult graph(Parser parser, Graph tokens) =>
    parser.parseGraph(tokens).orElseThrow();

String symbol(ParseTree tree) => (tree as Node).symbol;

Edge edge(
  int id,
  Vertex from,
  Vertex to,
  int start,
  String text,
  String category,
) => Edge(
  id: id,
  from: from,
  to: to,
  start: start,
  text: text,
  category: category,
  features: Structure.empty,
  cost: 0,
);

/// Selection by S-P3 (R-PARSE-8, D15). Ported from Java `ParserTests` at
/// unifica 8d8c01a.
void main() {
  test('testTieBreakDeclarationOrder', () {
    final first = parser(
      "start S; S --> A; S --> B; A --> X; B --> X; X --> 'x';",
    ).parse('x');
    final second = parser(
      "start S; S --> B; S --> A; A --> X; B --> X; X --> 'x';",
    ).parse('x');

    expect(symbol(root(first).children.first), 'A');
    expect(first.ambiguous, isTrue);
    expect(first.tied, isFalse);
    expect(symbol(root(second).children.first), 'B');
  });

  test('testUnambiguous', () {
    final result = parser("start S; S --> A B; A --> 'a'; B --> 'b';")
        .parse('a b');

    expect(result.ambiguous, isFalse);
    expect(result.tied, isFalse);
  });

  test('testNullableAmbiguity', () {
    final parsed = parser("start S; S --> A A; A --> E?; E --> 'a';");

    expect(parsed.parse('a').ambiguous, isTrue);
    expect(parsed.parse('aa').ambiguous, isFalse);
    expect(parsed.parse('').ambiguous, isFalse);
  });

  test('testTieBreakTokenStateStack', () {
    // Tokens that tie on category are ordered by the state stack they lead
    // to, compared from the bottom, never by edge id.
    final start = Vertex(0, 0, const ['DEFAULT']);
    final later = Vertex(1, 1, const ['DEFAULT', 'B']);
    final earlier = Vertex(2, 1, const ['DEFAULT', 'A']);
    final tokens = Graph(
      [start, later, earlier],
      [
        [
          edge(0, start, later, 0, 'first', 'x'),
          edge(1, start, earlier, 0, 'second', 'x'),
        ],
        [],
        [],
      ],
      {1, 2},
    );

    final result = graph(parser('start S; S --> {TOKEN};'), tokens);

    expect(result.ambiguous, isTrue);
    expect((root(result).children.first as Leaf).text, 'second');
    expect(result.tied, isFalse);
  });

  test('testTieBreakDeclarationOrderIsTied', () {
    // Java logs a warning when only declaration order chose the tree (S-P3);
    // Dart reports it as tied (D15).
    final first = parser(
      "start S; S --> {TOKEN}; W{k: b} --> 'a'; W{k: a} --> 'a';",
    ).parse('a');
    final ordered = parser(
      "start S; S --> {TOKEN}; B{k: b} --> 'a'; A{k: a} --> 'a';",
    ).parse('a');

    expect((root(first).children.first as Leaf).features.display(), '{k: b}');
    expect(first.tied, isTrue);
    expect(ordered.tied, isFalse);
    expect((root(ordered).children.first as Leaf).features.display(), '{k: a}');
  });

  test('testTieBreakComparesWholeTrees', () {
    // Under S -> A* B, one A over "aa" gives productions [S, A, B] and two
    // A's give [S, A, A, B]; the second is smaller because A is declared
    // before B, although inside the repetition alone [A] is a prefix of
    // [A, A] and so comes first.
    final vertices = [
      for (var index = 0; index < 4; index++)
        Vertex(index, index, const ['DEFAULT']),
    ];
    final tokens = Graph(
      vertices,
      [
        [
          edge(0, vertices[0], vertices[1], 0, 'a', 'x'),
          edge(1, vertices[0], vertices[2], 0, 'aa', 'x'),
        ],
        [edge(2, vertices[1], vertices[2], 1, 'a', 'x')],
        [edge(3, vertices[2], vertices[3], 2, 'b', 'y')],
        [],
      ],
      {3},
    );

    final result = graph(
      parser("start S; S --> A* B; A --> x; B --> y; x --> 'x'; y --> 'y';"),
      tokens,
    );

    expect(result.ambiguous, isTrue);
    expect(
      [for (final child in root(result).children) symbol(child)],
      ['A', 'A', 'B'],
    );
  });

  test('testCategoriesCompareByCodePoint', () {
    // By code point U+FF21 precedes U+1F600; by UTF-16 unit the surrogate
    // 0xD83D of U+1F600 would come first.
    final start = Vertex(0, 0, const ['DEFAULT']);
    final end = Vertex(1, 1, const ['DEFAULT']);
    final tokens = Graph(
      [start, end],
      [
        [
          edge(0, start, end, 0, 'emoji', '\u{1F600}'),
          edge(1, start, end, 0, 'letter', '\u{FF21}'),
        ],
        [],
      ],
      {1},
    );

    final result = graph(parser('start S; S --> {TOKEN};'), tokens);

    expect((root(result).children.first as Leaf).text, 'letter');
  });

  test('testNoCategoryComesFirst', () {
    final start = Vertex(0, 0, const ['DEFAULT']);
    final end = Vertex(1, 1, const ['DEFAULT']);
    final tokens = Graph(
      [start, end],
      [
        [
          edge(0, start, end, 0, 'named', 'a'),
          Edge(
            id: 1,
            from: start,
            to: end,
            start: 0,
            text: 'bare',
            category: null,
            features: Structure.empty,
            cost: 0,
          ),
        ],
        [],
      ],
      {1},
    );

    final result = graph(parser('start S; S --> {TOKEN};'), tokens);

    expect((root(result).children.first as Leaf).text, 'bare');
  });

  test('testTiedAcrossRoots', () {
    // Two final vertices at one offset and state hold separate roots that
    // differ only in the caller's order of their tokens.
    final start = Vertex(0, 0, const ['DEFAULT']);
    final first = Vertex(1, 1, const ['DEFAULT']);
    final second = Vertex(2, 1, const ['DEFAULT']);
    final tokens = Graph(
      [start, first, second],
      [
        [
          edge(0, start, first, 0, 'one', 'x'),
          edge(1, start, second, 0, 'two', 'x'),
        ],
        [],
        [],
      ],
      {1, 2},
    );

    final result = graph(parser('start S; S --> {TOKEN};'), tokens);

    expect((root(result).children.first as Leaf).text, 'one');
    expect(result.ambiguous, isTrue);
    expect(result.tied, isTrue);
  });

  test('testAuxiliaryProductionsNotCompared', () {
    // Only real symbols enter the production key: A is declared before B,
    // although the auxiliaries lowered for B+ precede those for A+.
    final result = parser(
      "start S; S --> (B+ | A+); A --> X; B --> X; X --> 'x';",
    ).parse('x');

    expect(result.ambiguous, isTrue);
    expect(symbol(root(result).children.first), 'A');
  });

  test('testDeepDerivationSelects', () {
    const depth = 50000;
    final input = List.filled(depth, 'a').join(' ');

    final result = parser("start S; S --> S A; S --> A; A --> 'a';")
        .parse(input);

    expect(result.success, isTrue);
    expect(result.tree!.text, 'a' * depth);
  });
}
