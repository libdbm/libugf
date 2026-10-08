part of 'value.dart';

/// An immutable feature structure: a map from feature names to feature
/// values, which can be atomic, variables, or other structures.
///
/// Instances are built with [builder] or [Structure.of], or derived with
/// [plus]; nothing changes a structure after construction, so structures may
/// be shared freely. Because a structure can only contain values that already
/// exist, it cannot contain itself (S-F3). Equality, hashing and display do
/// not recurse, so deeply nested structures cannot overflow the stack.
final class Structure extends Value {
  Structure._(Map<String, Value> features)
    : _features = Map.unmodifiable(features);

  /// A structure holding a copy of [features].
  factory Structure.of(Map<String, Value> features) => Structure._(features);

  /// The empty structure.
  static final empty = Structure._(const {});

  /// A builder, pre-populated with the features of [base] if given. The base
  /// is not changed.
  static StructureBuilder builder([Structure? base]) =>
      StructureBuilder._({...?base?._features});

  final Map<String, Value> _features;

  /// The cached hash, computed once, bottom-up.
  int? _hash;

  /// A new structure equal to this one with [feature] set to [value]. This
  /// structure is not changed.
  Structure plus(String feature, Value value) =>
      Structure._({..._features, feature: value});

  /// The value of [feature], or null if it is absent.
  Value? get(String feature) => _features[feature];

  /// The value of [feature], or null if it is absent.
  Value? operator [](String feature) => _features[feature];

  /// Whether [feature] is present.
  bool has(String feature) => _features.containsKey(feature);

  /// The feature names, as an unmodifiable set.
  Set<String> get keys => Set.unmodifiable(_features.keys);

  /// The number of features.
  int get size => _features.length;

  /// Whether there are no features.
  bool get isEmpty => _features.isEmpty;

  /// Whether there is at least one feature.
  bool get isNotEmpty => _features.isNotEmpty;

  @override
  bool get isVariable => false;

  @override
  bool get isAtomic => false;

  @override
  String display() {
    final out = StringBuffer();
    final stack = <Object>[this];
    while (stack.isNotEmpty) {
      switch (stack.removeLast()) {
        case final String text:
          out.write(text);
        case final Structure structure when structure._features.isEmpty:
          out.write('{}');
        case final Structure structure:
          final parts = <Object>['{'];
          var first = true;
          for (final MapEntry(:key, :value) in structure._features.entries) {
            if (!first) {
              parts.add(', ');
            }
            parts
              ..add('$key: ')
              ..add(value);
            first = false;
          }
          parts.add('}');
          stack.addAll(parts.reversed);
        case final Value value:
          out.write(value.display());
      }
    }
    return out.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! Structure) {
      return false;
    }
    final stack = <(Structure, Structure)>[(this, other)];
    while (stack.isNotEmpty) {
      final (left, right) = stack.removeLast();
      if (identical(left, right)) {
        continue;
      }
      if (left._features.length != right._features.length) {
        return false;
      }
      for (final MapEntry(:key, value: a) in left._features.entries) {
        final b = right._features[key];
        if (b == null) {
          return false;
        }
        if (a is Structure && b is Structure) {
          stack.add((a, b));
        } else if (a != b) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  int get hashCode {
    final cached = _hash;
    if (cached != null) {
      return cached;
    }
    final stack = <Structure>[this];
    while (stack.isNotEmpty) {
      final top = stack.last;
      if (top._hash != null) {
        stack.removeLast();
        continue;
      }
      var ready = true;
      for (final value in top._features.values) {
        if (value is Structure && value._hash == null) {
          stack.add(value);
          ready = false;
        }
      }
      if (ready) {
        stack.removeLast();
        // Order-independent, as feature order is not part of equality.
        var computed = 31;
        for (final MapEntry(:key, :value) in top._features.entries) {
          computed = (computed + (key.hashCode ^ value.hashCode)) & 0x3fffffff;
        }
        top._hash = computed;
      }
    }
    return _hash!;
  }

  @override
  String toString() => display();
}

/// Builds a [Structure] feature by feature.
final class StructureBuilder {
  StructureBuilder._(this._features);

  final Map<String, Value> _features;

  /// Sets [feature] to [value], replacing any earlier value.
  StructureBuilder put(String feature, Value value) {
    _features[feature] = value;
    return this;
  }

  /// The structure built so far.
  Structure build() => Structure._(_features);
}
