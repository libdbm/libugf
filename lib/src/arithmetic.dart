/// Integer arithmetic that detects overflow instead of wrapping: 64-bit on
/// the VM and wasm, exact to 2^53 - 1 on dart2js.
library;

/// Whether integers are doubles, exact only to 2^53 (dart2js).
const _web = identical(0, 0.0);

/// The largest integer the platform holds exactly: 2^63 - 1 on the VM and
/// wasm, 2^53 - 1 on the web. A penalty or weight beyond it is an overflow.
final int largest = _web ? 9007199254740991 : ((1 << 62) - 1) + (1 << 62);

/// [left] + [right], or null if the sum lies beyond [largest] in either
/// direction.
int? sum(int left, int right) {
  if (right > 0 && left > largest - right) {
    return null;
  }
  if (right < 0 && left < -largest - right) {
    return null;
  }
  return left + right;
}

/// The integer [real] is exactly, or null if it is not finite, not integral,
/// or beyond [largest] in magnitude.
int? exact(double real) {
  if (!real.isFinite || real != real.truncateToDouble()) {
    return null;
  }
  // 2^63 and 2^53 - 1 are exact doubles; 2^63 itself is out of range.
  final inside = _web
      ? real.abs() <= 9007199254740991.0
      : real.abs() < 9223372036854775808.0;
  return inside ? real.toInt() : null;
}
