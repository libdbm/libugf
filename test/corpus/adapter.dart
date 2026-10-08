/// Runs a corpus case through libugf and reports the result in the corpus
/// vocabulary: `{grammar: {ok, error}, inputs: [{input, outcome, penalty,
/// ambiguous, tree}], generation: {empty, rejected}}`, as Java
/// `ConformanceTests.actual` does.
library;

import 'dart:convert';
import 'dart:math';

import 'package:libugf/libugf.dart';

import '../support/canonical.dart';
import 'runner.dart';

/// The result of running [files] through the library.
Map<String, Object?> actual(Case files) {
  final Grammar grammar;
  final Parser parser;
  switch (GrammarLoader.parse(files['grammar.ug']!)) {
    case Success(:final value):
      grammar = value;
    case Failure(:final error):
      return {
        'grammar': {'ok': false, 'error': _code(error)},
      };
  }
  switch (ParserFactory.create(grammar)) {
    case Success(:final value):
      parser = value;
    case Failure(:final error):
      return {
        'grammar': {'ok': false, 'error': _code(error)},
      };
  }
  final settings = jsonDecode(files['case.json']!) as Map<String, Object?>;
  return {
    'grammar': {'ok': true},
    'inputs': [
      for (final input in inputs(files['inputs.txt'] ?? ''))
        _parse(parser, input),
    ],
    if (settings['generate'] case final Map<String, Object?> generate)
      'generation': _generate(grammar, parser, generate),
  };
}

/// Generates sentences and reports those that do not parse (S-N1), as Java
/// `ConformanceTests.generate`: whether none was generated, and the
/// rejected ones, distinct and sorted.
Map<String, Object?> _generate(
  Grammar grammar,
  Parser parser,
  Map<String, Object?> settings,
) {
  final sentences = GrammarGenerator.builder(grammar)
      .random(Random(settings['seed']! as int))
      .build()
      .orElseThrow()
      .generate(
        settings['start']! as String,
        Structure.empty,
        settings['count']! as int,
      )
      .orElse(const []);
  return {
    'empty': sentences.isEmpty,
    'rejected': ({
      for (final sentence in sentences)
        if (!parser.parse(sentence).success) sentence,
    }.toList()..sort()),
  };
}

/// A loader or compiler error code in the corpus vocabulary: `syntax`, or
/// `validation` for a grammar that loads but does not compile.
String _code(ErrorDetails error) => switch (error.code) {
  GrammarLoader.syntax => 'syntax',
  GrammarLoader.validation || Compiler.invalid => 'validation',
  _ => error.code,
};

Map<String, Object?> _parse(Parser parser, String input) {
  final result = parser.parse(input);
  return {
    'input': input,
    'outcome': result.outcome.name,
    'penalty': result.penalty,
    'ambiguous': result.ambiguous,
    'tree': switch (result.tree) {
      final selected? => tree(selected),
      null => null,
    },
  };
}
