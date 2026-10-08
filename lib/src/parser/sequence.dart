/// Keys that order derivations (S-P3).
library;

/// An immutable sequence of integers built by concatenation, used for the
/// keys that order derivations (S-P3). Concatenation shares both parts
/// instead of copying them, so a derivation's keys cost constant space on
/// top of its parts' keys; comparison skips the parts two sequences share.
/// Not exported.
final class Sequence implements Comparable<Sequence> {
  const Sequence._(this._left, this._right, this._value, this.size);

  /// The sequence of one integer.
  const Sequence.of(int value) : this._(null, null, value, 1);

  /// The sequence of no integers.
  static const empty = Sequence._(null, null, 0, 0);

  final Sequence? _left;
  final Sequence? _right;
  final int _value;

  /// The number of integers in the sequence.
  final int size;

  /// This sequence followed by [other].
  Sequence then(Sequence other) {
    if (other.size == 0) {
      return this;
    }
    if (size == 0) {
      return other;
    }
    return Sequence._(this, other, 0, size + other.size);
  }

  /// Lexicographic order; a proper prefix comes first.
  @override
  int compareTo(Sequence other) {
    final result = differ(other);
    return result != 0 ? result : size.compareTo(other.size);
  }

  /// The order at the first position where the two sequences differ, or 0
  /// if one is a prefix of the other. A nonzero result holds whatever is
  /// appended to both.
  int differ(Sequence other) {
    final mine = <Sequence>[];
    final theirs = <Sequence>[];
    _push(mine, this);
    _push(theirs, other);
    while (mine.isNotEmpty && theirs.isNotEmpty) {
      final a = mine.last;
      final b = theirs.last;
      if (identical(a, b)) {
        // A shared part is equal and has the same length, so both sides
        // stay aligned.
        mine.removeLast();
        theirs.removeLast();
      } else if (a._left case final left?) {
        mine.removeLast();
        _push(mine, a._right!);
        _push(mine, left);
      } else if (b._left case final left?) {
        theirs.removeLast();
        _push(theirs, b._right!);
        _push(theirs, left);
      } else {
        mine.removeLast();
        theirs.removeLast();
        final result = a._value.compareTo(b._value);
        if (result != 0) {
          return result;
        }
      }
    }
    return 0;
  }

  static void _push(List<Sequence> stack, Sequence sequence) {
    if (sequence.size > 0) {
      stack.add(sequence);
    }
  }
}
