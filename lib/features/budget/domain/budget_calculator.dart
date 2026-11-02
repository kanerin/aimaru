import 'budget_plan.dart';
import 'budget_result.dart';
import 'year_month.dart';

// ── 家計の計算エンジン ─────────────────────────────────
// BudgetPlan（入力）→ BudgetResult（出力）の純粋関数。UI・Firebaseに依存せず、
// 同じ入力からは必ず同じ結果を返す（シミュレーション画面はスライダーを
// 動かすたびにこれを呼び直して即時に再計算する）。
//
// 計算の約束事:
// - 金額はすべて整数（円）。比率配分の端数は最大剰余法で配り、合計を必ず
//   「必要額 + バッファ」に一致させる（1円のずれも出さない）。
// - 貯金推移は月単位。startDateの月〜deadlineの月の各月に、毎月の貯金入金・
//   その月のボーナス入金・（toSavingsなら）生活費口座の余剰が入るものとして積む。
// - 補助（offsets）は手取りとは別に生活費口座の必要額を直接減らすお金として扱い、
//   受け取る人の手取り・自由に使えるお金には足さない。
class BudgetCalculator {
  // 「バッファが大きすぎる」と判定する余剰の割合（必要額に対する%）。
  // 口座に残す設定で余剰がこれを超えると、貯金へ回す・入金額を見直す余地がある。
  static const excessiveSurplusPercent = 15;

  // 目標到達月を探すときに先読みする最大月数（期限を過ぎても探す。50年）。
  // 入金がほぼ無いプランで永久ループにしないための上限。
  static const maxGoalSearchMonths = 600;

  const BudgetCalculator._();

  static BudgetResult calculate(BudgetPlan plan) {
    final members = plan.members;

    // ── 生活費口座 ──
    final totalSharedExpenses = _sum(plan.sharedExpenses.map((e) => e.monthlyAmount));
    final totalOffsets = _sum(plan.offsets.map((o) => o.monthlyAmount));
    final netRequired = totalSharedExpenses - totalOffsets;

    final livingContributions = _livingContributions(plan, netRequired);
    final totalLivingContributions = _sum(livingContributions.values);
    final livingSurplus = totalLivingContributions - netRequired;

    // ── 各自のお金 ──
    final savingsGoal = plan.savingsGoal;
    final remainingAfterLiving = <String, int>{};
    final savingsContributions = <String, int>{};
    final remainingAfterSavings = <String, int>{};
    for (final m in members) {
      final living = livingContributions[m.memberId] ?? 0;
      final saving = savingsGoal.monthlyContributions[m.memberId] ?? 0;
      remainingAfterLiving[m.memberId] = m.monthlyTakeHome - living;
      savingsContributions[m.memberId] = saving;
      remainingAfterSavings[m.memberId] = m.monthlyTakeHome - living - saving;
    }

    // ── 貯金 ──
    // 不足しているときに貯金口座から生活費口座へ逆流させる、という扱いはしない
    // （不足は警告で知らせる）。移すのは余剰があるときだけ。
    final monthlySurplusToSavings =
        plan.livingAccount.surplusHandling == SurplusHandling.toSavings && livingSurplus > 0
            ? livingSurplus
            : 0;
    final monthlySavingsInflow = _sum(savingsContributions.values) + monthlySurplusToSavings;
    final annualBonusContributions = _sum(savingsGoal.bonusContributions.map((b) => b.amount));
    final annualSavings = monthlySavingsInflow * 12 + annualBonusContributions;

    final start = YearMonth.fromDate(savingsGoal.startDate);
    final deadline = YearMonth.fromDate(savingsGoal.deadline);
    // 期限が開始より前なら推移は空（入金する月が無い）
    final periodMonths = start.isAfter(deadline) ? 0 : start.monthsUntil(deadline) + 1;

    int inflowFor(YearMonth ym) =>
        monthlySavingsInflow + _bonusInflowForMonth(savingsGoal.bonusContributions, ym.month);

    final projection = <ProjectionPoint>[];
    var balance = savingsGoal.currentBalance;
    for (var i = 0; i < periodMonths; i++) {
      final ym = start.addMonths(i);
      balance += inflowFor(ym);
      projection.add(ProjectionPoint(ym, balance));
    }
    final projectedAtDeadline = projection.isEmpty ? savingsGoal.currentBalance : projection.last.balance;

    final goalAchievedDate = _goalAchievedDate(savingsGoal, start, inflowFor);
    final requiredMonthlyToHitGoal = _requiredMonthly(
      savingsGoal: savingsGoal,
      start: start,
      periodMonths: periodMonths,
      monthlySurplusToSavings: monthlySurplusToSavings,
    );

    // ── 警告 ──
    final warnings = <BudgetWarning>[];
    if (livingSurplus < 0) {
      warnings.add(BudgetWarning(type: BudgetWarningType.livingShortfall, amount: -livingSurplus));
    }
    for (final m in members) {
      final remaining = remainingAfterSavings[m.memberId]!;
      if (remaining < 0) {
        warnings.add(BudgetWarning(
          type: BudgetWarningType.negativeRemaining,
          memberId: m.memberId,
          amount: -remaining,
        ));
      }
    }
    if (savingsGoal.hasTarget && projectedAtDeadline < savingsGoal.targetAmount) {
      warnings.add(BudgetWarning(
        type: BudgetWarningType.goalNotReached,
        amount: savingsGoal.targetAmount - projectedAtDeadline,
      ));
    }
    // 毎月貯金へ移す設定なら余剰は貯金に回るので、大きくても問題にしない。
    if (plan.livingAccount.surplusHandling == SurplusHandling.keep &&
        netRequired > 0 &&
        livingSurplus * 100 > netRequired * excessiveSurplusPercent) {
      warnings.add(BudgetWarning(type: BudgetWarningType.excessiveSurplus, amount: livingSurplus));
    }

    return BudgetResult(
      totalSharedExpenses:      totalSharedExpenses,
      totalOffsets:             totalOffsets,
      netRequired:              netRequired,
      livingContributions:      livingContributions,
      totalLivingContributions: totalLivingContributions,
      livingSurplus:            livingSurplus,
      remainingAfterLiving:     remainingAfterLiving,
      savingsContributions:     savingsContributions,
      remainingAfterSavings:    remainingAfterSavings,
      monthlySurplusToSavings:  monthlySurplusToSavings,
      monthlySavingsInflow:     monthlySavingsInflow,
      annualBonusContributions: annualBonusContributions,
      annualSavings:            annualSavings,
      startingBalance:          savingsGoal.currentBalance,
      projection:               List.unmodifiable(projection),
      projectedAtDeadline:      projectedAtDeadline,
      goalAchievedDate:         goalAchievedDate,
      requiredMonthlyToHitGoal: requiredMonthlyToHitGoal,
      warnings:                 List.unmodifiable(warnings),
    );
  }

  // ── 生活費口座への各自の入金額 ──────────────────────────
  static Map<String, int> _livingContributions(BudgetPlan plan, int netRequired) {
    final rule = plan.livingAccount;
    final members = plan.members;
    switch (rule.mode) {
      case LivingAccountMode.fixed:
        return {for (final m in members) m.memberId: rule.contributions[m.memberId] ?? 0};
      case LivingAccountMode.ratio:
      case LivingAccountMode.incomeProportional:
        // 補助が支出を上回って必要額がマイナスになっても、入金をマイナス
        // （口座から各自へ払い戻し）にはしない。
        final total = (netRequired > 0 ? netRequired : 0) + (rule.bufferAmount > 0 ? rule.bufferAmount : 0);
        final weights = [
          for (final m in members)
            rule.mode == LivingAccountMode.ratio
                ? (rule.contributions[m.memberId] ?? 0)
                : m.monthlyTakeHome,
        ];
        final shares = allocateByWeights(total, weights);
        return {for (var i = 0; i < members.length; i++) members[i].memberId: shares[i]};
    }
  }

  // totalを重みの比で整数に分ける（最大剰余法）。合計は必ずtotalに一致する。
  // 重みが全員0（または負）のときは均等に分ける。端数の1円は剰余の大きい順、
  // 同じなら並び順の早い人に配る（同じ入力なら必ず同じ結果になるように）。
  static List<int> allocateByWeights(int total, List<int> weights) {
    if (weights.isEmpty) return const [];
    final w = [for (final x in weights) x > 0 ? x : 0];
    var sumW = _sum(w);
    final effective = sumW == 0 ? List.filled(w.length, 1) : w;
    if (sumW == 0) sumW = w.length;

    final shares = <int>[];
    final remainders = <int>[];
    for (final x in effective) {
      shares.add(total * x ~/ sumW);
      remainders.add(total * x % sumW);
    }
    var leftover = total - _sum(shares);
    final order = List.generate(w.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = remainders[b].compareTo(remainders[a]);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    for (final i in order) {
      if (leftover <= 0) break;
      shares[i]++;
      leftover--;
    }
    return shares;
  }

  static int _bonusInflowForMonth(List<BonusContribution> bonuses, int month) =>
      _sum(bonuses.where((b) => b.month == month).map((b) => b.amount));

  static YearMonth? _goalAchievedDate(
    SavingsGoal goal,
    YearMonth start,
    int Function(YearMonth) inflowFor,
  ) {
    if (!goal.hasTarget) return null;
    // 開始時点で既に到達しているなら、開始月を到達月とする
    if (goal.currentBalance >= goal.targetAmount) return start;
    var balance = goal.currentBalance;
    for (var i = 0; i < maxGoalSearchMonths; i++) {
      final ym = start.addMonths(i);
      balance += inflowFor(ym);
      if (balance >= goal.targetAmount) return ym;
    }
    return null;
  }

  static int? _requiredMonthly({
    required SavingsGoal savingsGoal,
    required YearMonth start,
    required int periodMonths,
    required int monthlySurplusToSavings,
  }) {
    if (!savingsGoal.hasTarget) return null;
    var bonusInPeriod = 0;
    for (var i = 0; i < periodMonths; i++) {
      bonusInPeriod += _bonusInflowForMonth(savingsGoal.bonusContributions, start.addMonths(i).month);
    }
    final need = savingsGoal.targetAmount -
        savingsGoal.currentBalance -
        bonusInPeriod -
        monthlySurplusToSavings * periodMonths;
    if (need <= 0) return 0;
    if (periodMonths == 0) return null;
    // 切り上げ（1円でも足りないと期限に間に合わないため）
    return (need + periodMonths - 1) ~/ periodMonths;
  }

  static int _sum(Iterable<int> values) => values.fold(0, (sum, v) => sum + v);
}
