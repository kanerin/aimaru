import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/domain/budget_plan.dart';
import 'package:aimaru/features/budget/domain/budget_plan_diff.dart';

import '../../../helpers/budget_fixtures.dart';

// 変更履歴（誰がいつ何を変えたか）の「何を」の部分。
void main() {
  final base = realCouplePlan();

  test('何も変えていなければ差分は空', () {
    expect(diffBudgetPlans(base, realCouplePlan()), isEmpty);
  });

  test('手取りの変更は「名前の手取り: 変更前 → 変更後」', () {
    final changed = base.copyWith(members: [
      base.members[0].copyWith(monthlyTakeHome: 190000),
      base.members[1],
    ]);

    final changes = diffBudgetPlans(base, changed);

    expect(changes, [const BudgetChange('Aの手取り', before: '180,000円', after: '190,000円')]);
    expect(changes.single.describe(), 'Aの手取り: 180,000円 → 190,000円');
  });

  test('共通支出の金額変更・追加・削除・並び替えをそれぞれ記録する', () {
    final changed = base.copyWith(sharedExpenses: [
      base.sharedExpenses[1], // 水道を先頭へ（並び替え）
      base.sharedExpenses[0].copyWith(monthlyAmount: 120000), // 家賃を変更
      // 光熱費を削除
      base.sharedExpenses[3],
      const SharedExpense(id: 'net', label: '通信費', monthlyAmount: 8000, category: ExpenseCategory.communication),
    ]);

    final described = diffBudgetPlans(base, changed).map((c) => c.describe()).toList();

    expect(described, containsAll([
      '家賃: 110,000円 → 120,000円',
      '共通支出「通信費」を追加（8,000円）',
      '共通支出「光熱費」を削除（15,000円）',
      '共通支出の並び順を変更',
    ]));
  });

  test('削除・追加だけで残った項目の順番が同じなら、並び替えとは記録しない', () {
    final changed = base.copyWith(sharedExpenses: base.sharedExpenses.sublist(1));

    final described = diffBudgetPlans(base, changed).map((c) => c.describe()).toList();

    expect(described, ['共通支出「家賃」を削除（110,000円）']);
  });

  test('補助の受け取りを変えると、メンバー名で記録する', () {
    final changed = base.copyWith(offsets: [
      base.offsets.single.copyWith(receivedBy: memberA),
    ]);

    expect(
      diffBudgetPlans(base, changed),
      [const BudgetChange('家賃補助の受け取り', before: 'B', after: 'A')],
    );
  });

  test('生活費口座のルール・入金額・余剰の扱いの変更', () {
    final changed = base.copyWith(
      livingAccount: base.livingAccount.copyWith(
        contributions: {memberA: 65000, memberB: 150000},
        surplusHandling: SurplusHandling.toSavings,
      ),
    );

    expect(diffBudgetPlans(base, changed).map((c) => c.describe()), [
      'Aの生活費入金: 60,000円 → 65,000円',
      '生活費口座の余剰: 口座に残す → 毎月貯金へ移す',
    ]);
  });

  test('固定額から比率指定に切り替えたときは、比率を新しい値として記録する', () {
    final changed = base.copyWith(
      livingAccount: base.livingAccount.copyWith(
        mode: LivingAccountMode.ratio,
        contributions: {memberA: 40, memberB: 60},
      ),
    );

    expect(diffBudgetPlans(base, changed).map((c) => c.describe()), [
      '生活費口座の入金ルール: 固定額 → 比率指定',
      'Aの生活費の比率を追加（40）',
      'Bの生活費の比率を追加（60）',
    ]);
  });

  test('貯金目標・期限・毎月の貯金・ボーナス入金の変更', () {
    final changed = base.copyWith(
      savingsGoal: base.savingsGoal.copyWith(
        targetAmount: 9000000,
        deadline: DateTime(2030, 3, 31),
        monthlyContributions: {memberA: 50000, memberB: 100000},
        bonusContributions: const [
          BonusContribution(memberId: memberB, month: 12, amount: 300000),
        ],
      ),
    );

    expect(diffBudgetPlans(base, changed).map((c) => c.describe()), [
      '貯金の目標額: 8,000,000円 → 9,000,000円',
      '貯金の期限: 2029年10月31日 → 2030年3月31日',
      'Bの毎月の貯金: 90,000円 → 100,000円',
      'ボーナスからの貯金: B 6月 200,000円、B 12月 200,000円 → B 12月 300,000円',
    ]);
  });

  test('毎月の貯金の決め方を比率指定に変えると、決め方と比率を記録する', () {
    final changed = base.copyWith(
      savingsGoal: base.savingsGoal.copyWith(
        contributionMode: SavingsContributionMode.ratio,
        contributionWeights: {memberA: 40, memberB: 60},
      ),
    );

    expect(diffBudgetPlans(base, changed).map((c) => c.describe()), [
      '毎月の貯金の決め方: カスタム → 比率指定',
      'Aの貯金の比率: 0 → 40',
      'Bの貯金の比率: 0 → 60',
    ]);
  });

  test('固定＋残り では、誰をいくらで固定したかを記録する', () {
    final changed = base.copyWith(
      savingsGoal: base.savingsGoal.copyWith(
        contributionMode: SavingsContributionMode.fixed,
        fixedMemberIds: [memberA],
      ),
    );

    expect(diffBudgetPlans(base, changed).map((c) => c.describe()), [
      '毎月の貯金の決め方: カスタム → 固定＋残り',
      'Aの毎月の貯金: 残りを負担 → 固定 50,000円',
    ]);
  });

  test('ボーナス（収入側）の変更', () {
    final changed = base.copyWith(members: [
      base.members[0].copyWith(bonuses: const [Bonus(month: 7, amount: 200000)]),
      base.members[1],
    ]);

    expect(diffBudgetPlans(base, changed).map((c) => c.describe()), [
      'Aのボーナス: なし → 7月 200,000円',
    ]);
  });

  test('BudgetChangeはFirestore用のMapと相互に変換できる', () {
    const change = BudgetChange('家賃', before: '110,000円', after: '120,000円');
    expect(BudgetChange.fromMap(change.toMap()), change);
  });
}
