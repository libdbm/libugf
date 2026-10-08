/// Feature values used in unification grammar parsing.
///
/// The [Value] sealed class hierarchy represents all possible feature values:
/// - [Constant] subtypes for atomic values (strings, numbers, booleans)
/// - [Variable] for unification variables
/// - [FeaturePath] for dotted path expressions
/// - [Binding] for labeled constituent bindings
/// - [Structure] for nested feature structures
library;

import '../result.dart';

part 'structure.dart';

bool _listEquals(List<String> left, List<String> right) {
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

/// Base sealed class for all feature values.
///
/// Feature values can be atomic constants, variables, bindings, feature paths,
/// or nested structures.
sealed class Value {
  const Value();

  /// Returns true if this value is a variable or feature path.
  bool get isVariable;

  /// Returns true if this value is an atomic constant.
  bool get isAtomic;

  /// Returns a string representation for display.
  String display();

  /// The value's text for string predicates (S-C9): a string constant's
  /// value, or a constituent binding's input text. Other values have none.
  String? get text => null;
}

/// Marker interface for atomic constant values.
///
/// Groups [StringConstant], [NumericConstant], and [BooleanConstant].
sealed class Constant extends Value {
  const Constant();

  @override
  bool get isVariable => false;

  @override
  bool get isAtomic => true;
}

/// Represents a string constant value.
final class StringConstant extends Constant {
  /// The string.
  final String value;

  /// A string constant of [value].
  const StringConstant(this.value);

  /// Factory constructor for creating string constants.
  factory StringConstant.of(String value) => StringConstant(value);

  @override
  String get text => value;

  @override
  String display() => value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StringConstant && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Represents a numeric constant value.
///
/// Integral values are stored as `int` and floating values as `double`, with
/// the [floating] flag stored rather than inferred from the runtime type: on
/// the web `1.0 is int`.
///
/// Equality follows the mathematical value (S-F4): `1` and `1.0` are equal
/// and hash alike, `-0.0` equals `0.0`, and NaN equals NaN. Integral and
/// floating values are compared exactly, never by narrowing the integral
/// value to a double.
final class NumericConstant extends Constant {
  static final _integer = RegExp(r'^[+-]?\d+$');
  static final _floating = RegExp(
    r'^[+-]?(?:(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?|\d+(?:[eE][+-]?\d+))$',
  );

  /// Whether integers are doubles, exact only to 2^53 (dart2js).
  static const _web = identical(0, 0.0);

  /// The largest integer magnitude a literal may have: 2^63 - 1, or 2^53 - 1 on dart2js.
  static final _limit = _web
      ? BigInt.from(9007199254740991)
      : BigInt.parse('9223372036854775807');

  /// The value: an `int` unless [floating].
  final num value;

  /// Whether the value is floating point.
  final bool floating;

  /// A constant holding [value], converted to a double if [floating] and
  /// truncated to an integer otherwise.
  NumericConstant(num value, {this.floating = false})
    : value = floating ? value.toDouble() : value.toInt();

  /// Creates an integer constant.
  factory NumericConstant.integer(int value) => NumericConstant(value);

  /// Creates a floating-point constant.
  factory NumericConstant.real(double value) =>
      NumericConstant(value, floating: true);

  /// Parses a numeric literal: floating if it has a decimal point or an
  /// exponent, integral otherwise. An invalid literal, or an integer beyond
  /// the platform's exact range, is a `number.invalid` failure.
  static Result<NumericConstant, ErrorDetails> parse(String literal) {
    final trimmed = literal.trim();
    if (isFloating(trimmed)) {
      return Success(NumericConstant.real(double.parse(trimmed)));
    }
    if (isInteger(trimmed)) {
      final big = BigInt.parse(trimmed);
      if (big.abs() > _limit && !(big == -_limit - BigInt.one && !_web)) {
        return Failure(
          ErrorDetails.of(
            'number.invalid',
            'Numeric literal out of range: $literal',
          ),
        );
      }
      return Success(NumericConstant.integer(big.toInt()));
    }
    return Failure(
      ErrorDetails.of('number.invalid', 'Invalid numeric literal: $literal'),
    );
  }

  /// Returns true if the string represents a floating-point number.
  static bool isFloating(String s) {
    if (s.isEmpty) return false;
    return _floating.hasMatch(s.trim());
  }

  /// Returns true if the string represents an integer.
  static bool isInteger(String s) {
    if (s.isEmpty) return false;
    return _integer.hasMatch(s.trim());
  }

  /// Returns true if the string represents any numeric value.
  static bool isNumeric(String s) => isInteger(s) || isFloating(s);

  /// Returns the value as an integer.
  int get asInt => value.toInt();

  /// Returns the value as a double.
  double get asDouble => value.toDouble();

  @override
  String display() => value.toString();

  @override
  String toString() => value.toString();

  @override
  bool operator ==(Object other) {
    if (other is! NumericConstant) {
      return false;
    }
    if (!floating && !other.floating) {
      return value == other.value;
    }
    if (floating && other.floating) {
      final (a, b) = (value as double, other.value as double);
      return a == b || a.isNaN && b.isNaN;
    }
    final real = floating ? value as double : other.value as double;
    final integral = floating ? other.value as int : value as int;
    final whole = _whole(real);
    return whole != null && whole == integral;
  }

  @override
  int get hashCode {
    if (!floating) {
      return value.hashCode;
    }
    // A floating value equal to an integer hashes like that integer.
    return _whole(value as double)?.hashCode ?? value.hashCode;
  }

  /// The integer [real] is exactly, or null if it is not integral or lies
  /// outside the 64-bit range.
  static int? _whole(double real) {
    if (!real.isFinite ||
        real != real.truncateToDouble() ||
        real < -9223372036854775808.0 ||
        real >= 9223372036854775808.0) {
      return null;
    }
    return real.toInt();
  }
}

/// Represents a boolean constant value.
///
/// Provides singleton instances for true and false.
final class BooleanConstant extends Constant {
  /// The true constant.
  static const trueValue = BooleanConstant._(true);

  /// The false constant.
  static const falseValue = BooleanConstant._(false);

  /// The boolean.
  final bool value;

  const BooleanConstant._(this.value);

  /// Returns the singleton for the given boolean value.
  factory BooleanConstant.of(bool value) => value ? trueValue : falseValue;

  /// Parses "true" or "false", ignoring case; anything else is a
  /// `boolean.invalid` failure.
  static Result<BooleanConstant, ErrorDetails> parse(String s) =>
      switch (s.toLowerCase()) {
        'true' => const Success(trueValue),
        'false' => const Success(falseValue),
        _ => Failure(ErrorDetails.of('boolean.invalid', 'Invalid boolean: $s')),
      };

  /// Returns true if the string represents a boolean value.
  static bool isBoolean(String s) {
    final lower = s.toLowerCase();
    return lower == 'true' || lower == 'false';
  }

  @override
  String display() => value.toString();

  @override
  String toString() => value.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BooleanConstant && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Represents a unification variable.
///
/// Variables are used for feature unification and must be bound during parsing.
/// The name is stored without the optional '?' prefix.
final class Variable extends Value {
  /// The variable's name, without a `?` prefix.
  final String name;

  /// A variable named [name].
  const Variable(this.name);

  /// Creates a variable from a string that may have a '?' prefix.
  factory Variable.of(String s) =>
      Variable(s.startsWith('?') ? s.substring(1) : s);

  @override
  bool get isVariable => true;

  @override
  bool get isAtomic => false;

  /// Shows the variable as `?name`, without the `$` a grammar variable is
  /// named with.
  @override
  String display() => '?${name.startsWith(r'$') ? name.substring(1) : name}';

  @override
  String toString() => display();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Variable && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

/// Represents a feature path expression like `W.cat` or `X.num.person`.
///
/// Feature paths are used in constraints to access nested features.
/// The first part is the root variable, and remaining parts are feature names.
final class FeaturePath extends Value {
  /// The root variable followed by the feature names.
  final List<String> parts;

  /// A path of [parts], which must not be empty.
  FeaturePath(this.parts) {
    if (parts.isEmpty) {
      throw ArgumentError('Feature path must have at least one part');
    }
  }

  /// Creates a feature path from a dotted string.
  factory FeaturePath.parse(String path) =>
      FeaturePath(path.split('.').toList());

  /// The root variable name (first part).
  String get root => parts.first;

  /// The feature names to traverse (remaining parts after root).
  List<String> get path => parts.length > 1 ? parts.sublist(1) : const [];

  /// Returns true if this is a simple variable (no feature path).
  bool get isSimple => parts.length == 1;

  @override
  bool get isVariable => true;

  @override
  bool get isAtomic => false;

  @override
  String display() => parts.join('.');

  @override
  String toString() => display();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeaturePath && _listEquals(parts, other.parts);

  @override
  int get hashCode => Object.hashAll(parts);
}

/// Represents a binding that combines text content and feature structure.
///
/// Used to bind labeled constituents in constraint evaluation, allowing
/// predicates to access either the text representation or the associated features.
final class Binding extends Value {
  @override
  final String text;

  /// The constituent's features.
  final Structure features;

  /// A binding of [text] and [features].
  const Binding(this.text, this.features);

  /// Creates a binding with [text] and [features], empty by default.
  factory Binding.of(String text, [Structure? features]) =>
      Binding(text, features ?? Structure.empty);

  @override
  bool get isVariable => false;

  @override
  bool get isAtomic => false;

  @override
  String display() {
    if (features.isEmpty) {
      return "'$text'";
    }
    return "'$text'${features.display()}";
  }

  @override
  String toString() => display();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Binding && text == other.text && features == other.features;

  @override
  int get hashCode => Object.hash(text, features);
}
