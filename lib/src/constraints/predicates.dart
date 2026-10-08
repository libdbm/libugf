/// The predicate registry and the environment constraints are evaluated in.
library;

import '../arithmetic.dart';
import '../features/unifier.dart';
import '../features/value.dart';
import '../patterns.dart';
import '../result.dart';
import 'expression.dart';

part 'builtins.dart';
part 'environment.dart';
part 'lexical.dart';

/// When a predicate can be evaluated.
enum Phase {
  /// Only during lexing: needs the lexical state stack or character position
  /// (S-C7).
  lexical,

  /// Whenever bindings are available: during parsing, or during lexing for
  /// literals.
  syntactic,

  /// During parsing, reading the constituent's position ([Environment.origin],
  /// [Environment.end], [Environment.next]) as well as the arguments. Results
  /// are never reused between constituents.
  positional,
}

/// A predicate implementation: deterministic, and true or false (S-C8).
/// Apart from [Phase.lexical] and [Phase.positional] predicates, the result
/// depends only on the arguments.
///
/// A grammar's predicates are trusted and run without isolation (S-T1): a
/// check returns false for arguments it rejects, and an exception it throws
/// is not caught, so it propagates out of parsing or lexing.
typedef Check = bool Function(Environment environment, List<Value> args);

/// A registered predicate.
final class Entry {
  /// The predicate [name], accepting [minimum] to [maximum] arguments, in
  /// [phase], implemented by [check].
  Entry(this.name, this.minimum, this.maximum, this.phase, this.check) {
    if (minimum < 0 || maximum < minimum) {
      throw ArgumentError('invalid arity $minimum..$maximum for $name');
    }
  }

  /// The [maximum] of a predicate that takes any number of arguments.
  static const unlimited = 0x7fffffff;

  /// The predicate name.
  final String name;

  /// The fewest arguments accepted.
  final int minimum;

  /// The most arguments accepted, [unlimited] for no limit.
  final int maximum;

  /// When the predicate can be evaluated.
  final Phase phase;

  /// The implementation.
  final Check check;

  /// Whether a call with [count] arguments is valid.
  bool accepts(int count) => count >= minimum && count <= maximum;
}

/// An immutable registry of the predicates a grammar may call. Each entry
/// records a name, an accepted argument count, the phase in which it can be
/// evaluated, and its implementation. Predicates must be pure and
/// deterministic.
///
/// The registry is fixed when a grammar is compiled, which lets the compiler
/// reject unknown names and wrong arities (S-C8); at runtime every call
/// therefore finds its entry.
final class Predicates {
  Predicates._(Map<String, Entry> entries)
    : _entries = Map.unmodifiable(entries);

  final Map<String, Entry> _entries;

  /// A builder for a registry.
  static PredicatesBuilder builder() => PredicatesBuilder._();

  /// The standard registry: the lexical predicates and every builtin.
  static Predicates standard() => builder().lexical().builtins().build();

  /// The entry for [name], or null if no such predicate is registered.
  Entry? entry(String name) => _entries[name];

  /// The names of every predicate in [phase].
  Set<String> names(Phase phase) => {
    for (final entry in _entries.values)
      if (entry.phase == phase) entry.name,
  };

  /// Evaluates [call]. An unregistered name is a programming error, because
  /// compilation rejects grammars that call unknown predicates.
  bool _test(Environment environment, Call call) {
    final entry = _entries[call.name];
    if (entry == null) {
      throw StateError('Unregistered predicate: ${call.name}');
    }
    return entry.check(environment, call.args);
  }
}

/// Builds a [Predicates] registry. A later registration of the same name
/// replaces the earlier one.
final class PredicatesBuilder {
  PredicatesBuilder._();

  final _entries = <String, Entry>{};

  /// Registers the predicate [name] with its arity, [phase] and [check].
  PredicatesBuilder add(
    String name,
    int minimum,
    int maximum,
    Phase phase,
    Check check,
  ) {
    _entries[name] = Entry(name, minimum, maximum, phase, check);
    return this;
  }

  /// Adds the builtin predicates (string, feature, equality, numeric and
  /// token position).
  PredicatesBuilder builtins() {
    _Builtins.register(this);
    return this;
  }

  /// Adds the lexical state and character position predicates.
  PredicatesBuilder lexical() {
    _Lexical.register(this);
    return this;
  }

  /// The registry built so far.
  Predicates build() => Predicates._(_entries);
}
