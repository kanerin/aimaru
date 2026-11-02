import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/domain/bonus_savings.dart';
import 'package:aimaru/features/budget/domain/budget_plan.dart';

import '../../../helpers/budget_fixtures.dart';

// ボーナスからの貯金を「年に何回・1回いくら」で入力するための変換。
void main() {
  test('年n回の既定の月は12月で終わる等間隔', () {
    expect(evenlySpacedMonths(0), isEmpty);
    expect(evenlySpacedMonths(1), [12]);
    expect(evenlySpacedMonths(2), [6, 12]);
    expect(evenlySpacedMonths(3), [4, 8, 12]);
    expect(evenlySpacedMonths(4), [3, 6, 9, 12]);
    expect(evenlySpacedMonths(12), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  });

  test('今の設定を「年◯回 × ◯円」として読む', () {
    final setting = bonusSavingsOf(realCouplePlan().savingsGoal, memberB);

    expect(setting.timesPerYear, 2);
    expect(setting.amountPerTime, 200000);
    expect(setting.annualAmount, 400000);
    expect(setting.uniformAmount, isTrue);
    expect(setting.months, [6, 12]);

    expect(bonusSavingsOf(realCouplePlan().savingsGoal, memberA).timesPerYear, 0);
  });

  test('回数が同じまま金額だけ変えると、入金する月はそのまま', () {
    final list = withBonusSavings(realCouplePlan(), memberB, timesPerYear: 2, amountPerTime: 250000);

    expect(list.map((b) => (b.memberId, b.month, b.amount)), [
      (memberB, 6, 250000),
      (memberB, 12, 250000),
    ]);
  });

  test('ボーナスの無いメンバーに追加すると等間隔の月に入り、他のメンバーの分は残る', () {
    final list = withBonusSavings(realCouplePlan(), memberA, timesPerYear: 2, amountPerTime: 100000);

    // 月の順、同じ月はメンバーの並び順
    expect(list.map((b) => (b.memberId, b.month, b.amount)), [
      (memberA, 6, 100000),
      (memberB, 6, 200000),
      (memberA, 12, 100000),
      (memberB, 12, 200000),
    ]);
  });

  test('回数を変えたとき、収入側のボーナスの回数と同じならその支給月に入れる', () {
    final plan = realCouplePlan();
    final withIncomeBonus = plan.copyWith(members: [
      plan.members[0].copyWith(bonuses: const [Bonus(month: 7, amount: 300000), Bonus(month: 12, amount: 300000)]),
      plan.members[1],
    ]);

    final list = withBonusSavings(withIncomeBonus, memberA, timesPerYear: 2, amountPerTime: 100000);

    expect(list.where((b) => b.memberId == memberA).map((b) => b.month), [7, 12]);
  });

  test('収入側のボーナスと回数が合わなければ等間隔の月にする', () {
    final list = withBonusSavings(realCouplePlan(), memberB, timesPerYear: 3, amountPerTime: 100000);

    expect(list.where((b) => b.memberId == memberB).map((b) => b.month), [4, 8, 12]);
  });

  test('0回にするとそのメンバーの分はなくなる', () {
    final list = withBonusSavings(realCouplePlan(), memberB, timesPerYear: 0, amountPerTime: 200000);

    expect(list, isEmpty);
  });

  test('月ごとに額が違う設定は uniformAmount=false として読む', () {
    final goal = realCouplePlan().savingsGoal.copyWith(bonusContributions: const [
      BonusContribution(memberId: memberB, month: 6, amount: 200000),
      BonusContribution(memberId: memberB, month: 12, amount: 300000),
    ]);

    final setting = bonusSavingsOf(goal, memberB);
    expect(setting.uniformAmount, isFalse);
    expect(setting.amountPerTime, 200000);
  });
}
