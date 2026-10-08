part of 'predicates.dart';

/// The immutable environment one constraint evaluation runs in: the
/// predicate registry, label and variable bindings, and, during lexing only,
/// the lexical state stack and character position. Operations that add
/// information return a new environment.
final class Environment {
  Environment._(
    this.predicates,
    Map<String, Value> bindings,
    List<String> states,
    this.position,
  ) : _bindings = Map.unmodifiable(bindings),
      states = List.unmodifiable(states);

  /// An environment with no bindings, in the initial lexical state.
  factory Environment.of(Predicates predicates) =>
      Environment._(predicates, const {}, const ['DEFAULT'], 0);

  /// The binding holding where the constituent being checked starts, as a
  /// structure with one feature per position (S-C7): during parsing, the
  /// token index of every path that reaches its start node; during lexing,
  /// the offset where the token starts. No grammar identifier can name it.
  /// Java's `Environment.POSITION`.
  static const origin = '@position';

  /// The binding that is true when the constituent being checked ends at the
  /// end of the input.
  static const end = '@end';

  /// The binding holding the categories of the tokens that follow the
  /// constituent being checked, as a structure with one feature per
  /// category.
  static const next = '@next';

  /// The predicate registry.
  final Predicates predicates;

  final Map<String, Value> _bindings;

  /// The lexical state stack, bottom to top; never empty.
  final List<String> states;

  /// The character position being lexed.
  final int position;

  /// A new environment with [name] bound to [value].
  Environment plus(String name, Value value) =>
      Environment._(predicates, {..._bindings, name: value}, states, position);

  /// A new environment with every binding in [values] added; later entries
  /// replace earlier ones.
  Environment merge(Map<String, Value> values) =>
      Environment._(predicates, {..._bindings, ...values}, states, position);

  /// A new environment for lexing at [position] with the state stack
  /// [states], listed from bottom to top. The stack is never empty.
  Environment lexical(List<String> states, int position) {
    if (states.isEmpty) {
      throw ArgumentError.value(
        states,
        'states',
        'the state stack is never empty',
      );
    }
    return Environment._(predicates, _bindings, states, position);
  }

  /// The value bound to [name], or null.
  Value? get(String name) => _bindings[name];

  /// The current lexical state: the top of the stack.
  String get state => states.last;

  /// Resolves a predicate argument (S-C11): a variable to its binding, a
  /// feature path to the value it names (through constituent bindings and
  /// structures), anything else to itself. Null for an unbound variable or a
  /// path that leads nowhere.
  Value? resolve(Value value) => switch (value) {
    Variable(:final name) => _bindings[name],
    final FeaturePath path => _lookup(path),
    _ => value,
  };

  Value? _lookup(FeaturePath path) {
    var current = _bindings[path.root];
    for (final feature in path.path) {
      current = switch (current) {
        final Binding binding => binding.features.get(feature),
        final Structure structure => structure.get(feature),
        _ => null,
      };
      if (current == null) {
        return null;
      }
    }
    return current;
  }

  /// Evaluates a predicate [call] in this environment.
  bool test(Call call) => predicates._test(this, call);
}
