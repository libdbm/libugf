import 'package:libugf/libugf.dart';
import 'package:libugf/src/arithmetic.dart' show largest;
import 'package:test/test.dart';

Compiled compile(String grammar) => Compiler.compile(
  GrammarLoader.unvalidated(grammar).orElseThrow(),
  Predicates.standard(),
).orElseThrow();

Graph tokenize(String grammar, String input) =>
    Lexer(compile(grammar)).tokenize(input).orElseThrow();

/// The categories of the edges leaving the nodes at [offset].
Set<String?> categories(Graph graph, int offset) => {
  for (final node in graph.nodes)
    if (node.offset == offset)
      for (final edge in graph.edgesOf(node)) edge.category,
};

List<String> texts(Graph graph) => [for (final edge in graph.edges) edge.text];

/// Ported from Java `LexerTests` at unifica 8d8c01a, except the state, skip
/// and caller-token tests (Tasks 23 and 25) and `testSimpleGrammar`, whose
/// grammar needs lowering (Task 21). Grammars that used a group or a
/// quantifier in a syntactic production to make a sequence are written with
/// plain productions; the lexer reads only their lexemes.
void main() {
  test('testMaximalMunch', () {
    final graph = tokenize(
      "start S; S --> AB; S --> A B; AB --> 'ab'; A --> 'a'; B --> 'b';",
      'ab',
    );

    expect(texts(graph), ['ab']);
    expect(categories(graph, 0), {'AB'});
    // The shorter lexeme declared first.
    expect(
      categories(
        tokenize(
          "start S; S --> AB; S --> A B; A --> 'a'; B --> 'b'; AB --> 'ab';",
          'ab',
        ),
        0,
      ),
      {'AB'},
    );
  });

  test('testEqualLengthAlternatives', () {
    final graph = tokenize(
      "start S; S --> K; S --> I; K --> 'if'; I --> [a-z]+;",
      'if',
    );

    expect(categories(graph, 0), {'K', 'I'});
  });

  test('testTiesKeepDeclarationOrder', () {
    List<String?> order(String grammar) => [
      for (final edge in tokenize(grammar, 'if').edges) edge.category,
    ];

    // A literal is indexed by its first character, a regex tried
    // everywhere; neither changes the order.
    expect(order("start S; S --> K; S --> I; K --> 'if'; I --> [a-z]+;"), [
      'K',
      'I',
    ]);
    expect(order("start S; S --> K; S --> I; I --> [a-z]+; K --> 'if';"), [
      'I',
      'K',
    ]);
    expect(order("start S; S --> I; S --> T; I --> [a-z]+; T --> 'if' 'x';"), [
      'I',
      "'if'",
    ]);
    expect(order("start S; S --> T; S --> I; T --> 'if' 'x'; I --> [a-z]+;"), [
      "'if'",
      'I',
    ]);
  });

  test('testErrorEdge', () {
    final graph = tokenize("start S; S --> A B; A --> 'a'; B --> 'b';", 'a#b');

    expect(categories(graph, 1), {Edge.error});
    expect(texts(graph), ['a', '#', 'b']);
    expect(graph.edges[1].cost, 0);
  });

  test('testErrorEdgeIsOneCodePoint', () {
    final graph = tokenize("start S; S --> A; A --> 'a';", '\u{1F600}a');

    expect(texts(graph), ['\u{1F600}', 'a']);
    expect(graph.edges.first.end, 2);
  });

  test('testWhitespace', () {
    final graph = tokenize(
      "start S; S --> K X; K --> 'a b'; X --> 'c';",
      'a b  c ',
    );

    expect(texts(graph), ['a b', 'c']);
    final second = graph.edges[1];
    expect(second.start, 5);
    expect(second.end, 6);
    expect(graph.nodes.any(graph.isFinal), isTrue);
  });

  test('testDeclaredWhitespace', () {
    final graph = tokenize(
      "start S; whitespace [_]+; S --> A A; A --> 'a';",
      'a__a',
    );

    expect(texts(graph), ['a', 'a']);
    expect(
      categories(
        tokenize("start S; whitespace [_]+; S --> A A; A --> 'a';", 'a a'),
        1,
      ),
      {Edge.error},
    );
  });

  test('testEmptyInput', () {
    final graph = tokenize("start S; S --> ; S --> A; A --> 'a';", '');

    expect(graph.nodes, hasLength(1));
    expect(graph.isFinal(graph.start), isTrue);
  });

  test('testNodesInTopologicalOrder', () {
    final graph = tokenize(
      'start S; S --> W S; S --> W; W --> [a-z]+;',
      'ab cd ef',
    );

    for (final edge in graph.edges) {
      expect(edge.from.id, lessThan(edge.to.id));
    }
    for (var index = 0; index < graph.edges.length; index++) {
      expect(graph.edges[index].id, index);
    }
  });

  test('testConstrainedLongestDoesNotSuppress', () {
    final graph = tokenize(
      "start S; S --> W; S --> A; W --> [a-z]+:w where starts_with(w, 'x'); A --> 'ab';",
      'abc',
    );

    expect(categories(graph, 0), {'A'});
  });

  test('testLabelsAndTextBoundForConstraints', () {
    const grammar =
        "start S; S --> W; W --> [a-z]+:w where starts_with(w, 'a'), ends_with(W, 'c');";

    expect(categories(tokenize(grammar, 'abc'), 0), {'W'});
    expect(categories(tokenize(grammar, 'bbc'), 0), {Edge.error});
  });

  test('testSoftConstraintCost', () {
    final graph = tokenize(
      "start S; S --> W; W --> [a-z]+:w where starts_with(w, 'q'):4 @1;",
      'abc',
    );

    expect(graph.edges.first.cost, 5);
  });

  test('testPenaltyOverflow', () {
    final weight = largest;
    for (final grammar in [
      "start S; S --> W; W --> [a-z]+:w where starts_with(w, 'q'):$weight @1;",
      "start S; S --> W; W --> [a-z]+:w where starts_with(w, 'q'):$weight, ends_with(w, 'q'):1;",
    ]) {
      final result = Lexer(compile(grammar)).tokenize('abc');
      final error = (result as Failure<Graph, ErrorDetails>).error;
      expect(error.code, Lexer.overflow, reason: grammar);
      expect(error.message, 'token penalty overflow at offset 0');
    }
  });

  test('testLexicalPredicate', () {
    const grammar =
        'start S; S --> A; S --> B; S --> C;'
        " A --> 'y' where (in_state('DEFAULT') | equals('a', 'b'));"
        " B --> 'z' where !in_state('IN'); C --> 'w' where !in_state('DEFAULT');";

    expect(categories(tokenize(grammar, 'y'), 0), {'A'});
    expect(categories(tokenize(grammar, 'z'), 0), {'B'});
    expect(categories(tokenize(grammar, 'w'), 0), {Edge.error});
  });

  test('testLexemeFeaturesOnEdge', () {
    final graph = tokenize("start S; S --> N; N{num: sg} --> 'dog';", 'dog');

    expect(graph.edges.first.features.get('num')!.display(), 'sg');
  });

  test('testTokenPositions', () {
    final edges = tokenize(
      'start S; S --> A B; A --> [a-z]+; B --> [0-9]+;',
      'ab  12',
    ).edges;

    expect((edges[0].start, edges[0].end), (0, 2));
    expect((edges[1].start, edges[1].end), (4, 6));
  });

  test('testZeroLengthMatchIgnored', () {
    final graph = tokenize("start S; S --> A B; A --> [a]*; B --> 'b';", 'b');

    expect(texts(graph), ['b']);
  });

  test('testWhitespaceOnlyInput', () {
    final graph = tokenize("start S; S --> ; S --> A; A --> 'a';", '   \n\t ');

    expect(graph.edges, isEmpty);
    expect(graph.nodes.any(graph.isFinal), isTrue);
  });

  test('testWhitespaceNoneKeepsSpaces', () {
    final graph = tokenize(
      'start S; whitespace none; S --> W SP W; W --> [a-z]+; SP --> [ ]+;',
      'ab  cd',
    );

    expect(texts(graph), ['ab', '  ', 'cd']);
  });

  test('testMathTokens', () {
    const grammar =
        'start e; e --> t; t --> number; t --> variable; t --> op; t --> lparen; t --> rparen;'
        " number --> [0-9]+ ('.' [0-9]+)?; variable --> [a-z]+; op --> [-+*/];"
        " lparen --> '('; rparen --> ')';";

    final graph = tokenize(grammar, '(x + 2) * 3.14 - -1');

    expect(texts(graph), ['(', 'x', '+', '2', ')', '*', '3.14', '-', '-', '1']);
    expect(categories(graph, 9), {'number'});
  });

  test('testLexicalAlternationAndRepetition', () {
    final graph = tokenize(
      "start S; S --> K K; K --> ('ab' | 'cd')+ [0-9]?;",
      'abcd1 cdcd',
    );

    expect(texts(graph), ['abcd1', 'cdcd']);
  });

  test('testLookaroundSeesTheWholeInput', () {
    final graph = tokenize(
      r"start S; S --> A B; A --> 'a'; B --> (?<=a)'b'(?=$);",
      'ab',
    );

    expect(categories(graph, 1), {'B'});
  });
}
