import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/domain/bonus_calendar.dart';
import 'package:aimaru/features/budget/domain/budget_plan.dart';

import '../../../helpers/budget_fixtures.dart';

void main() {
  BudgetPlan planWithBonuses(List<Bonus> bonuses) {
    final plan = realCouplePlan();
    return plan.copyWith(members: [
      plan.members[0].copyWith(bonuses: bonuses),
      plan.members[1].copyWith(bonuses: const []),
    ]);
  }

  test('支給日が設定されていればその日に、毎年表示する', () {
    final plan = realCouplePlan(); // Bのボーナス: 6/30、12/10

    final june = bonusEntriesOn(plan, DateTime(2027, 6, 30));
    expect(june, hasLength(1));
    expect(june.single.memberId, memberB);
    expect(june.single.amount, 500000);
    expect(june.single.label, 'Bのボーナス');
    expect(june.single.isMonthOnly, isFalse);

    expect(bonusEntriesOn(plan, DateTime(2028, 12, 10)), hasLength(1));
    expect(bonusEntriesOn(plan, DateTime(2027, 6, 29)), isEmpty);
    expect(bonusEntriesOn(plan, DateTime(2027, 7, 30)), isEmpty);
  });

  test('支給日が未設定ならその月の1日に「ボーナス月」として表示する', () {
    final plan = planWithBonuses(const [Bonus(month: 7, amount: 300000)]);

    final entries = bonusEntriesOn(plan, DateTime(2027, 7, 1));
    expect(entries, hasLength(1));
    expect(entries.single.label, 'Aのボーナス月');
    expect(entries.single.isMonthOnly, isTrue);
    expect(bonusEntriesOn(plan, DateTime(2027, 7, 2)), isEmpty);
  });

  test('その月に無い支給日（2月31日など）は月末に寄せる', () {
    final plan = planWithBonuses(const [Bonus(month: 2, amount: 100000, payDay: 31)]);

    expect(bonusEntriesOn(plan, DateTime(2027, 2, 28)), hasLength(1));
    expect(bonusEntriesOn(plan, DateTime(2028, 2, 29)), hasLength(1)); // うるう年
    expect(bonusEntriesOn(plan, DateTime(2028, 2, 28)), isEmpty);
  });
}
