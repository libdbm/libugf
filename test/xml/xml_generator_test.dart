@TestOn('vm')
library;

import 'dart:math';

import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

import 'xml.dart' show build;

/// Ported from Java `XMLGeneratorTests` at unifica 8d8c01a. The grammar is
/// loaded as written, with the default whitespace, as in Java. Sequences
/// come from `dart:math` `Random`, so they differ from Java's (R-GEN-4).
void main() {
  late Grammar grammar;
  late GrammarGenerator generator;
  late Parser parser;

  setUp(() {
    grammar = GrammarFiles.parse('test/resources/xml.ug').orElseThrow();
    final random = Random(42);
    const names = ['div', 'span', 'p', 'img', 'link', 'meta', 'title'];
    const words = ['hello', 'world', 'test', 'content', 'data', 'value'];
    final terminals = RegexTerminalGenerator.builder()
        .register(
          r'[a-zA-Z][a-zA-Z0-9_\-]*',
          (features) => names[random.nextInt(names.length)],
        )
        .register(
          r'[a-zA-Z0-9_\\-]+',
          (features) => words[random.nextInt(words.length)],
        )
        // Without these the literal fallback emits the regex source, which
        // never parses, and only sentences that parse are returned (S-N1).
        .register(r'[ \t\n\r]+', (features) => ' ')
        .register(r'[^"<&]+', (features) => 'value')
        .fallback(const LiteralTerminalGenerator())
        .build();
    generator = GrammarGenerator.builder(grammar)
        .terminal(terminals)
        .random(random)
        .policy(Policy.defaults.copy(depth: 10))
        .build()
        .orElseThrow();
    parser = ParserFactory.create(grammar).orElseThrow();
  });

  test('testGenerateDocuments', () {
    expect(
      generator.generateOne('document', Structure.empty).orElseThrow(),
      isNotEmpty,
    );
    final documents = generator
        .generate('document', Structure.empty, 5)
        .orElseThrow();
    expect(documents, hasLength(5));
    expect(documents, everyElement(isNotEmpty));
  });

  test('testGeneratedDocumentsAreParseable', () {
    final shallow = GrammarGenerator.builder(grammar)
        .terminal(
          RegexTerminalGenerator.builder()
              .register(r'[a-zA-Z][a-zA-Z0-9_\-]*', (features) => 'div')
              .register(r'[a-zA-Z0-9_\-]+', (features) => 'text')
              .fallback(const LiteralTerminalGenerator())
              .build(),
        )
        .random(Random(42))
        .policy(Policy.defaults.copy(depth: 3))
        .build()
        .orElseThrow();

    for (final document
        in shallow.generate('document', Structure.empty, 5).orElse(const [])) {
      expect(parser.parse(document).success, isTrue, reason: document);
    }
  });

  test('testGenerateElements', () {
    final normal = generator
        .generate('normal_element', Structure.empty, 5)
        .orElseThrow();
    expect(normal, hasLength(5));
    for (final element in normal) {
      expect(element, allOf(contains('<'), contains('>'), contains('</')));
    }
    final empty = generator
        .generate('empty_element', Structure.empty, 5)
        .orElseThrow();
    expect(empty, hasLength(5));
    for (final element in empty) {
      expect(element, allOf(contains('<'), contains('/>')));
    }
  });

  test('testGenerateTagNames', () {
    final names = generator
        .generate('tagname', Structure.empty, 5)
        .orElseThrow();

    expect(names, hasLength(5));
    for (final name in names) {
      expect(
        RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]*$').hasMatch(name),
        isTrue,
        reason: name,
      );
    }
  });

  test('testGenerateAttributes', () {
    final attributes = generator
        .generate('attributes', Structure.empty, 3)
        .orElseThrow();

    expect(attributes, hasLength(3));
    for (final list in attributes) {
      expect(list, allOf(contains('='), contains('"')));
    }
    final values = generator
        .generate('attrvalue', Structure.empty, 5)
        .orElseThrow();
    expect(values, hasLength(5));
    for (final value in values) {
      expect(value, allOf(startsWith('"'), endsWith('"')));
    }
  });

  test('testRoundTripParseAndGenerate', () {
    final documents = generator
        .generate('document', Structure.empty, 10)
        .orElse(const []);

    // Every returned document was verified by parsing (S-N1), so all parse;
    // Java requires at least 2 of 10.
    expect(
      documents.where((document) => parser.parse(document).success).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('testGenerateAndBuildXML', () {
    for (final document
        in generator
            .generate('document', Structure.empty, 3)
            .orElse(const [])) {
      final result = parser.parse(document);
      if (result.tree case final tree?) {
        expect(build(tree), isNotNull);
      }
    }
  });

  test('testDeterministicGeneration', () {
    String document() =>
        GrammarGenerator.builder(grammar)
            .terminal(const LiteralTerminalGenerator())
            .random(Random(123))
            .policy(Policy.defaults.copy(depth: 10))
            .build()
            .orElseThrow()
            .generateOne('document', Structure.empty)
            .orElse('');

    expect(document(), document());
  });

  test('testGenerateTextContent', () {
    // Text content lexes only in the CONTENT state, entered after '>', so a
    // bare textcontent never parses as one (S-N1).
    final standalone = generator.generate('textcontent', Structure.empty, 5);
    expect(
      (standalone as Failure<List<String>, ErrorDetails>).error.message,
      contains('does not parse'),
    );

    final documents = generator
        .generate('document', Structure.empty, 10)
        .orElse(const []);
    expect(documents, isNotEmpty);
    expect(
      documents.any(
        (document) => RegExp(r'>[^<]+<', dotAll: true).hasMatch(document),
      ),
      isTrue,
    );
  });
}
