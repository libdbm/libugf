import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Parser parser(String source, [Options options = const Options()]) => Parser.of(
  Compiler.compile(
    GrammarLoader.unvalidated(source).orElseThrow(),
    Predicates.standard(),
  ).orElseThrow(),
  options,
);

Token token(String text, int start, [String? category]) => Token(
  text,
  category == null
      ? Structure.empty
      : Structure.of({'pos': StringConstant(category)}),
  start,
  start + text.length,
  category,
);

ErrorDetails failure<T>(Result<T, ErrorDetails> result) =>
    (result as Failure<T, ErrorDetails>).error;

Node root(ParseResult result) => result.tree! as Node;

String symbol(ParseTree tree) => (tree as Node).symbol;

ParseResult parse(Parser parser, Graph graph, {String? input}) =>
    parser.parseGraph(graph, input: input).orElseThrow();

/// Caller-supplied tokens (S-L6, S-T2) and token enhancers. Ported from
/// Java `GraphTests` and `ParserTests` at unifica 8d8c01a.
void main() {
  group('sources', () {
    test('testLinearGraph', () {
      final graph = TokenSource.of([
        token('the', 0, 'DT'),
        token('dogs', 4, 'NNS'),
      ]).tokenize('ignored').orElseThrow();

      expect([for (final vertex in graph.nodes) vertex.offset], [0, 3, 8]);
      final first = graph.edgesOf(graph.start).first;
      expect((first.category, first.start, first.end), ('DT', 0, 3));
      expect(graph.edgesOf(graph.nodes[1]).first.start, 4);
      expect(graph.isFinal(graph.nodes[2]), isTrue);
    });

    test('testAlternatives', () {
      final graph = TokenSource.alternatives([
        [token('run', 0, 'VB'), token('run', 0, 'NN')],
        [token('fast', 4, 'RB')],
      ]).tokenize('ignored').orElseThrow();

      expect(graph.nodes, hasLength(3));
      expect(graph.edgesOf(graph.start), hasLength(2));
      expect(graph.edges, hasLength(3));
    });

    test('testEmptyTokenList', () {
      final graph = TokenSource.of(const []).tokenize('').orElseThrow();

      expect(graph.nodes, hasLength(1));
      expect(graph.isFinal(graph.start), isTrue);
    });

    test('testAlternativesWithDifferentSpansRejected', () {
      final error = failure(
        TokenSource.alternatives([
          [token('dogs', 0, 'NNS'), token('dog', 0, 'NN')],
        ]).tokenize(''),
      );

      expect(error.code, TokenSource.tokens);
      expect(error.issues, ['cell 0 has tokens with different spans']);
    });

    test('testOverlappingTokensRejected', () {
      final error = failure(
        TokenSource.of([token('dogs', 0, 'NNS'), token('s', 3, 'S')])
            .tokenize(''),
      );

      expect(error.issues, ['cell 1 starts at 3, before 4']);
    });

    test('testEmptyCellRejected', () {
      final error = failure(
        TokenSource.alternatives([
          [token('a', 0, 'A')],
          [],
        ]).tokenize(''),
      );

      expect(error.issues, ['cell 1 has no tokens']);
    });

    test('testLexerIsATokenSource', () {
      final TokenSource source = Lexer(
        Compiler.compile(
          GrammarLoader.unvalidated("start S; S --> 'a';").orElseThrow(),
          Predicates.standard(),
        ).orElseThrow(),
      );

      expect(source.tokenize('a').orElseThrow().edges, hasLength(1));
    });
  });

  group('parsing', () {
    test('testCallerSuppliedAlternatives', () {
      final graph = TokenSource.alternatives([
        [token('dogs', 0, 'NN'), token('dogs', 0, 'VB')],
        [token('run', 5, 'VB'), token('run', 5, 'NN')],
      ]).tokenize('').orElseThrow();

      final result = parse(
        parser("start S; S --> NN VB; NN --> 'zz'; VB --> 'yy';"),
        graph,
      );

      expect(result.outcome, Outcome.accepted);
      expect(
        [for (final child in root(result).children) symbol(child)],
        ['NN', 'VB'],
      );
      expect(result.ambiguous, isFalse);
    });

    test('testCallerOrderBreaksTies', () {
      // Equal categories and states: the caller's order chooses (S-P3), and
      // the result says only that order chose.
      for (final (first, second) in [('one', 'two'), ('two', 'one')]) {
        final graph = TokenSource.alternatives([
          [
            Token(first, Structure.empty, 0, 3, 'X'),
            Token(second, Structure.empty, 0, 3, 'X'),
          ],
        ]).tokenize('').orElseThrow();

        final result = parse(parser('start S; S --> {TOKEN};'), graph);

        expect((root(result).children.single as Leaf).text, first);
        expect(result.ambiguous, isTrue);
        expect(result.tied, isTrue);
      }
    });

    test('testUncategorizedCallerTokens', () {
      final graph = TokenSource.of([
        Token('zz', Structure.empty, 0, 2),
        Token('zz', Structure.empty, 3, 5),
      ]).tokenize('').orElseThrow();

      expect(
        parse(parser('start S; S --> {TOKEN} {TOKEN};'), graph).outcome,
        Outcome.accepted,
      );
      expect(
        parse(parser("start S; S --> W W; W --> 'zz';"), graph).outcome,
        Outcome.rejected,
      );
      expect(
        parse(parser("start S; S --> 'zz' 'zz';"), graph).outcome,
        Outcome.rejected,
      );
      expect(
        parse(
          parser(
            "start S; S --> P {TOKEN}; P --> {TOKEN} where before('null');",
          ),
          graph,
        ).outcome,
        Outcome.rejected,
      );
    });

    test('testCallerTokenText', () {
      final graph = TokenSource.of([
        Token('dogs', Structure.empty, 0, 4),
        Token('run', Structure.empty, 6, 9),
      ]).tokenize('').orElseThrow();
      final spanned = parser(
        "start S; S --> P:p where equals(p, 'dogs  run'); P --> {TOKEN} {TOKEN};",
      );
      final joined = parser(
        "start S; S --> P:p where equals(p, 'dogs run'); P --> {TOKEN} {TOKEN};",
      );
      final single = parser(
        "start S; S --> {TOKEN}:w P where equals(w, 'Dogs'); P --> {TOKEN};",
      );

      expect(
        parse(spanned, graph, input: 'dogs  run').outcome,
        Outcome.accepted,
      );
      expect(
        parse(joined, graph, input: 'dogs  run').outcome,
        Outcome.rejected,
      );
      expect(parse(joined, graph).outcome, Outcome.accepted);
      expect(parse(spanned, graph).outcome, Outcome.rejected);
      expect(
        parse(single, graph, input: 'Dogs  run').outcome,
        Outcome.accepted,
      );
    });

    test('testCallerGraphPastInput', () {
      final graph = TokenSource.of([Token('dogs', Structure.empty, 0, 4)])
          .tokenize('')
          .orElseThrow();

      final error = failure(
        parser('start S; S --> {TOKEN};').parseGraph(graph, input: 'dog'),
      );

      expect(error.code, TokenSource.tokens);
      expect(
        error.message,
        'node 1 is at offset 4, past the end of the input (3)',
      );
    });

    test('testPositionIsTokenIndex', () {
      // In a syntactic production at_position reads the token index, which
      // is independent of vertex ids. Vertices 1 and 2 share offset 1, so
      // vertex 2 has token index 1; vertex 3 is reached by paths of one and
      // two tokens.
      const states = ['DEFAULT'];
      final vertices = [
        Vertex(0, 0, states),
        Vertex(1, 1, states),
        Vertex(2, 1, const ['DEFAULT', 'B']),
        Vertex(3, 2, states),
        Vertex(4, 3, states),
      ];
      Edge edge(int id, int from, int to, String category) => Edge(
        id: id,
        from: vertices[from],
        to: vertices[to],
        start: vertices[from].offset,
        text: category,
        category: category,
        features: Structure.empty,
        cost: 0,
      );
      final graph = Graph(
        vertices,
        [
          [edge(0, 0, 1, 'x'), edge(1, 0, 2, 'y'), edge(2, 0, 3, 'w')],
          [edge(3, 1, 3, 'x')],
          [edge(4, 2, 3, 'z')],
          [edge(5, 3, 4, 'c')],
          [],
        ],
        {4},
      );
      const symbols = " x --> 'x'; y --> 'y'; z --> 'z'; w --> 'w'; c --> 'c';";

      expect(
        parse(
          parser(
            "start S; S --> y P c; P --> z where at_position('1');$symbols",
          ),
          graph,
        ).outcome,
        Outcome.accepted,
      );
      expect(
        parse(
          parser(
            "start S; S --> y P c; P --> z where at_position('2');$symbols",
          ),
          graph,
        ).outcome,
        Outcome.rejected,
      );
      for (final index in ['1', '2']) {
        expect(
          parse(
            parser(
              "start S; S --> w P; P --> c where at_position('$index');$symbols",
            ),
            graph,
          ).outcome,
          Outcome.accepted,
          reason: index,
        );
      }
    });
  });

  group('enhancers', () {
    /// Adds the category `tag` to every edge with no category.
    Graph tag(Graph graph, String category) {
      final edges = [
        for (final list in graph.outgoing)
          [
            for (final edge in list)
              Edge(
                id: edge.id,
                from: edge.from,
                to: edge.to,
                start: edge.start,
                text: edge.text,
                category: edge.category ?? category,
                features: edge.features,
                cost: edge.cost,
              ),
          ],
      ];
      return Graph(graph.nodes, edges, graph.finals);
    }

    test('testIdentityAndPipeline', () {
      final graph = TokenSource.of([Token.simple('a', 0, 1)])
          .tokenize('')
          .orElseThrow();
      final first = TokenEnhancer((graph) => tag(graph, 'A'));
      final second = TokenEnhancer((graph) => tag(graph, 'B'));

      expect(identical(TokenEnhancer.identity.enhance(graph), graph), isTrue);
      expect(first.andThen(second).enhance(graph).edges.single.category, 'A');
      expect(second.andThen(first).enhance(graph).edges.single.category, 'B');
      expect(
        TokenEnhancer.pipeline([second, first])
            .enhance(graph)
            .edges
            .single
            .category,
        'B',
      );
      expect(
        identical(TokenEnhancer.pipeline(const []).enhance(graph), graph),
        isTrue,
      );
    });

    test('testEnhancerAppliedBeforeParsing', () {
      final options = Options(
        enhancer: TokenEnhancer((graph) => tag(graph, 'W')),
      );
      final graph = TokenSource.of([Token.simple('zz', 0, 2)])
          .tokenize('')
          .orElseThrow();
      final enhanced = parser("start S; S --> W; W --> 'q';", options);

      expect(parse(enhanced, graph).outcome, Outcome.accepted);
      expect(
        parse(parser("start S; S --> W; W --> 'q';"), graph).outcome,
        Outcome.rejected,
      );
    });

    test('testEnhancerAppliedToLexedInput', () {
      // Every edge the lexer finds becomes a W.
      final options = Options(
        enhancer: TokenEnhancer((graph) {
          final edges = [
            for (final list in graph.outgoing)
              [
                for (final edge in list)
                  Edge(
                    id: edge.id,
                    from: edge.from,
                    to: edge.to,
                    start: edge.start,
                    text: edge.text,
                    category: 'W',
                    features: edge.features,
                    cost: edge.cost,
                  ),
              ],
          ];
          return Graph(graph.nodes, edges, graph.finals);
        }),
      );

      expect(
        parser(
          "start S; S --> W; W --> 'q'; X --> 'x';",
          options,
        ).parse('x').success,
        isTrue,
      );
    });
  });
}
