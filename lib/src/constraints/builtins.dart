part of 'predicates.dart';

/// The builtin predicates, registered with [PredicatesBuilder.builtins]:
/// unification (`agree`, `unify`), features (`has_feature`, `get_feature`,
/// `feature_eq`), equality, type tests, strings (`starts_with`, `ends_with`,
/// `contains`, `matches`, `not_empty`, `is_upper`, `is_lower`,
/// `is_capitalized`), exact numeric comparison (`lt`, `le`, `gt`, `ge`) and
/// token position (`at_start`, `at_position`, `at_end`, `before`).
///
/// String predicates use a value's text (S-C9), so a literal, a labelled
/// token and a labelled constituent behave alike.
abstract final class _Builtins {
  /// How many compiled `matches` patterns are kept, least recently used
  /// first out.
  static const _patterns = 256;

  /// Compiled full-match patterns for `matches`, by source; null for a
  /// pattern outside the portable subset, which never matches (S-L7).
  static final _cache = <String, RegExp?>{};

  static final _uppercase = RegExp(r'^\p{Uppercase}$', unicode: true);

  /// Registers every builtin: the position predicates are positional, the
  /// rest syntactic.
  static void register(PredicatesBuilder builder) {
    const phase = Phase.syntactic;
    builder
      ..add('agree', 2, 2, phase, _agrees)
      ..add('unify', 2, 2, phase, _agrees)
      ..add('has_feature', 2, 2, phase, (environment, args) {
        final structure = _features(environment.resolve(args[0]));
        final name = environment.resolve(args[1])?.text;
        return structure != null && name != null && structure.has(name);
      })
      ..add('get_feature', 3, 3, phase, (environment, args) {
        final actual = _feature(environment, args[0], args[1]);
        return actual != null && actual == environment.resolve(args[2]);
      })
      ..add('feature_eq', 4, 4, phase, (environment, args) {
        final first = _feature(environment, args[0], args[1]);
        return first != null &&
            first == _feature(environment, args[2], args[3]);
      })
      ..add('equals', 2, 2, phase, (environment, args) {
        final first = environment.resolve(args[0]);
        return first != null && _same(first, environment.resolve(args[1]));
      })
      ..add('not_equals', 2, 2, phase, (environment, args) {
        final first = environment.resolve(args[0]);
        return first == null || !_same(first, environment.resolve(args[1]));
      })
      ..add(
        'is_string',
        1,
        1,
        phase,
        (environment, args) =>
            environment.resolve(args.first) is StringConstant,
      )
      ..add(
        'is_number',
        1,
        1,
        phase,
        (environment, args) =>
            environment.resolve(args.first) is NumericConstant,
      )
      ..add(
        'is_structure',
        1,
        1,
        phase,
        (environment, args) => environment.resolve(args.first) is Structure,
      )
      ..add('is_bound', 1, 1, phase, (environment, args) {
        final value = environment.resolve(args.first);
        return value != null && value is! Variable;
      })
      ..add('starts_with', 2, 2, phase, _strings((a, b) => a.startsWith(b)))
      ..add('ends_with', 2, 2, phase, _strings((a, b) => a.endsWith(b)))
      ..add('contains', 2, 2, phase, _strings((a, b) => a.contains(b)))
      ..add('matches', 2, 2, phase, _strings(_matches))
      ..add('not_empty', 1, 1, phase, _string((text) => text.isNotEmpty))
      ..add(
        'is_upper',
        1,
        1,
        phase,
        _string((text) => text.isNotEmpty && text == text.toUpperCase()),
      )
      ..add(
        'is_lower',
        1,
        1,
        phase,
        _string((text) => text.isNotEmpty && text == text.toLowerCase()),
      )
      ..add('is_capitalized', 1, 1, phase, _string(_capitalized))
      ..add('lt', 2, 2, phase, _numbers((comparison) => comparison < 0))
      ..add('le', 2, 2, phase, _numbers((comparison) => comparison <= 0))
      ..add('gt', 2, 2, phase, _numbers((comparison) => comparison > 0))
      ..add('ge', 2, 2, phase, _numbers((comparison) => comparison >= 0));
    const positional = Phase.positional;
    builder
      ..add(
        'at_start',
        0,
        0,
        positional,
        (environment, args) => _at(environment, 0),
      )
      ..add('at_position', 1, 1, positional, (environment, args) {
        final position = _Lexical.integer(args.first);
        return position != null && position >= 0 && _at(environment, position);
      })
      ..add('at_end', 0, 0, positional, (environment, args) {
        final end = environment.get(Environment.end);
        return end is BooleanConstant && end.value;
      })
      ..add('before', 1, Entry.unlimited, positional, (environment, args) {
        final next = _features(environment.get(Environment.next));
        return next != null &&
            args.any((arg) {
              final category = environment.resolve(arg)?.text;
              return category != null && next.has(category);
            });
      });
  }

  static bool _agrees(Environment environment, List<Value> args) {
    final first = environment.resolve(args[0]);
    final second = environment.resolve(args[1]);
    return first != null &&
        second != null &&
        Unifier.unify(first, second) is Success;
  }

  /// Value equality, except that a labelled constituent and a string compare
  /// by text (S-C9).
  static bool _same(Value first, Value? second) => switch ((first, second)) {
    (final Binding binding, final StringConstant constant) =>
      binding.text == constant.value,
    (final StringConstant constant, final Binding binding) =>
      constant.value == binding.text,
    _ => first == second,
  };

  /// The features of a structure or a constituent binding, or null.
  static Structure? _features(Value? value) => switch (value) {
    final Structure structure => structure,
    final Binding binding => binding.features,
    _ => null,
  };

  static Value? _feature(Environment environment, Value base, Value name) {
    final structure = _features(environment.resolve(base));
    final key = environment.resolve(name)?.text;
    return structure == null || key == null ? null : structure.get(key);
  }

  /// A predicate over the texts of two arguments; false if either has no
  /// text (S-C9).
  static Check _strings(bool Function(String, String) test) =>
      (environment, args) {
        final first = environment.resolve(args[0])?.text;
        final second = environment.resolve(args[1])?.text;
        return first != null && second != null && test(first, second);
      };

  /// A predicate over the text of one argument; false if it has no text
  /// (S-C9).
  static Check _string(bool Function(String) test) => (environment, args) {
    final text = environment.resolve(args.first)?.text;
    return text != null && test(text);
  };

  /// Java's `Character.isUpperCase` of the first UTF-16 unit: false for a
  /// surrogate, otherwise the Unicode Uppercase property.
  static bool _capitalized(String text) {
    if (text.isEmpty) {
      return false;
    }
    final unit = text.codeUnitAt(0);
    return (unit < 0xD800 || unit > 0xDFFF) &&
        _uppercase.hasMatch(String.fromCharCode(unit));
  }

  /// A comparison of two numbers (S-F4). As in IEEE 754, a comparison with
  /// NaN is false and the infinities order below and above every finite
  /// value; finite values compare exactly.
  static Check _numbers(bool Function(int) test) => (environment, args) {
    final first = environment.resolve(args[0]);
    final second = environment.resolve(args[1]);
    return first is NumericConstant &&
        second is NumericConstant &&
        !first.asDouble.isNaN &&
        !second.asDouble.isNaN &&
        test(_compare(first, second));
  };

  static int _compare(NumericConstant first, NumericConstant second) {
    if (!first.floating && !second.floating) {
      return first.asInt.compareTo(second.asInt);
    }
    if (first.floating && second.floating) {
      return first.asDouble.compareTo(second.asDouble);
    }
    final order = first.floating
        ? _mixed(first.asDouble, second.asInt)
        : -_mixed(second.asDouble, first.asInt);
    return order;
  }

  /// The order of [real] (not NaN) against [integral], exactly.
  static int _mixed(double real, int integral) {
    if (real.isInfinite) {
      return real > 0 ? 1 : -1;
    }
    if (identical(0, 0.0)) {
      // On the web an int is a double, so the comparison is already exact.
      return real.compareTo(integral);
    }
    if (real >= 9223372036854775808.0) {
      return 1;
    }
    if (real < -9223372036854775808.0) {
      return -1;
    }
    final whole = real.truncateToDouble();
    final order = whole.toInt().compareTo(integral);
    if (order != 0) {
      return order;
    }
    return real == whole ? 0 : (real > whole ? 1 : -1);
  }

  /// Whether all of [text] matches [pattern], a standalone S-L7 pattern; a
  /// pattern outside the subset never matches.
  static bool _matches(String text, String pattern) {
    final RegExp? compiled;
    if (_cache.containsKey(pattern)) {
      // Least recently used order: move the pattern to the end.
      compiled = _cache.remove(pattern);
    } else {
      compiled = switch (Patterns.portable(pattern)) {
        Success(:final value) => _full(value),
        Failure() => null,
      };
      if (_cache.length >= _patterns) {
        _cache.remove(_cache.keys.first);
      }
    }
    _cache[pattern] = compiled;
    return compiled != null && compiled.hasMatch(text);
  }

  static RegExp? _full(String dart) {
    try {
      return RegExp('^(?:$dart)\$', unicode: true);
    } on FormatException {
      return null;
    }
  }

  /// True if the constituent being checked can start at [position] (S-C7).
  static bool _at(Environment environment, int position) {
    final positions = _features(environment.get(Environment.origin));
    return positions != null && positions.has('$position');
  }
}
