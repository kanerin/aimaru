import 'budget_plan.dart';

// ── ボーナスからの貯金を「年に何回・1回いくら」で扱う ─────────────
// 保存の形は従来どおり月ごとの BonusContribution のリスト（計算エンジン・
// 貯金推移はどの月に入るかを使う）。画面では各自「年◯回 × ◯円」で
// 入力できるよう、ここで回数・金額とリストを相互に変換する。

class BonusSavingsSetting {
  final int timesPerYear;
  // 1回あたりの額（月ごとに額が違う場合は最初の月の額）
  final int amountPerTime;
  // 月ごとに額が違う（項目編集で個別に変えた）とき false
  final bool uniformAmount;
  final List<int> months;

  const BonusSavingsSetting({
    required this.timesPerYear,
    required this.amountPerTime,
    required this.uniformAmount,
    required this.months,
  });

  int get annualAmount => timesPerYear * amountPerTime;
}

const maxBonusSavingsTimesPerYear = 12;

// 年n回を、12月で終わる等間隔の月に置く（1回→12月、2回→6・12月、3回→4・8・12月）
List<int> evenlySpacedMonths(int times) {
  if (times <= 0) return const [];
  final n = times.clamp(1, 12);
  return [for (var i = 1; i <= n; i++) (12 * i / n).round()];
}

BonusSavingsSetting bonusSavingsOf(SavingsGoal goal, String memberId) {
  final entries = goal.bonusContributions.where((b) => b.memberId == memberId).toList()
    ..sort((a, b) => a.month.compareTo(b.month));
  return BonusSavingsSetting(
    timesPerYear: entries.length,
    amountPerTime: entries.isEmpty ? 0 : entries.first.amount,
    uniformAmount: entries.every((b) => b.amount == entries.first.amount),
    months: [for (final b in entries) b.month],
  );
}

// memberIdのボーナスからの貯金を「年timesPerYear回 × amountPerTime円」にした
// リストを返す（他のメンバーの分はそのまま）。入金する月は次の順で決める:
//   1. 回数が今と同じなら今の月のまま（項目編集で決めた月を崩さない）
//   2. そのメンバーの収入側のボーナスの回数と同じなら、ボーナスの支給月
//   3. それ以外は12月で終わる等間隔の月
List<BonusContribution> withBonusSavings(
  BudgetPlan plan,
  String memberId, {
  required int timesPerYear,
  required int amountPerTime,
}) {
  final times = timesPerYear.clamp(0, maxBonusSavingsTimesPerYear);
  final current = bonusSavingsOf(plan.savingsGoal, memberId);
  final incomeMonths = {for (final b in plan.memberById(memberId)?.bonuses ?? const <Bonus>[]) b.month}
      .toList()
    ..sort();

  final List<int> months;
  if (current.timesPerYear == times) {
    months = current.months;
  } else if (incomeMonths.length == times) {
    months = incomeMonths;
  } else {
    months = evenlySpacedMonths(times);
  }

  final memberOrder = [for (final m in plan.members) m.memberId];
  int orderOf(String id) {
    final i = memberOrder.indexOf(id);
    return i < 0 ? memberOrder.length : i;
  }

  return [
    ...plan.savingsGoal.bonusContributions.where((b) => b.memberId != memberId),
    for (final month in months) BonusContribution(memberId: memberId, month: month, amount: amountPerTime),
  ]..sort((a, b) {
      final byMonth = a.month.compareTo(b.month);
      return byMonth != 0 ? byMonth : orderOf(a.memberId).compareTo(orderOf(b.memberId));
    });
}
