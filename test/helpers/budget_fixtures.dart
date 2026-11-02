import 'package:aimaru/features/budget/domain/budget_plan.dart';

// 家計機能のテストで共通に使うプラン。
//
// 実際の2人の家計ルールをそのまま入力にしたもの（計算エンジンの期待値は
// この入力に対して2人で確認済みの数字）:
//   - メンバーA: 手取り 180,000 / メンバーB: 手取り 400,000
//   - 共通支出: 家賃 110,000、水道 10,000、光熱費 15,000、食費/日用品（お酒以外）70,000
//   - 補助: 家賃補助 30,000（Bが受け取る）
//   - 生活費口座: 固定額 A 60,000 / B 150,000、余剰は口座に残す
//   - 貯金: 目標 8,000,000、毎月 A 50,000 / B 90,000、ボーナス入金 年2回 各200,000
//
// ボーナス入金を誰が入れるかは期待値に影響しない（年間合計だけが効く）ので、
// ここではBの6月・12月としている。期限・開始月・現在の残高も期待値に
// 影響しないため、推移を検証するテストではそれぞれ上書きして使う。
const memberA = 'A';
const memberB = 'B';

BudgetPlan realCouplePlan({
  SurplusHandling surplusHandling = SurplusHandling.keep,
  int contributionA = 60000,
  int contributionB = 150000,
  int takeHomeA = 180000,
  int takeHomeB = 400000,
  int savingsA = 50000,
  int savingsB = 90000,
  int targetAmount = 8000000,
  int currentBalance = 0,
  DateTime? startDate,
  DateTime? deadline,
  String id = '',
  String name = '確定プラン',
  bool isActive = true,
}) =>
    BudgetPlan(
      id: id,
      name: name,
      isActive: isActive,
      members: [
        BudgetMember(memberId: memberA, displayName: 'A', monthlyTakeHome: takeHomeA),
        BudgetMember(
          memberId: memberB,
          displayName: 'B',
          monthlyTakeHome: takeHomeB,
          bonuses: const [
            Bonus(month: 6, amount: 500000, payDay: 30),
            Bonus(month: 12, amount: 500000, payDay: 10),
          ],
        ),
      ],
      sharedExpenses: const [
        SharedExpense(id: 'rent', label: '家賃', monthlyAmount: 110000, category: ExpenseCategory.housing),
        SharedExpense(id: 'water', label: '水道', monthlyAmount: 10000, category: ExpenseCategory.utilities),
        SharedExpense(id: 'energy', label: '光熱費', monthlyAmount: 15000, category: ExpenseCategory.utilities),
        SharedExpense(
          id: 'groceries',
          label: '食費/日用品（お酒以外）',
          monthlyAmount: 70000,
          category: ExpenseCategory.food,
        ),
      ],
      offsets: const [
        BudgetOffset(id: 'rent-aid', label: '家賃補助', monthlyAmount: 30000, receivedBy: memberB),
      ],
      livingAccount: LivingAccountRule(
        mode: LivingAccountMode.fixed,
        contributions: {memberA: contributionA, memberB: contributionB},
        surplusHandling: surplusHandling,
      ),
      savingsGoal: SavingsGoal(
        targetAmount: targetAmount,
        startDate: startDate ?? DateTime(2026, 11, 1),
        deadline: deadline ?? DateTime(2029, 10, 31),
        monthlyContributions: {memberA: savingsA, memberB: savingsB},
        bonusContributions: const [
          BonusContribution(memberId: memberB, month: 6, amount: 200000),
          BonusContribution(memberId: memberB, month: 12, amount: 200000),
        ],
        currentBalance: currentBalance,
      ),
    );
