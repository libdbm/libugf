import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Compiled compile(String grammar) => Compiler.compile(
  GrammarLoader.unvalidated(grammar).orElseThrow(),
  Predicates.standard(),
).orElseThrow();

Graph tokenize(String grammar, String input) =>
    Lexer(compile(grammar)).tokenize(input).orElseThrow();

Set<String?> categories(Graph graph, int offset) => {
  for (final vertex in graph.nodes)
    if (vertex.offset == offset)
      for (final edge in graph.edgesOf(vertex)) edge.category,
};

List<String> texts(Graph graph) => [for (final edge in graph.edges) edge.text];

bool accepts(String grammar, String input) =>
    ParserFactory.create(GrammarLoader.unvalidated(grammar).orElseThrow())
        .orElseThrow()
        .parse(input)
        .success;

/// Lexical states, skip and whitespace (R-LEX-2 to R-LEX-4, S-L3, S-L4).
/// Ported from Java `LexerTests`, `ParserTests` and `ReadmeExamplesTests` at
/// unifica 8d8c01a.
void main() {
  group('states', () {
    test('testStateConstrainedLexeme', () {
      const grammar =
          "start s; s --> open b; open --> '<' ==> IN; b --> {IN} 'y';";

      expect(texts(tokenize(grammar, '<y')), ['<', 'y']);
      expect(categories(tokenize(grammar, 'y'), 0), {Edge.error});
    });

    test('testDivergentStates', () {
      // Equal spans with different transitions lead to different vertices.
      final graph = tokenize(
        "start s; s --> a x; s --> b y; a --> 'k' ==> P; b --> 'k' ==> Q;"
            " x --> {P} 'z'; y --> {Q} 'z';",
        'kz',
      );

      expect({
        for (final edge in graph.edgesOf(graph.start)) edge.to,
      }, hasLength(2));
      expect(categories(graph, 1), {'x', 'y'});
    });

    test('testTransitionPopAndReset', () {
      final graph = tokenize(
        "start s; s --> o c r; o --> '(' ==> IN; c --> {IN} ')' ==> _; r --> '!' ==> !DONE;",
        '()!',
      );

      expect(graph.nodes.last.states, ['DONE']);
      expect(graph.nodes[2].states, ['DEFAULT']);
      expect(graph.nodes[1].states, ['DEFAULT', 'IN']);
    });

    test('testPopNeverBelowTheBottom', () {
      final graph = tokenize("start s; s --> c c; c --> ')' ==> _;", '))');

      expect([
        for (final vertex in graph.nodes) vertex.states,
      ], everyElement(['DEFAULT']));
      expect(graph.nodes, hasLength(3));
    });

    test('testReplaceTransition', () {
      const grammar =
          "start s; s --> o r c; o --> '<' ==> A; r --> {A} 'x' ==> ^B; c --> {B} '>' ==> _;";

      expect(accepts(grammar, '<x>'), isTrue);
      expect(accepts(grammar, '<x x>'), isFalse);
      expect(tokenize(grammar, '<x').nodes.last.states, ['DEFAULT', 'B']);
    });

    test('testStateAnnotationMatchesTheTop', () {
      // A lexeme annotated {A} matches only when A is on top of the stack.
      const grammar =
          "start s; s --> a b w; a --> 'a' ==> A; b --> 'b' ==> B; w --> {A} 'w';";

      expect(categories(tokenize(grammar, 'abw'), 2), {Edge.error});
    });

    test('testDepthLimit', () {
      final lexer = Lexer(compile("start s; s --> o; o --> '(' ==> IN;"));

      expect(
        lexer.tokenize('((', depth: 3),
        isA<Success<Graph, ErrorDetails>>(),
      );
      final error = (lexer.tokenize(
        '(((',
        depth: 3,
      ) as Failure<Graph, ErrorDetails>).error;
      expect(error.code, Lexer.depth);
      expect(
        error.message,
        'a lexical state stack is deeper than 3 at offset 3',
      );
      expect(lexer.tokenize('(((((('), isA<Success<Graph, ErrorDetails>>());
    });

    test('testXmlElementTokens', () {
      const grammar =
          'start doc; doc --> lt name gt text ltc name gt | lt name slashgt;'
          " lt --> '<' ==> TAG; ltc --> '</' ==> TAG; gt --> {TAG} '>' ==> _;"
          " slashgt --> {TAG} '/>' ==> _;"
          ' name --> {TAG} [a-z]+; text --> {DEFAULT} [^<]+;';

      expect(texts(tokenize(grammar, '<div>hello</div>')), [
        '<',
        'div',
        '>',
        'hello',
        '</',
        'div',
        '>',
      ]);
      expect(texts(tokenize(grammar, '<br/>')), ['<', 'br', '/>']);
      // Longest match: "</" is one token, not "<" then "/".
      expect(categories(tokenize(grammar, '<a>x</a>'), 4), {'ltc'});
    });

    test('testCDATAContent', () {
      const grammar =
          "start doc; doc --> open body close; open --> '<![CDATA[' ==> CDATA;"
          r' body --> {CDATA} (?:[^\]]|[\]](?![\]]>))+;'
          " close --> {CDATA} ']]>' ==> _;";

      expect(texts(tokenize(grammar, '<![CDATA[a < b & ] c]]>')), [
        '<![CDATA[',
        'a < b & ] c',
        ']]>',
      ]);
    });

    test('testReadmeStates', () {
      // The README's states.ug example.
      const grammar = '''
# Words, and code spans in backquotes. Inside a code span the lexer is in
# state CODE, where any run of non-space characters is one Token.
# Comments run from '#' to the end of the line and are skipped.
start Text;
skip Comment;

Text --> (Word | Code)*;
Code --> Open Token* Close;

Word --> [a-z]+;
Open --> '`' ==> CODE;
Token --> {CODE} [^`\\s]+;
Close --> {CODE} '`' ==> _;
Comment --> '#' [^\\n]*;
''';

      expect(accepts(grammar, 'see `x + 1` here # a comment\nand `y`'), isTrue);
      expect(accepts(grammar, 'see `x + 1 here'), isFalse);
      expect(accepts(grammar, 'see + here'), isFalse);
      final graph = tokenize(grammar, 'see `x + 1` # c\nand');
      // In CODE, Word (which has no state annotation) and Token both match
      // x; only Token matches +; the comment is skipped.
      expect(categories(graph, 5), {'Word', 'Token'});
      expect(categories(graph, 6), {'Token'});
      expect(texts(graph), isNot(contains('# c')));
    });
  });

  group('skip', () {
    test('testSkipCategories', () {
      const grammar =
          'start S; skip Block, Line; S --> W+; W --> [a-z]+;'
          r" Block --> '/*' (?:[^*]|[*]+[^*/])* [*]+ '/'; Line --> '//' [^\n]*;";

      final graph = tokenize(grammar, 'ab /* x */ cd // y\n ef/**/gh');

      expect(texts(graph), ['ab', 'cd', 'ef', 'gh']);
      expect(graph.nodes.any(graph.isFinal), isTrue);
    });

    test('testSkipRespectsStates', () {
      const grammar =
          "start S; skip C; S --> o W W; o --> '<' ==> IN; W --> [a-z]+; C --> {IN} '#' [a-z]*;";

      expect(texts(tokenize(grammar, '<ab #zz cd')), ['<', 'ab', 'cd']);
      expect(
        categories(
          tokenize(
            "start S; skip C; S --> W W; W --> [a-z]+; C --> {IN} '#' [a-z]*;",
            'ab #zz',
          ),
          2,
        ),
        {Edge.error},
      );
    });

    test('testSkipConstraints', () {
      // A skip category's constraints decide whether a match is discarded.
      const grammar =
          "start S; skip H; S --> W+; W --> [a-z]+; H --> '#' [^\\n]* where at_char_start();";

      expect(accepts(grammar, '#note\nab'), isTrue);
      expect(accepts(grammar, 'a #b'), isFalse);
    });

    test('testSkipAppliesNoTransition', () {
      const grammar =
          "start S; skip C; S --> W W; W --> [a-z]+; C --> '#' ==> IN;";

      final graph = tokenize(grammar, 'ab # cd');

      expect(texts(graph), ['ab', 'cd']);
      expect([
        for (final vertex in graph.nodes) vertex.states,
      ], everyElement(['DEFAULT']));
    });

    test('testSkipBeforeWhitespaceAndRepeated', () {
      // Whitespace and skip categories alternate until neither matches.
      const grammar =
          "start S; skip C; S --> W W; W --> [a-z]+; C --> '#' [a-z]*;";

      expect(texts(tokenize(grammar, 'ab #x #y  #z cd')), ['ab', 'cd']);
    });

    test('testSkipEndSeesNoTransition', () {
      // A skip lexeme's at_end is computed with no transition (S-L4): the
      // trailing comment is skipped only at the end of the input.
      const grammar =
          "start S; skip C; S --> W+; W --> [a-z]+; C --> '#' [a-z]* where at_end();";

      expect(accepts(grammar, 'ab #c'), isTrue);
      expect(accepts(grammar, 'ab #c d'), isFalse);
    });
  });

  group('whitespace', () {
    test('testWhitespaceStatement', () {
      const lines =
          r'start s; whitespace [ \t]+; s --> W NL W; NL --> [\n]; W --> [a-z]+;';
      const tight = "start s; whitespace none; s --> 'a' 'b';";

      expect(accepts(lines, 'ab \n cd'), isTrue);
      expect(
        accepts(r'start s; s --> W NL W; NL --> [\n]; W --> [a-z]+;', 'ab\ncd'),
        isFalse,
      );
      expect(accepts(tight, 'ab'), isTrue);
      expect(accepts(tight, 'a b'), isFalse);
    });
  });

  group('bindings', () {
    test('testLexicalEndAfterTransition', () {
      // at_end skips trailing text under the state stack after the token's
      // transition: C skips spaces only in DEFAULT, and A moves to IN, so
      // the spaces after A are not skipped and A is not at the end.
      const grammar =
          'start S; whitespace none; skip C; S --> A; S --> A B;'
          " A --> 'a' where at_end() ==> IN; B --> {IN} [ ]+; C --> {DEFAULT} [ ]+;";

      expect(accepts(grammar, 'a'), isTrue);
      expect(accepts(grammar, 'a  '), isFalse);
    });

    test('testLexicalPosition', () {
      const grammar =
          "start S; S --> A B; A --> 'a' where at_start(); B --> 'b' where at_position('2');";

      expect(accepts(grammar, 'a b'), isTrue);
      expect(accepts(grammar, 'a  b'), isFalse);
      expect(accepts(grammar, ' a b'), isFalse);
    });
  });
}
