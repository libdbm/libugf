@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

import '../../example/agreement.dart' as agreement;
import '../../example/example.dart' as quickstart;
import '../../example/predicates.dart' as predicates;
import '../../example/states.dart' as states;
import '../../example/tagged.dart' as tagged;

const fixtures = 'example';

Parser parser(String name) =>
    GrammarFiles.parse('$fixtures/$name')
        .flatMap((grammar) => ParserFactory.create(grammar))
        .orElseThrow();

/// The lines [body] prints.
List<String> output(void Function() body) {
  final lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.addAll(line.split('\n')),
    ),
  );
  return lines;
}

/// A README block tagged `<!-- example: name -->`.
final tag = RegExp(
  r'<!-- example: ([\w.-]+) -->\n```\w*\n(.*?)```',
  dotAll: true,
);

/// A region of an example program, from `// example: name` to
/// `// end example`.
final region = RegExp(
  r'\n( *)// example: ([\w-]+)\n(.*?)\n *// end example',
  dotAll: true,
);

/// The builtins table of the README.
final builtins = RegExp(
  r'<!-- builtins -->(.*?)<!-- /builtins -->',
  dotAll: true,
);

/// Each region of the example programs, with its indentation removed and a
/// trailing newline, by name.
Map<String, String> regions() => {
  for (final file in Directory(fixtures).listSync())
    if (file is File && file.path.endsWith('.dart'))
      for (final match in region.allMatches(file.readAsStringSync()))
        match[2]!:
            '${[for (final line in match[3]!.split('\n')) line.length > match[1]!.length ? line.substring(match[1]!.length) : line.trimLeft()].join('\n')}\n',
};

/// Ported from Java `ReadmeExamplesTests` at unifica 8d8c01a. The README's
/// grammars and code are the files in `example/`: each tagged README block
/// is a grammar there or a region of an example program, and the tests run
/// every program.
void main() {
  group('readme', () {
    test('testReadmeInSync', () {
      final readme = File('README.md').readAsStringSync();
      final sources = regions();
      final used = <String>{};

      for (final match in tag.allMatches(readme)) {
        final name = match[1]!;
        used.add(name);
        final expected = name.endsWith('.ug')
            ? File('$fixtures/$name').readAsStringSync()
            : sources[name];
        expect(match[2], expected, reason: 'README block $name');
      }

      final expected = {
        ...sources.keys,
        for (final file in Directory(fixtures).listSync())
          if (file.path.endsWith('.ug')) file.uri.pathSegments.last,
      };
      expect(used, expected, reason: 'every example appears in the README');
    });

    test('testBuiltinsListed', () {
      final table = builtins.firstMatch(File('README.md').readAsStringSync());
      expect(table, isNotNull, reason: 'README has a builtins table');

      final listed = {
        for (final match in RegExp(
          r'^\| `(\w+)\(',
          multiLine: true,
        ).allMatches(table![1]!))
          match[1]!,
      };
      final registered = {
        for (final phase in Phase.values) ...Predicates.standard().names(phase),
      };

      expect(listed, registered);
    });
  });

  group('examples', () {
    test('testQuickStart', () {
      final lines = output(quickstart.main);

      expect(lines.first, 'Expr');
      expect(lines.map((line) => line.trim()), contains("'4' [9,10]"));
    });

    test('testPipeline', () {
      final lines = output(agreement.main);

      expect(lines.first, 'S {num: pl}');
      expect(lines.last, 'the dogs bark');
    });

    test('testStates', () {
      final lines = output(states.main);

      expect(lines.first, 'Text');
      expect(lines, containsAllInOrder(['    Open', '    Token', '    Close']));
      expect(lines.join('\n'), isNot(contains('comment')));
    });

    test('testPredicates', () {
      expect(output(predicates.main), [
        'hello Ada: accepted',
        'hello Alan: rejected',
      ]);
    });

    test('testTokens', () {
      expect(output(tagged.main), ['accepted, ambiguous: false']);
    });
  });

  group('generation', () {
    test('testGeneration', () {
      final grammar = GrammarFiles.parse('$fixtures/agreement.ug')
          .orElseThrow();

      final generator = GrammarGenerator.builder(grammar)
          .random(Random(42))
          .policy(Policy.defaults.copy(depth: 10))
          .build()
          .orElseThrow();
      final plural = Structure.of({'num': const StringConstant('pl')});
      final sentences = generator.generate('S', plural, 5);

      final agreement = parser('agreement.ug');
      for (final sentence in sentences.orElseThrow()) {
        final result = agreement.parse(sentence);
        expect(result.outcome, Outcome.accepted, reason: sentence);
        expect(
          (result.tree! as Node).features.get('num'),
          const StringConstant('pl'),
        );
      }
    });
  });

  group('grammars', () {
    test('testArithmetic', () {
      final arithmetic = parser('arithmetic.ug');

      expect(arithmetic.parse('2 * (3 + 4.5) - 1').outcome, Outcome.accepted);
      expect(arithmetic.parse('2 * (3 + 4) - 1').ambiguous, isFalse);
      expect(arithmetic.parse('2 +').outcome, Outcome.rejected);
    });

    test('testAgreement', () {
      final agreement = parser('agreement.ug');

      expect(agreement.parse('a dog barks').outcome, Outcome.accepted);
      expect(agreement.parse('the dogs bark').outcome, Outcome.accepted);
      expect(agreement.parse('a dogs bark').outcome, Outcome.rejected);
      expect(agreement.parse('the dog bark').outcome, Outcome.rejected);
    });

    test('testGreeting', () {
      final greeting = parser('greeting.ug');

      expect(greeting.parse('hello, Anna').penalty, 0);
      expect(greeting.parse('hello, Bob').penalty, 2);
      expect(greeting.parse('hello Anna').penalty, 1);
      expect(greeting.parse('hello, anna').outcome, Outcome.rejected);
    });

    test('testStates', () {
      final states = parser('states.ug');

      expect(
        states.parse('see `x + 1` here # a comment\nand `y`').outcome,
        Outcome.accepted,
      );
      expect(states.parse('see `x + 1 here').outcome, Outcome.rejected);
      expect(states.parse('see + here').outcome, Outcome.rejected);
    });
  });
}
