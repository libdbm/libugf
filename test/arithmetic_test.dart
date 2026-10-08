import 'package:libugf/src/arithmetic.dart';
import 'package:test/test.dart';

const web = identical(0, 0.0);

void main() {
  test('testLargestIsThePlatformsExactLimit', () {
    expect(largest, web ? 9007199254740991 : int.parse('9223372036854775807'));
  });

  test('testSum', () {
    expect(sum(2, 3), 5);
    expect(sum(largest - 1, 1), largest);
    expect(sum(largest, 1), isNull);
    expect(sum(-largest, -1), isNull);
    expect(sum(5, -7), -2);
  });

  test('testExact', () {
    expect(exact(4.0), 4);
    expect(exact(-0.0), 0);
    expect(exact(4.5), isNull);
    expect(exact(double.nan), isNull);
    expect(exact(double.infinity), isNull);
    expect(exact(1e300), isNull);
    if (web) {
      expect(exact(9007199254740991.0), 9007199254740991);
      expect(exact(9007199254740992.0), isNull);
    } else {
      expect(exact(9223372036854775808.0), isNull);
      expect(exact(4611686018427387904.0), int.parse('4611686018427387904'));
    }
  });
}
