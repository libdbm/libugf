import 'dart:math';

import 'package:libugf/src/parser/sequence.dart';
import 'package:test/test.dart';

int compare(List<int> a, List<int> b) {
  for (var index = 0; index < min(a.length, b.length); index++) {
    final result = a[index].compareTo(b[index]);
    if (result != 0) {
      return result;
    }
  }
  return a.length.compareTo(b.length);
}

/// Ported from Java `SequenceTests` at unifica 8d8c01a.
void main() {
  test('testOrderMatchesLists', () {
    // Random concatenations, including shared parts, order like the lists
    // they represent.
    final random = Random(11);
    final pool = <(Sequence, List<int>)>[(Sequence.empty, const [])];
    for (var index = 0; index < 400; index++) {
      if (random.nextInt(3) == 0) {
        final value = random.nextInt(4);
        pool.add((Sequence.of(value), [value]));
      } else {
        final (a, left) = pool[random.nextInt(pool.length)];
        final (b, right) = pool[random.nextInt(pool.length)];
        pool.add((a.then(b), [...left, ...right]));
      }
    }
    for (final (a, left) in pool) {
      for (final (b, right) in pool) {
        expect(
          a.compareTo(b).sign,
          compare(left, right).sign,
          reason: '$left vs $right',
        );
      }
      expect(a.size, left.length);
    }
  });

  test('testPrefixComesFirst', () {
    final prefix = const Sequence.of(1).then(const Sequence.of(2));

    expect(prefix.compareTo(prefix.then(const Sequence.of(0))).sign, -1);
    expect(prefix.then(const Sequence.of(0)).compareTo(prefix).sign, 1);
    expect(
      prefix.compareTo(const Sequence.of(1).then(const Sequence.of(2))),
      0,
    );
    expect(prefix.differ(prefix.then(const Sequence.of(0))), 0);
  });

  test('testDeepSequence', () {
    // A deep concatenation, as a long chain builds, compares without
    // exhausting the stack.
    var left = Sequence.empty;
    var right = Sequence.empty;
    for (var index = 0; index < 100000; index++) {
      left = left.then(Sequence.of(index));
      right = Sequence.of(index).then(right);
    }

    expect(left.compareTo(left.then(Sequence.empty)), 0);
    expect(right.compareTo(left).sign, 1);
  });
}
