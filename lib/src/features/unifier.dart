/// Unification of feature values (S-F1, S-F2).
library;

import '../result.dart';
import 'value.dart';

/// An immutable set of variable bindings produced by unification.
/// Operations that add a binding return a new instance.
final class Bindings {
  /// Bindings holding a copy of [values].
  Bindings(Map<String, Value> values) : values = Map.unmodifiable(values);

  const Bindings._(this.values);

  /// No bindings.
  static const empty = Bindings._({});

  /// Variable name to bound value.
  final Map<String, Value> values;

  /// The value bound to [name], or null if it is unbound.
  Value? get(String name) => values[name];

  /// New bindings with [name] bound to [value].
  Bindings plus(String name, Value value) => Bindings({...values, name: value});

  /// Whether nothing is bound.
  bool get isEmpty => values.isEmpty;

  @override
  String toString() => 'Bindings($values)';
}

/// A successful unification: the unified [value] with every bound variable
/// substituted, and the [bindings] that produced it (S-F1).
final class Unification<T extends Value> {
  /// A unification of [value] under [bindings].
  const Unification(this.value, this.bindings);

  /// The unified value.
  final T value;

  /// The bindings after unification.
  final Bindings bindings;
}

/// Unification for feature values: the most general value both inputs
/// subsume.
///
/// Every entry point shares one implementation and returns the unified value
/// with all bound variables substituted, together with the resulting
/// [Bindings] (S-F1). A failure carries the reason in its [ErrorDetails],
/// with code `unification.mismatch` or `unification.occurs`.
///
/// Unification runs in two passes, both iterative so that deeply nested
/// structures cannot overflow the stack: [_bind] walks pairs of values with an
/// explicit work stack and records variable bindings, then [_build]
/// constructs the merged, fully substituted result bottom-up.
abstract final class Unifier {
  static const _mismatch = 'unification.mismatch';
  static const _circular = 'unification.occurs';

  /// Unifies two values under [bindings].
  static Result<Unification<Value>, ErrorDetails> unify(
    Value left,
    Value right, [
    Bindings bindings = Bindings.empty,
  ]) {
    final working = {...bindings.values};
    final failure = _bind(left, right, working);
    if (failure != null) {
      return Failure(failure);
    }
    return Success(
      Unification(_build(left, right, working), Bindings(working)),
    );
  }

  /// Unifies two feature structures under [bindings].
  static Result<Unification<Structure>, ErrorDetails> structures(
    Structure left,
    Structure right, [
    Bindings bindings = Bindings.empty,
  ]) => unify(left, right, bindings).map(
    (unification) =>
        Unification(unification.value as Structure, unification.bindings),
  );

  /// [value] with every variable bound in [bindings] substituted.
  static Value substitute(Value value, Bindings bindings) =>
      _build(value, null, bindings.values);

  /// First pass: unifies [left] with [right], adding variable bindings to
  /// [bindings]. Returns null on success, or the reason for failure.
  static ErrorDetails? _bind(
    Value left,
    Value right,
    Map<String, Value> bindings,
  ) {
    final stack = <(Value, Value, String)>[(left, right, '')];
    while (stack.isNotEmpty) {
      final (one, two, path) = stack.removeLast();
      final first = _deref(one, bindings);
      final second = _deref(two, bindings);
      if (first is Variable && second is Variable) {
        if (first.name != second.name) {
          bindings[first.name] = second;
        }
      } else if (first is Variable) {
        if (_occurs(first, second, bindings)) {
          return _failure(
            _circular,
            path,
            'Occurs check failed: $first occurs in $second',
          );
        }
        bindings[first.name] = second;
      } else if (second is Variable) {
        if (_occurs(second, first, bindings)) {
          return _failure(
            _circular,
            path,
            'Occurs check failed: $second occurs in $first',
          );
        }
        bindings[second.name] = first;
      } else if (first.isAtomic && second.isAtomic) {
        // Value equality: numbers compare by mathematical value (S-F4), and a
        // string never equals a number or boolean with the same display.
        if (first != second) {
          return _failure(
            _mismatch,
            path,
            "Values don't match: $first vs $second",
          );
        }
      } else {
        final a = _features(first);
        final b = _features(second);
        if (a == null || b == null) {
          return _failure(
            _mismatch,
            path,
            'Type mismatch: ${_kind(first)} vs ${_kind(second)}',
          );
        }
        for (final key in a.keys) {
          if (b.has(key)) {
            stack.add((
              a.get(key)!,
              b.get(key)!,
              path.isEmpty ? key : '$path.$key',
            ));
          }
        }
      }
    }
    return null;
  }

  static ErrorDetails _failure(String code, String path, String message) =>
      ErrorDetails.of(
        code,
        path.isEmpty ? message : "Feature '$path': $message",
      );

  /// The class name of [value], spelled out so it is the same on every
  /// platform (dart2js minifies runtime type names).
  static String _kind(Value value) => switch (value) {
    StringConstant() => 'StringConstant',
    NumericConstant() => 'NumericConstant',
    BooleanConstant() => 'BooleanConstant',
    Variable() => 'Variable',
    FeaturePath() => 'FeaturePath',
    Binding() => 'Binding',
    Structure() => 'Structure',
  };

  /// Second pass: the merge of [left] and [right] (either may be null) with
  /// every bound variable substituted. Assumes [_bind] succeeded for the
  /// pair, so wherever both sides are present they are compatible. With
  /// [right] null this is plain substitution.
  static Value _build(Value? left, Value? right, Map<String, Value> bindings) {
    final root = _open(left, right, bindings);
    if (root is! _Frame) {
      return root as Value;
    }
    final stack = <_Frame>[root];
    Value? finished;
    while (true) {
      final frame = stack.last;
      if (finished != null) {
        frame.builder.put(frame.keys[frame.index - 1], finished);
        finished = null;
      }
      if (frame.index == frame.keys.length) {
        stack.removeLast();
        finished = frame.finish();
        if (stack.isEmpty) {
          return finished;
        }
        continue;
      }
      final key = frame.keys[frame.index++];
      final next = _open(frame.left.get(key), frame.right?.get(key), bindings);
      if (next is _Frame) {
        stack.add(next);
      } else {
        frame.builder.put(key, next as Value);
      }
    }
  }

  /// Either the finished value for a pair, or a [_Frame] when it is a
  /// structure to build.
  static Object _open(Value? left, Value? right, Map<String, Value> bindings) {
    final a = left == null ? null : _deref(left, bindings);
    final b = right == null ? null : _deref(right, bindings);
    if (a == null || b == null) {
      return switch (a ?? b!) {
        final Structure structure => _Frame(structure, null, null),
        final Binding binding => _Frame(binding.features, null, binding.text),
        final Value single => single,
      };
    }
    final fa = _features(a);
    final fb = _features(b);
    // Two feature-bearing values merge into a plain structure; anything else
    // is already equal.
    return fa != null && fb != null ? _Frame(fa, fb, null) : a;
  }

  /// The feature structure of a structure or a constituent binding, or null
  /// for other values.
  static Structure? _features(Value value) => switch (value) {
    final Structure structure => structure,
    final Binding binding => binding.features,
    _ => null,
  };

  static Value _deref(Value value, Map<String, Value> bindings) {
    var current = value;
    while (current is Variable) {
      final bound = bindings[current.name];
      if (bound == null) {
        break;
      }
      current = bound;
    }
    return current;
  }

  /// Occurs check: true if [variable] appears in [value], including inside
  /// bindings (S-F2).
  static bool _occurs(
    Variable variable,
    Value value,
    Map<String, Value> bindings,
  ) {
    final stack = <Value>[value];
    while (stack.isNotEmpty) {
      final current = _deref(stack.removeLast(), bindings);
      if (current is Variable) {
        if (current.name == variable.name) {
          return true;
        }
        continue;
      }
      final structure = _features(current);
      if (structure != null) {
        for (final key in structure.keys) {
          stack.add(structure.get(key)!);
        }
      }
    }
    return false;
  }
}

/// A structure under construction in the second pass of unification.
final class _Frame {
  _Frame(this.left, this.right, this.text)
    : keys = [
        ...left.keys,
        if (right != null)
          for (final key in right.keys)
            if (!left.has(key)) key,
      ];

  final Structure left;
  final Structure? right;
  final String? text;
  final List<String> keys;
  final builder = Structure.builder();
  var index = 0;

  Value finish() {
    final structure = builder.build();
    final label = text;
    return label == null ? structure : Binding(label, structure);
  }
}

/// Conversions between string-based and structured feature representations.
abstract final class Utilities {
  /// A structure from a string map. Strings starting with `?` become
  /// variables, `true` and `false` (ignoring case) booleans, numeric strings
  /// numbers, and all other strings string constants. Null values are
  /// skipped.
  static Structure fromMap(Map<String, String?> map) {
    final builder = Structure.builder();
    for (final MapEntry(:key, :value) in map.entries) {
      if (value != null) {
        builder.put(key, _parse(value));
      }
    }
    return builder.build();
  }

  static Value _parse(String value) {
    if (value.isEmpty) {
      return const StringConstant('');
    }
    if (value.startsWith('?')) {
      return Variable(value.substring(1));
    }
    if (BooleanConstant.isBoolean(value)) {
      return BooleanConstant.parse(value).orElseThrow();
    }
    // A numeric literal outside the platform's range stays a string.
    return switch (NumericConstant.parse(value)) {
      Success(:final value) => value,
      Failure() => StringConstant(value),
    };
  }

  /// [value] as a plain string for components that expect string features:
  /// variables with a leading `?`, structures by their display. Null for
  /// null.
  static String? valueToString(Value? value) => switch (value) {
    null => null,
    StringConstant(:final value) => value,
    NumericConstant(:final value) => '$value',
    BooleanConstant(:final value) => '$value',
    Variable(:final name) => '?$name',
    _ => value.display(),
  };
}
