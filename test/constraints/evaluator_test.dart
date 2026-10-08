import 'package:libugf/libugf.dart';
import 'package:libugf/src/arithmetic.dart';
import 'package:test/test.dart';

const p = Call('t', []);
const q = Call('t', []);
const f = Call('f', []);
const g = Call('f', []);

/// Calls named `t` are true, `f` false, `in_state(s)` true for DEFAULT.
bool oracle(Call call) => switch (call.name) {
  't' => true,
  'f' => false,
  'in_state' => call.args.first == const StringConstant('DEFAULT'),
  _ => throw StateError('unexpected call $call'),
};

Verdict evaluate(Plan plan) => Evaluator.evaluate(plan, oracle);

Plan soft(Expression expression, int weight) =>
    Plan(const [], [Soft(expression, weight)]);

int penalty(Verdict verdict) => (verdict as Accepted).penalty;

/// Ported from Java `PlanEvaluatorTests` at unifica 8d8c01a.
void main() {
  test('testTruthIsBoolean', () {
    expect(Evaluator.truth(const And([p, q]), oracle), isTrue);
    expect(Evaluator.truth(const And([p, f]), oracle), isFalse);
    expect(Evaluator.truth(const Or([f, q]), oracle), isTrue);
    expect(Evaluator.truth(const Or([f, g]), oracle), isFalse);
    expect(Evaluator.truth(const Not(f), oracle), isTrue);
    expect(Evaluator.truth(Literal.trueValue, oracle), isTrue);
    expect(Evaluator.truth(const Weighted(f, 3), oracle), isFalse);
  });

  test('testTruthShortCircuits', () {
    final seen = <String>[];
    bool calls(Call call) {
      seen.add(call.name);
      return call.name == 't';
    }

    Evaluator.truth(const And([f, Call('t', [])]), calls);
    Evaluator.truth(const Or([Call('t', []), f]), calls);

    expect(seen, ['f', 't']);
  });

  test('testSoftGroupTable', () {
    expect(penalty(evaluate(soft(const And([p, q]), 7))), 0);
    expect(penalty(evaluate(soft(const And([p, f]), 7))), 7);
    expect(penalty(evaluate(soft(const And([f, g]), 7))), 7);
    expect(penalty(evaluate(soft(const Or([p, f]), 7))), 0);
    expect(penalty(evaluate(soft(const Or([f, g]), 7))), 7);
  });

  test('testIndependentSoftGroupsAdd', () {
    final plan = Plan(const [], [Soft(f, 3), Soft(g, 4), Soft(p, 9)]);

    expect(penalty(evaluate(plan)), 7);
  });

  test('testRequiredFailureRejects', () {
    final plan = Plan(const [p, f], [Soft(g, 3)]);

    expect((evaluate(plan) as Rejected).failed, f);
  });

  test('testRequiredAndSoftTogether', () {
    final plan = Plan(
      const [p],
      [
        Soft(const And([f, g]), 7),
      ],
    );

    expect(penalty(evaluate(plan)), 7);
  });

  test('testOverflow', () {
    final plan = Plan(const [], [Soft(f, largest), Soft(g, 1)]);

    expect(evaluate(plan), isA<Overflow>());
  });

  test('testLargestPenaltyFits', () {
    final plan = Plan(const [], [Soft(f, largest - 1), Soft(g, 1)]);

    expect(penalty(evaluate(plan)), largest);
  });

  test('testEmptyPlanAccepts', () {
    expect(penalty(evaluate(Plan.empty)), 0);
    expect(Plan.empty.isEmpty, isTrue);
  });

  test('testResidualPreservesTruth', () {
    const state = Call('in_state', [StringConstant('DEFAULT')]);
    const equals = Call('equals', [StringConstant('a'), StringConstant('b')]);
    const lexical = {'in_state'};

    expect(
      Evaluator.residual(const Or([state, equals]), oracle, lexical),
      Literal.trueValue,
    );
    expect(
      Evaluator.residual(const And([state, equals]), oracle, lexical),
      equals,
    );
    expect(
      Evaluator.residual(const Not(state), oracle, lexical),
      Literal.falseValue,
    );
    expect(
      Evaluator.residual(const Not(equals), oracle, lexical),
      const Not(equals),
    );
  });

  test('testResidualKeepsUnevaluatedStructure', () {
    const other = Call('equals', [StringConstant('a'), StringConstant('a')]);
    const expression = Or([
      other,
      And([other, other]),
    ]);

    expect(Evaluator.residual(expression, oracle, {'in_state'}), expression);
  });

  test('testResidualDropsWeights', () {
    expect(
      Evaluator.residual(const Weighted(Call('x', []), 3), oracle, const {}),
      const Call('x', []),
    );
  });
}
