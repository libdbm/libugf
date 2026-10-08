@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

/// The Dart loader against Java's: every synced grammar loads (or fails) as
/// Java's loader does at unifica 8d8c01a, with the same rules, kinds, costs,
/// transitions, constraints and S-L7 verdicts. The expectations are a Java
/// observation recorded by `tool/observe/observe.sh` into
/// `test/corpus/java/grammars.json`, not conformance expectations.
void main() {
  final observed = jsonDecode(
    File('test/corpus/java/grammars.json').readAsStringSync(),
  ) as Map<String, Object?>;

  for (final MapEntry(key: name, value: expected) in observed.entries) {
    test(name, () {
      final source = File('test/corpus/$name').readAsStringSync();
      expect(canonical(GrammarLoader.unvalidated(source)), expected);
    });
  }
}

Object? canonical(Result<Grammar, ErrorDetails> result) => switch (result) {
  Failure(:final error) => {'error': error.code},
  Success(value: final grammar) => {
    'start': grammar.start,
    'module': grammar.module.name,
    'exports': grammar.module.exports.toList()..sort(),
    'skips': grammar.skips.toList()..sort(),
    'whitespace': grammar.whitespace == null
        ? null
        : {
            'pattern': grammar.whitespace,
            'portable': grammar.whitespace!.isEmpty
                ? null
                : verdict(Patterns.compile(grammar.whitespace!)),
          },
    'imports': [for (final declaration in grammar.imports) import(declaration)],
    'rules': [
      for (final rules in grammar.rules.values)
        for (final rule in rules)
          {
            'symbol': rule.lhs.symbol,
            'features': value(rule.lhs.features),
            'kind': rule.kind.name,
            'cost': rule.cost,
            'transition': rule.transition,
            'rhs': [for (final element in rule.rhs) item(element)],
            'constraints': [
              for (final constraint in rule.constraints) expression(constraint),
            ],
          },
    ],
  },
};

Object? import(ImportDeclaration declaration) => switch (declaration) {
  ImportAll(:final path) => {'all': path},
  ImportSelective(:final path, :final symbols) => {
    'selective': path,
    'symbols': symbols.toList()..sort(),
  },
  ImportFile(:final path) => {'file': path},
};

Object? item(RuleElement element) => switch (element) {
  Nonterminal(:final name, :final label, :final features) => {
    'nonterminal': name,
    'label': label,
    'features': value(features),
  },
  Terminal(:final text, :final label) => {'terminal': text, 'label': label},
  Regex(:final pattern, :final label) => {
    'regex': pattern,
    'label': label,
    'fragment': verdict(Patterns.fragment(pattern)),
  },
  Repetition(:final element, :final quantifier) => {
    'repetition': switch (quantifier) {
      Quantifier.star => '*',
      Quantifier.plus => '+',
      Quantifier.optional => '?',
    },
    'element': item(element),
  },
  Sequence(:final elements) => {
    'sequence': [for (final inner in elements) item(inner)],
  },
  Alternation(:final options) => {
    'alternation': [for (final option in options) item(option)],
  },
  StateAnnotation(:final state) => {'state': state},
  TokenMatch(:final label) => {'token': label},
};

Object? expression(Expression node) => switch (node) {
  And(:final terms) => {
    'and': [for (final term in terms) expression(term)],
  },
  Or(:final terms) => {
    'or': [for (final term in terms) expression(term)],
  },
  Not(:final term) => {'not': expression(term)},
  Weighted(:final term, :final weight) => {
    'weighted': expression(term),
    'weight': weight,
  },
  Literal(value: final truth) => {'literal': truth},
  Call(:final name, :final args) => {
    'call': name,
    'args': [for (final arg in args) value(arg)],
    if (name == 'matches' && args.length == 2 && args[1] is StringConstant)
      'portable': verdict(Patterns.compile((args[1] as StringConstant).value)),
  },
};

Object? value(Value node) => switch (node) {
  StringConstant(value: final text) => {'s': text},
  Variable(:final name) => {'v': name},
  FeaturePath(:final parts) => {'path': parts},
  final Structure structure => {
    'm': {
      for (final key in structure.keys.toList()..sort())
        key: value(structure.get(key)!),
    },
  },
  _ => {'other': node.display()},
};

String verdict(Result<Object, ErrorDetails> result) => switch (result) {
  Success() => 'ok',
  Failure(:final error) => error.code,
};
