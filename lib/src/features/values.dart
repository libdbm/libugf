/// Traversals over feature values that need no recursion, so deep values
/// cannot exhaust the stack.
library;

import 'value.dart';

/// Traversals over feature values.
abstract final class Values {
  /// [value] with every variable replaced by [rename]'s result.
  ///
  /// Structure features are visited in sorted order (by UTF-16 code unit), so
  /// a renaming that numbers variables by first occurrence is deterministic,
  /// and constituent bindings are entered through their features. Unchanged
  /// parts are returned as the same instances.
  static Value rename(Value value, Variable Function(Variable) rename) {
    if (value is! Structure && value is! Binding) {
      return _leaf(value, rename);
    }
    final stack = <_Frame>[_Frame(value)];
    Value? finished;
    while (true) {
      final frame = stack.last;
      if (finished != null) {
        frame.accept(finished);
        finished = null;
      }
      if (frame.done) {
        stack.removeLast();
        finished = frame.finish();
        if (stack.isEmpty) {
          return finished;
        }
        continue;
      }
      final child = frame.next;
      if (child is Structure || child is Binding) {
        stack.add(_Frame(child));
      } else {
        frame.accept(_leaf(child, rename));
      }
    }
  }

  static Value _leaf(Value value, Variable Function(Variable) rename) =>
      value is Variable ? rename(value) : value;
}

/// A structure or binding being rebuilt: its children in order and their
/// renamed results.
final class _Frame {
  _Frame(this.source)
    : keys = switch (source) {
        final Structure structure => structure.keys.toList()..sort(),
        _ => const [],
      } {
    switch (source) {
      case final Structure structure:
        children.addAll([for (final key in keys) structure.get(key)!]);
      case final Binding binding:
        children.add(binding.features);
      default:
        throw ArgumentError.value(
          source,
          'source',
          'not a structure or binding',
        );
    }
  }

  final Value source;
  final List<String> keys;
  final children = <Value>[];
  final results = <Value>[];
  var changed = false;

  bool get done => results.length == children.length;

  Value get next => children[results.length];

  void accept(Value result) {
    changed = changed || !identical(result, children[results.length]);
    results.add(result);
  }

  Value finish() {
    if (!changed) {
      return source;
    }
    if (source case final Binding binding) {
      return Binding.of(binding.text, results.first as Structure);
    }
    final builder = Structure.builder();
    for (var index = 0; index < keys.length; index++) {
      builder.put(keys[index], results[index]);
    }
    return builder.build();
  }
}
