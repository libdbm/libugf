/// The parser.
library;

import '../compiler/compiled.dart';
import '../compiler/compiler.dart';
import '../compiler/element.dart';
import '../constraints/expression.dart';
import '../constraints/plan.dart';
import '../constraints/predicates.dart';
import '../features/value.dart';
import '../grammar/grammar.dart';
import '../lexer/graph.dart';
import '../lexer/lexer.dart';
import '../result.dart';
import 'parse_result.dart';
import '../lexer/token_source.dart';
import 'options.dart';
import 'session.dart';
import 'statistics.dart';
import 'stop.dart';

/// An Earley parser over the token graph of a [Compiled] grammar (S-P1 to
/// S-P8). A parser is immutable; each parse runs in its own session.
final class Parser {
  Parser._(this.compiled, this.options, this._canonical)
    : _lexer = Lexer(compiled),
      _referenced = {
        for (final production in compiled.productions)
          production.id: _labels(production),
      };

  /// A parser for [compiled] with [options].
  factory Parser.of(Compiled compiled, [Options options = const Options()]) =>
      Parser._(compiled, options, true);

  /// The compiled grammar.
  final Compiled compiled;

  /// The options for each parse.
  final Options options;
  final Lexer _lexer;

  /// Whether chart states are identified up to renamed variables (S-P9);
  /// false only in tests.
  final bool _canonical;

  /// The labels each production's constraints read, by production id.
  final Map<int, Set<String>> _referenced;

  /// Lexes [input] with the grammar's lexemes and parses the token graph as
  /// the start symbol, within the [options]' limits. With [symbol], parses
  /// it as that symbol instead, requiring the root constituent's features to
  /// unify with [features] (used to verify generated text, S-N1).
  ParseResult parse(String input, {String? symbol, Structure? features}) {
    final clock = Stopwatch()..start();
    final limits = options.limits;
    return switch (_lexer.tokenize(
      input,
      nodes: limits.nodes,
      depth: limits.depth,
      deadline: limits.deadline,
      cancel: options.cancel,
    )) {
      Success(value: final graph) => _run(
        graph,
        input,
        clock,
        _top(symbol ?? compiled.start, features),
      ),
      Failure(:final error) => _lexed(error, clock),
    };
  }

  /// Parses a token graph, for example one built from caller-supplied
  /// tokens (S-L6). With [input], whose offsets the graph's index, a
  /// constituent's text is the input it spans (S-C9), and a vertex past the
  /// end of the input is a [TokenSource.tokens] failure; without it, a
  /// constituent's text is its token texts joined by single spaces.
  Result<ParseResult, ErrorDetails> parseGraph(Graph graph, {String? input}) {
    final clock = Stopwatch()..start();
    if (input != null) {
      for (final vertex in graph.nodes) {
        if (vertex.offset > input.length) {
          return Failure(
            ErrorDetails.of(
              TokenSource.tokens,
              'node ${vertex.id} is at offset ${vertex.offset}, past the end '
              'of the input (${input.length})',
            ),
          );
        }
      }
    }
    return Success(_run(graph, input, clock, _top(compiled.start)));
  }

  /// Enhances [graph], holds it to the vertex limit and parses it as the
  /// start symbol.
  ParseResult _run(
    Graph graph,
    String? input,
    Stopwatch clock,
    Production top,
  ) {
    final enhanced = options.enhancer.enhance(graph);
    final nodes = options.limits.nodes;
    if (nodes > 0 && enhanced.nodes.length > nodes) {
      return _stopped(
        Outcome.limit,
        Stop(
          Stop.nodes,
          enhanced.nodes.length,
          nodes,
          'the token graph has ${enhanced.nodes.length} nodes, more than '
          '$nodes',
        ),
        clock,
      );
    }
    return Session(
      compiled,
      top,
      enhanced,
      input,
      _referenced,
      options,
      clock,
      _canonical,
    ).run();
  }

  /// The result of a parse whose input could not be lexed within the
  /// limits, as Java's `Parser.stopped`.
  ParseResult _lexed(ErrorDetails error, Stopwatch clock) {
    final limits = options.limits;
    return switch (error.code) {
      Lexer.nodes => _stopped(
        Outcome.limit,
        Stop(Stop.nodes, limits.nodes + 1, limits.nodes, error.message),
        clock,
      ),
      Lexer.depth => _stopped(
        Outcome.limit,
        Stop(Stop.depth, limits.depth + 1, limits.depth, error.message),
        clock,
      ),
      Lexer.deadline => _stopped(
        Outcome.limit,
        Stop(
          Stop.deadline,
          clock.elapsedMilliseconds,
          limits.deadline.inMilliseconds,
          error.message,
        ),
        clock,
      ),
      Lexer.interrupt => _stopped(
        Outcome.cancelled,
        Stop(Stop.interrupt, -1, -1, error.message),
        clock,
      ),
      Lexer.overflow => _stopped(
        Outcome.limit,
        Stop(Stop.penalty, -1, -1, error.message),
        clock,
      ),
      _ => _stopped(
        Outcome.limit,
        Stop(Stop.lexer, -1, -1, error.message),
        clock,
      ),
    };
  }

  static ParseResult _stopped(Outcome outcome, Stop stop, Stopwatch clock) =>
      ParseResult(
        outcome,
        stop: stop,
        statistics: Statistics(elapsed: clock.elapsed),
      );

  /// The token graph for [input], from the lexer [parse] uses.
  Result<Graph, ErrorDetails> tokenize(String input) => _lexer.tokenize(input);

  /// The labels of [production]'s elements that its constraints read.
  static Set<String> _labels(Production production) {
    final names = <String>{};
    for (final expression in production.plan.required) {
      _names(expression, names);
    }
    for (final soft in production.plan.soft) {
      _names(soft.expression, names);
    }
    return {
      for (final element in production.rhs)
        if (element.label case final label? when names.contains(label)) label,
    };
  }

  /// The variables and path roots [expression]'s calls name.
  static void _names(Expression expression, Set<String> names) {
    switch (expression) {
      case And(:final terms) || Or(:final terms):
        for (final term in terms) {
          _names(term, names);
        }
      case Not(:final term) || Weighted(:final term):
        _names(term, names);
      case Call(:final args):
        for (final arg in args) {
          switch (arg) {
            case FeaturePath(:final root):
              names.add(root);
            case Variable(:final name):
              names.add(name);
            default:
              break;
          }
        }
      case Literal():
        break;
    }
  }

  /// The auxiliary root production for [symbol]. Wrapping the start symbol
  /// lets a lexical start symbol work too.
  static Production _top(String symbol, [Structure? features]) => Production(
    id: -1,
    symbol: '',
    features: Structure.empty,
    rhs: [Named(symbol, null, features)],
    plan: Plan.empty,
    cost: 0,
    auxiliary: true,
  );
}

/// A parser for [compiled] that identifies chart states by their raw
/// bindings rather than up to renamed variables: for testing that canonical
/// merging changes no result (S-P9). Not exported.
Parser raw(Compiled compiled) => Parser._(compiled, const Options(), false);

/// Compiles a grammar and creates a [Parser] (PAR-10).
abstract final class ParserFactory {
  /// A parser for [grammar] compiled against [predicates] (the standard
  /// predicates by default) with [options], or the compiler's failure.
  static Result<Parser, ErrorDetails> create(
    Grammar grammar, [
    Predicates? predicates,
    Options options = const Options(),
  ]) => Compiler.compile(
    grammar,
    predicates ?? Predicates.standard(),
  ).map((compiled) => Parser.of(compiled, options));
}
