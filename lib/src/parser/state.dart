part of 'session.dart';

/// What a [_Link] advances over: a token edge or a completed constituent.
sealed class _Child {}

/// A token edge of the graph.
final class _Token extends _Child {
  _Token(this.edge);

  final Edge edge;
}

/// One derivation of a state: [previous] is the state with the dot one
/// place earlier, and [child] the token or constituent it advanced over. A
/// predicted state has no links.
typedef _Link = ({_State previous, _Child child});

/// Whether two children are the same token edge or the same constituent.
bool _same(_Child left, _Child right) =>
    identical(left, right) ||
    left is _Token && right is _Token && identical(left.edge, right.edge);

/// The identity of a state within its end vertex (PAR-2, S-P9): the
/// production, dot and origin, and the variable bindings and visible labels
/// as entries sorted by name.
final class _Key {
  _Key(this.production, this.dot, this.origin, this.bindings, this.labels)
    : hashCode = Object.hash(
        production,
        dot,
        origin,
        Object.hashAll(bindings),
        Object.hashAll(labels),
      );

  final int production;
  final int dot;
  final int origin;
  final List<(String, Value)> bindings;
  final List<(String, Value)> labels;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) =>
      other is _Key &&
      hashCode == other.hashCode &&
      production == other.production &&
      dot == other.dot &&
      origin == other.origin &&
      _entries(bindings, other.bindings) &&
      _entries(labels, other.labels);

  static bool _entries(
    List<(String, Value)> left,
    List<(String, Value)> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

/// [values] as entries sorted by name.
List<(String, Value)> _sorted(Map<String, Value> values) => [
  for (final name in values.keys.toList()..sort()) (name, values[name]!),
];

/// Whether [value] holds a variable; iterative, for deep values.
bool _variable(Value value) {
  final stack = [value];
  while (stack.isNotEmpty) {
    switch (stack.removeLast()) {
      case Variable():
        return true;
      case final Structure structure:
        for (final key in structure.keys) {
          stack.add(structure.get(key)!);
        }
      case Binding(:final features):
        stack.add(features);
      default:
        break;
    }
  }
  return false;
}

/// Whether [name] was renamed apart (S-F5).
bool _renamed(String name) => name.contains("'");

/// A chart state: a production with a dot, spanning [origin] to [end].
/// States with equal keys at one end vertex are equivalent for every future
/// operation; of these only the cheapest is kept, and equally cheap ones
/// become further [links] (packed derivations).
final class _State extends _Child {
  _State(
    this.production,
    this.dot,
    this.origin,
    this.end,
    this.bindings,
    Map<String, Value> labels,
    this.start,
    this.penalty,
  ) : labels = Map.unmodifiable(labels);

  final Production production;
  final int dot;
  final Vertex origin;
  final Vertex end;

  /// The variable bindings of this use of the production (S-F5).
  final Bindings bindings;

  /// The bindings of the labels the production's constraints read.
  final Map<String, Value> labels;

  /// The offset of the first token consumed, or -1 while none has been.
  final int start;

  final links = <_Link>[];

  /// For a complete state, the constituent's features.
  Structure features = Structure.empty;

  /// The total penalty: children, tokens, and for a complete state its own.
  int penalty;

  /// For a complete state, its production cost.
  int own = 0;

  bool superseded = false;

  /// The state's identity. Canonically (S-P9), the production's own
  /// variables are kept by name, each value and each visible label is fully
  /// substituted, and renamed-apart variables are numbered by first
  /// occurrence, which keeps which of them are shared. Renamed-apart
  /// variables that no production variable or label reaches cannot affect
  /// this use of the production and are left out. Raw keys compare the
  /// bindings as they are, for testing.
  _Key key(bool canonical) {
    if (!canonical || _plain) {
      return _Key(
        production.id,
        dot,
        origin.id,
        _sorted(bindings.values),
        _sorted(labels),
      );
    }
    final names = <String, String>{};
    Value rename(Value value) => Values.rename(
      Unifier.substitute(value, bindings),
      (variable) => _renamed(variable.name)
          ? Variable(names.putIfAbsent(variable.name, () => "'${names.length}"))
          : variable,
    );
    return _Key(
      production.id,
      dot,
      origin.id,
      [
        for (final (name, value) in _sorted(bindings.values))
          if (!_renamed(name)) (name, rename(value)),
      ],
      [for (final (name, value) in _sorted(labels)) (name, rename(value))],
    );
  }

  /// Whether the raw bindings are already canonical: no label is visible, no
  /// binding is for a renamed-apart variable, and no bound value holds a
  /// variable to substitute or rename.
  bool get _plain =>
      labels.isEmpty &&
      bindings.values.entries.every(
        (entry) => !_renamed(entry.key) && !_variable(entry.value),
      );

  bool get complete => dot == production.rhs.length;

  Element get next => production.rhs[dot];

  String get symbol => production.symbol;
}
