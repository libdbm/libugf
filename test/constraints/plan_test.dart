import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

const p = Call('p', []);
const q = Call('q', []);
const r = Call('r', []);

Plan plan(List<Expression> constraints) => Plan.of(constraints).orElseThrow();

ErrorDetails failure(List<Expression> constraints) =>
    (Plan.of(constraints) as Failure<Plan, ErrorDetails>).error;

/// Ported from Java `PlanConversionTests` at unifica 8d8c01a, with the
/// expressions the loader would build written out. The tests that parse
/// grammar text move to Task 13.
void main() {
  test('testRequiredAndSoftSplit', () {
    // r(), p():3
    expect(plan(const [r, Weighted(p, 3)]), Plan(const [r], [Soft(p, 3)]));
  });

  test('testWeightedGroupIsOneSoftGroup', () {
    // (p(), q()):7
    expect(
      plan(const [
        Weighted(And([p, q]), 7),
      ]),
      Plan(const [], [
        Soft(const And([p, q]), 7),
      ]),
    );
  });

  test('testUnweightedGroupsFlatten', () {
    // r(), (p():3, q():4)
    expect(
      plan(const [
        r,
        And([Weighted(p, 3), Weighted(q, 4)]),
      ]),
      Plan(const [r], [Soft(p, 3), Soft(q, 4)]),
    );
    // ((p():7))
    expect(
      plan(const [
        And([
          And([Weighted(p, 7)]),
        ]),
      ]),
      Plan(const [], [Soft(p, 7)]),
    );
  });

  test('testNestedWeightsIgnored', () {
    // (p():3, q():4):9
    expect(
      plan(const [
        Weighted(And([Weighted(p, 3), Weighted(q, 4)]), 9),
      ]),
      Plan(const [], [
        Soft(const And([p, q]), 9),
      ]),
    );
  });

  test('testWeightUnderOrRejected', () {
    // (p():3 | q())
    expect(
      failure(const [
        Or([Weighted(p, 3), q]),
      ]).code,
      'constraint.weight',
    );
  });

  test('testWeightUnderNotRejected', () {
    // !p():3
    expect(failure(const [Not(Weighted(p, 3))]).code, 'constraint.weight');
  });

  test('testWeightedNegationIsSoft', () {
    // (!p()):5
    expect(
      plan(const [Weighted(Not(p), 5)]),
      Plan(const [], [Soft(const Not(p), 5)]),
    );
  });

  test('testEveryErrorReported', () {
    // (p():3 | q()), !r():2
    final error = failure(const [
      Or([Weighted(p, 3), q]),
      Not(Weighted(r, 2)),
    ]);
    expect(error.issues, hasLength(2));
    expect(
      error.issues.first,
      "weight 3 on p(...) is under 'or' or 'not'; a soft group must be a "
      'top-level conjunct',
    );
  });

  test('testRequiredDisjunction', () {
    expect(
      plan(const [
        Or([p, q]),
      ]),
      Plan(const [
        Or([p, q]),
      ], const []),
    );
  });

  test('testZeroWeightIsDropped', () {
    expect(plan(const [Weighted(p, 0)]), Plan.empty);
  });

  test('testExpressionEquality', () {
    expect(
      const Call('a', [StringConstant('x')]),
      Call('a', List.of(const [StringConstant('x')])),
    );
    expect(const And([p, q]), isNot(const And([q, p])));
    expect(const And([p, q]).hashCode, And(List.of(const [p, q])).hashCode);
    expect(Literal.of(true), same(Literal.trueValue));
  });
}
