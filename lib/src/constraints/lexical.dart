part of 'predicates.dart';

/// The lexical predicates (S-C7): they read the lexical state stack or the
/// character position, so they can only be evaluated while lexing. This is
/// the only place their names are defined.
abstract final class _Lexical {
  static final _number = RegExp(r'^-?\d+$');

  static void register(PredicatesBuilder builder) {
    const phase = Phase.lexical;
    builder
      ..add(
        'in_state',
        1,
        Entry.unlimited,
        phase,
        (environment, args) =>
            args.any((arg) => _text(arg) == environment.state),
      )
      ..add('state_depth', 1, 1, phase, (environment, args) {
        final depth = integer(args.first);
        return depth != null && environment.states.length <= depth;
      })
      ..add(
        'state_contains',
        1,
        Entry.unlimited,
        phase,
        (environment, args) =>
            args.any((arg) => environment.states.contains(_text(arg))),
      )
      ..add(
        'at_char_start',
        0,
        0,
        phase,
        (environment, args) => environment.position == 0,
      )
      ..add('at_char_position', 1, 1, phase, (environment, args) {
        final position = integer(args.first);
        return position != null && environment.position == position;
      });
  }

  static String _text(Value value) =>
      value is StringConstant ? value.value : '$value';

  /// The value as an exact integer within the platform's range: a number, or
  /// a number written as a string literal (grammar source has no numeric
  /// literals). Fractions, non-finite numbers, out-of-range values and
  /// anything else are null, so the predicate using it is false (S-C8).
  static int? integer(Value value) {
    switch (value) {
      case NumericConstant(floating: true, :final asDouble):
        return exact(asDouble);
      case NumericConstant(:final asInt):
        return asInt;
      case StringConstant(value: final text) when _number.hasMatch(text.trim()):
        final big = BigInt.parse(text.trim());
        return big.abs() <= BigInt.from(largest) ? big.toInt() : null;
      default:
        return null;
    }
  }
}
