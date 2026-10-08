/// Diagnostics of a parse: why an input failed, and where a parse was
/// ambiguous.
library;

import '../features/value.dart';

/// The character span of a token or column: [index] is the lattice column
/// (vertex id), [start] and [end] absolute offsets in the input.
final class Span {
  /// A span over column [index] from offset [start] to [end].
  const Span(this.index, this.start, this.end);

  /// The lattice column: the token graph vertex id.
  final int index;

  /// The offset of the first character.
  final int start;

  /// The offset just past the last character.
  final int end;

  @override
  bool operator ==(Object other) =>
      other is Span &&
      index == other.index &&
      start == other.start &&
      end == other.end;

  @override
  int get hashCode => Object.hash(index, start, end);

  @override
  String toString() => 'Span($index, $start..$end)';
}

/// A required constraint that failed during parsing.
final class ConstraintFailure {
  /// A failure of [expression] in a production of [rule].
  const ConstraintFailure(
    this.rule,
    this.expression,
    this.reason,
    this.position, {
    this.hard = true,
    this.span,
  });

  /// The symbol of the production whose constraint failed.
  final String rule;

  /// The failed constraint, as grammar text.
  final String expression;

  /// Why it failed.
  final String reason;

  /// The vertex id where the production began.
  final int position;

  /// Whether the constraint was required; false for a soft one.
  final bool hard;

  /// The text the production covered, if known.
  final Span? span;
}

/// Text the lexer could not tokenize.
final class TokenizationError {
  /// Text at [position] that the lexer could not tokenize.
  const TokenizationError(
    this.position,
    this.input,
    this.expected, [
    this.span,
  ]);

  /// The offset of the text.
  final int position;

  /// The text.
  final String input;

  /// What the lexer expected there.
  final String expected;

  /// The span of the text, if known.
  final Span? span;
}

/// A general parsing issue.
final class ParsingIssue {
  /// An issue described by [message].
  const ParsingIssue(this.message, this.position, [this.span]);

  /// The issue.
  final String message;

  /// The vertex id where it arose.
  final int position;

  /// Where it arose, if known.
  final Span? span;
}

/// A child whose features did not unify with those written on its element.
final class UnificationFailure {
  /// A failure to unify a completed [symbol] with its element.
  const UnificationFailure(
    this.symbol,
    this.waiting,
    this.completed,
    this.expected,
    this.reason,
    this.position, [
    this.span,
  ]);

  /// The symbol of the completed child.
  final String symbol;

  /// The features of the production waiting for the child.
  final Structure waiting;

  /// The completed child's features.
  final Structure completed;

  /// The features written on the element.
  final Structure expected;

  /// Why unification failed.
  final String reason;

  /// The vertex id where the child ended.
  final int position;

  /// The text the child covered, if known.
  final Span? span;
}

/// A constituent that two derivations reached at the same penalty; the
/// [readings] sketch each competing derivation.
final class Ambiguity {
  /// An ambiguity of [symbol] over [span]; [readings] is copied.
  Ambiguity(this.symbol, this.span, [List<String> readings = const []])
    : readings = List.unmodifiable(readings);

  /// The ambiguous symbol.
  final String symbol;

  /// The text it covers.
  final Span span;

  /// A sketch of each competing derivation; possibly empty.
  final List<String> readings;
}

/// The state of a lattice item when the snapshot was taken.
enum ItemState {
  /// The item is waiting for its next element.
  active,

  /// The item has advanced over all its elements.
  complete,

  /// A required constraint rejected the item.
  rejected,
}

/// Why a candidate path failed to produce a parse (Java `FailureKind`).
enum Cause {
  /// A complete parse exists but its symbol is not the start symbol.
  wrongStart('WRONG_START'),

  /// The candidate failed a required constraint.
  constraint('CONSTRAINT'),

  /// Unification between the waiting and completed items failed.
  unification('UNIFICATION'),

  /// A partial parse waited for a symbol that never arrived.
  deadEnd('DEAD_END'),

  /// A duplicate item was dropped because a cheaper path existed.
  dropped('DROPPED');

  const Cause(this.label);

  /// The name in a rendered lattice, as Java prints it.
  final String label;
}

/// One chart item in a lattice snapshot.
final class LatticeItem {
  /// An item of [rule] with the dot at [dot], begun at [origin].
  const LatticeItem(
    this.rule,
    this.dot,
    this.origin,
    this.penalty,
    this.state,
    this.features,
  );

  /// The production, as `symbol --> elements`.
  final String rule;

  /// The number of elements the item has advanced over.
  final int dot;

  /// The vertex id where the item began.
  final int origin;

  /// The item's penalty, exact to 64 bits (S-C10).
  final int penalty;

  /// The state of the item.
  final ItemState state;

  /// The bindings of an active item, or the features of a complete one.
  final String features;
}

/// A reason a path did not succeed, for one lattice item.
final class PathFailure {
  /// A failure of [item], for [reason], of kind [cause].
  const PathFailure(this.item, this.span, this.reason, this.cause);

  /// The item whose path failed.
  final LatticeItem item;

  /// Where it failed, if known.
  final Span? span;

  /// Why it failed.
  final String reason;

  /// The kind of failure.
  final Cause cause;
}

/// One column of the lattice: the items at a chart position, the elements
/// active items expected next, and the failures of paths there.
final class Column {
  /// Column [index]; the lists are copied.
  Column(
    this.index,
    this.span,
    List<LatticeItem> items,
    List<String> expected,
    List<PathFailure> failures,
  ) : items = List.unmodifiable(items),
      expected = List.unmodifiable(expected),
      failures = List.unmodifiable(failures);

  /// The token graph vertex id.
  final int index;

  /// The text of the column, if known.
  final Span? span;

  /// The items ending at this column.
  final List<LatticeItem> items;

  /// The elements the active items expected next.
  final List<String> expected;

  /// The failures of paths at this column.
  final List<PathFailure> failures;
}

/// The chart when a parse was rejected (Java `ParseLattice`): its columns,
/// the [furthest] column with progress and its [position], and whether the
/// diagnostics limit cut the snapshot short.
final class Lattice {
  /// A lattice of [columns], which is copied.
  Lattice(
    List<Column> columns,
    this.furthest,
    this.position, {
    this.truncated = false,
  }) : columns = List.unmodifiable(columns);

  /// The columns, from the furthest back to the start.
  final List<Column> columns;

  /// The column of the furthest progress.
  final int furthest;

  /// The text at the furthest progress, if known.
  final Span? position;

  /// Whether the diagnostics limit cut the snapshot short.
  final bool truncated;

  /// Every path failure, across all columns.
  List<PathFailure> get failures =>
      List.unmodifiable([for (final column in columns) ...column.failures]);

  /// The lattice as a section of a diagnostic report.
  String render() {
    final out = StringBuffer('=== Parse Lattice ===\n');
    out.writeln(switch (position) {
      final Span span =>
        'Furthest progress: column $furthest (chars ${span.start}..${span.end})',
      null => 'Furthest progress: column $furthest',
    });
    if (truncated) {
      out.writeln('(truncated at the diagnostics limit)');
    }
    for (final column in columns) {
      out.write('Column ${column.index}');
      if (column.span case final span?) {
        out.write(' (chars ${span.start}..${span.end})');
      }
      out.writeln(':');
      if (column.expected.isNotEmpty) {
        out.writeln('  expected: ${column.expected.join(', ')}');
      }
      for (final item in column.items) {
        out.writeln(
          '  ${item.state.name}: ${item.rule} → dot=${item.dot} '
          'origin=${item.origin} pen=${item.penalty}',
        );
      }
      for (final failure in column.failures) {
        final location = switch (failure.span) {
          final Span span => 'chars ${span.start}..${span.end}',
          null => 'column ${column.index}',
        };
        out.writeln(
          '  failure [${failure.cause.label}] at $location: '
          '${failure.item.rule} (${failure.reason})',
        );
      }
    }
    out.writeln();
    return out.toString();
  }
}

/// The diagnostics of one parse, when `Options.diagnostics` is on: why it
/// failed and where it was ambiguous. A rejected parse also holds the chart
/// as a [Lattice].
final class ParseDiagnostics {
  final _constraints = <ConstraintFailure>[];
  final _tokenizations = <TokenizationError>[];
  final _issues = <ParsingIssue>[];
  final _unifications = <UnificationFailure>[];
  final _ambiguities = <Ambiguity>[];

  /// The chart when the parse was rejected, or null.
  Lattice? lattice;

  /// The required constraints that failed, in the order found.
  List<ConstraintFailure> get constraints => List.unmodifiable(_constraints);

  /// The text the lexer could not tokenize, in the order found.
  List<TokenizationError> get tokenizations =>
      List.unmodifiable(_tokenizations);

  /// General issues, in the order found.
  List<ParsingIssue> get issues => List.unmodifiable(_issues);

  /// The unification failures, in the order found.
  List<UnificationFailure> get unifications => List.unmodifiable(_unifications);

  /// Every constituent at which two derivations tied, in the order found.
  List<Ambiguity> get ambiguities => List.unmodifiable(_ambiguities);

  /// Records a constraint failure.
  void recordConstraint(ConstraintFailure failure) => _constraints.add(failure);

  /// Records a tokenization error.
  void recordTokenization(TokenizationError error) => _tokenizations.add(error);

  /// Records a general issue.
  void recordIssue(ParsingIssue issue) => _issues.add(issue);

  /// Records a unification failure.
  void recordUnification(UnificationFailure failure) =>
      _unifications.add(failure);

  /// Records an ambiguity.
  void recordAmbiguity(Ambiguity ambiguity) => _ambiguities.add(ambiguity);

  /// Whether any failure was recorded.
  bool get hasFailures =>
      _constraints.isNotEmpty ||
      _tokenizations.isNotEmpty ||
      _issues.isNotEmpty ||
      _unifications.isNotEmpty ||
      lattice != null;

  static String _describe(int position, Span? span) => span == null
      ? 'position $position'
      : 'column $position (token #${span.index}, chars ${span.start}..${span.end})';

  /// A readable report of everything recorded.
  String report() {
    final out = StringBuffer();
    if (_constraints.isNotEmpty) {
      out.writeln('=== Constraint Failures ===');
      for (final failure in _constraints) {
        out
          ..writeln(
            '  [${failure.hard ? 'HARD' : 'SOFT'}] Rule \'${failure.rule}\' at '
            '${_describe(failure.position, failure.span)}: ${failure.reason}',
          )
          ..writeln('    Constraint: ${failure.expression}');
      }
      out.writeln();
    }
    if (_tokenizations.isNotEmpty) {
      out.writeln('=== Tokenization Errors ===');
      for (final error in _tokenizations) {
        out.writeln(
          '  ${_describe(error.position, error.span)}: ${error.input} '
          '(expected: ${error.expected})',
        );
      }
      out.writeln();
    }
    if (_issues.isNotEmpty) {
      out.writeln('=== Parsing Issues ===');
      for (final issue in _issues) {
        out.writeln(
          '  ${_describe(issue.position, issue.span)}: ${issue.message}',
        );
      }
      out.writeln();
    }
    if (_unifications.isNotEmpty) {
      out.writeln('=== Feature Unification Failures ===');
      for (final failure in _unifications) {
        out
          ..writeln(
            '  ${_describe(failure.position, failure.span)}: Symbol '
            '\'${failure.symbol}\' - ${failure.reason}',
          )
          ..writeln('    Expected: ${failure.expected.display()}')
          ..writeln('    Waiting:  ${failure.waiting.display()}')
          ..writeln('    Completed: ${failure.completed.display()}');
      }
      out.writeln();
    }
    if (_ambiguities.isNotEmpty) {
      out.writeln('=== Ambiguities ===');
      for (final ambiguity in _ambiguities) {
        out.writeln(
          '  \'${ambiguity.symbol}\' has more than one derivation at '
          '${_describe(ambiguity.span.index, ambiguity.span)}',
        );
        for (final reading in ambiguity.readings) {
          out.writeln('    reading: $reading');
        }
      }
      out.writeln();
    }
    if (lattice case final snapshot?) {
      out.write(snapshot.render());
    }
    if (!hasFailures) {
      out.writeln('No failures recorded.');
    }
    return out.toString();
  }
}
