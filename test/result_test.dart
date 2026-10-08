import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

/// Ported from Java `ResultTests`.
void main() {
  final error = ErrorDetails.of('test.error', 'failed');

  test('testMapTransformsSuccess', () {
    final Result<int, ErrorDetails> result = const Success(2);

    expect(
      result.map((value) => value * 2),
      const Success<int, ErrorDetails>(4),
    );
  });

  test('testMapPreservesFailure', () {
    final Result<int, ErrorDetails> result = Failure(error);

    final mapped = result.map((value) => value * 2);

    expect(mapped, isA<Failure<int, ErrorDetails>>());
    expect((mapped as Failure<int, ErrorDetails>).error, same(error));
  });

  test('testFlatMapChainsSuccess', () {
    final Result<int, ErrorDetails> result = const Success(2);

    expect(
      result.flatMap((value) => Success('$value')),
      const Success<String, ErrorDetails>('2'),
    );
  });

  test('testFlatMapPropagatesInnerFailure', () {
    final Result<int, ErrorDetails> result = const Success(2);

    final chained = result.flatMap<String>((value) => Failure(error));

    expect(chained, Failure<String, ErrorDetails>(error));
  });

  test('testFlatMapSkipsOnFailure', () {
    final Result<int, ErrorDetails> result = Failure(error);

    final chained = result.flatMap<String>(
      (value) => fail('must not be called'),
    );

    expect(chained, Failure<String, ErrorDetails>(error));
  });

  test('testOrElse', () {
    expect(const Success<int, ErrorDetails>(1).orElse(0), 1);
    expect(Failure<int, ErrorDetails>(error).orElse(0), 0);
  });

  test('testOrElseThrow', () {
    expect(const Success<int, ErrorDetails>(1).orElseThrow(), 1);
    expect(
      () => Failure<int, ErrorDetails>(error).orElseThrow(),
      throwsA(
        isA<StateError>().having(
          (thrown) => thrown.message,
          'message',
          contains('test.error'),
        ),
      ),
    );
  });

  test('testPatternMatching', () {
    final Result<String, ErrorDetails> result = Failure(error);

    final text = switch (result) {
      Success(:final value) => value,
      Failure(:final error) => error.code,
    };

    expect(text, 'test.error');
  });

  test('testDetailsListSeveralIssues', () {
    final details = ErrorDetails.from('grammar.invalid', ['first', 'second']);

    expect(details.message, '2 issues');
    expect(details.issues, ['first', 'second']);
  });

  test('testDetailsSingleIssueBecomesMessage', () {
    expect(ErrorDetails.from('grammar.invalid', ['only']).message, 'only');
  });

  test('testDetailsIssuesAreCopiedAndUnmodifiable', () {
    final issues = ['first'];
    final details = ErrorDetails('code', 'message', issues);
    issues.add('second');

    expect(details.issues, ['first']);
    expect(() => details.issues.add('third'), throwsUnsupportedError);
  });

  test('testDetailsEquality', () {
    expect(
      ErrorDetails('code', 'message', ['a']),
      ErrorDetails('code', 'message', ['a']),
    );
    expect(
      ErrorDetails('code', 'message', ['a']).hashCode,
      ErrorDetails('code', 'message', ['a']).hashCode,
    );
    expect(
      ErrorDetails('code', 'message', ['a']),
      isNot(ErrorDetails('code', 'message', ['b'])),
    );
  });
}
