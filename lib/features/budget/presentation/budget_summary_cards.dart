import 'package:flutter/material.dart';

import '../../../utils/app_theme.dart';
import '../domain/budget_plan.dart';
import '../domain/budget_plan_diff.dart';
import '../domain/budget_result.dart';
import '../domain/money.dart';
import 'budget_widgets.dart';

// ── 家計サマリーのカード群 ──────────────────────────────
// 確定プランのサマリー画面と、シミュレーション画面の結果表示で同じものを使う。
// baseline（確定プランの計算結果）を渡すと、各金額の横に差分を出す。

// 毎月の流れ: 手取り → 生活費口座 → 貯金口座 → 自由に使えるお金 を2人並べて表示
class MonthlyFlowCard extends StatelessWidget {
  final BudgetPlan plan;
  final BudgetResult result;
  final BudgetResult? baseline;

  const MonthlyFlowCard({super.key, required this.plan, required this.result, this.baseline});

  @override
  Widget build(BuildContext context) {
    return BudgetSectionCard(
      title: '毎月の流れ',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, m) in plan.members.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _MemberFlow(member: m, result: result, baseline: baseline)),
          ],
        ],
      ),
    );
  }
}

class _MemberFlow extends StatelessWidget {
  final BudgetMember member;
  final BudgetResult result;
  final BudgetResult? baseline;

  const _MemberFlow({required this.member, required this.result, this.baseline});

  @override
  Widget build(BuildContext context) {
    final id = member.memberId;
    final living = result.livingContributions[id] ?? 0;
    final saving = result.savingsContributions[id] ?? 0;
    final free = result.remainingAfterSavings[id] ?? 0;
    final baseFree = baseline?.remainingAfterSavings[id];

    Widget step(String label, int amount, {bool outflow = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          Text(
            outflow && amount != 0 ? '-${formatYen(amount)}' : formatYen(amount),
            style: const TextStyle(fontSize: 13, color: AppColors.textSecond, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );

    const arrow = Padding(
      padding: EdgeInsets.symmetric(vertical: 1),
      child: Icon(Icons.arrow_downward_rounded, size: 14, color: AppColors.textMuted),
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(member.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: appAccent(context))),
          const SizedBox(height: 6),
          step('手取り', member.monthlyTakeHome),
          arrow,
          step('生活費口座へ', living, outflow: true),
          arrow,
          step('貯金口座へ', saving, outflow: true),
          const Divider(height: 14),
          const Text('自由に使えるお金', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatYen(free),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: free < 0 ? Colors.redAccent : AppColors.textPrimary,
              ),
            ),
          ),
          if (baseFree != null) DiffText(free - baseFree),
        ],
      ),
    );
  }
}

// 生活費口座: 共通支出 − 補助 = 必要額 / 入金 / 余剰・不足
class LivingAccountCard extends StatelessWidget {
  final BudgetPlan plan;
  final BudgetResult result;
  final BudgetResult? baseline;

  const LivingAccountCard({super.key, required this.plan, required this.result, this.baseline});

  @override
  Widget build(BuildContext context) {
    final surplus = result.livingSurplus;
    final base = baseline;
    return BudgetSectionCard(
      title: '生活費口座',
      trailing: Text('入金ルール: ${plan.livingAccount.mode.label}',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in plan.sharedExpenses)
            AmountRow(label: '${e.category.emoji} ${e.label}', value: formatYen(e.monthlyAmount)),
          for (final o in plan.offsets)
            AmountRow(
              label: '↩︎ ${o.label}${o.receivedBy != null ? '（${plan.memberName(o.receivedBy)}が受け取り）' : ''}',
              value: '-${formatYen(o.monthlyAmount)}',
              valueColor: AppColors.success,
            ),
          const Divider(height: 14),
          AmountRow(
            label: '必要額',
            value: formatYen(result.netRequired),
            emphasized: true,
            diff: base == null ? null : DiffText(result.netRequired - base.netRequired, higherIsBetter: false),
          ),
          AmountRow(
            label: '入金（${plan.members.map((m) => '${m.displayName} ${formatAmount(result.livingContributions[m.memberId] ?? 0)}').join(' / ')}）',
            value: formatYen(result.totalLivingContributions),
          ),
          AmountRow(
            label: surplus >= 0
                ? '余り（${plan.livingAccount.surplusHandling.label}）'
                : '不足',
            value: formatSignedYen(surplus),
            emphasized: true,
            valueColor: surplus < 0 ? Colors.redAccent : AppColors.textPrimary,
            diff: base == null ? null : DiffText(surplus - base.livingSurplus),
          ),
        ],
      ),
    );
  }
}

// 貯金: 進捗バー（現在の残高と期限時点の見込み）・年間貯金額・到達見込み
class SavingsGoalCard extends StatelessWidget {
  final BudgetPlan plan;
  final BudgetResult result;
  final BudgetResult? baseline;

  const SavingsGoalCard({super.key, required this.plan, required this.result, this.baseline});

  @override
  Widget build(BuildContext context) {
    final goal = plan.savingsGoal;
    final base = baseline;
    final achieved = result.goalAchievedDate;
    final deadlineMonth = DateTime(goal.deadline.year, goal.deadline.month);
    final achievedInTime = achieved != null && !achieved.firstDay.isAfter(deadlineMonth);

    return BudgetSectionCard(
      title: '貯金',
      trailing: goal.hasTarget
          ? Text('期限 ${formatDateJa(goal.deadline)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (goal.hasTarget) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(formatYen(goal.currentBalance), style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary,
                )),
                Text(' / 目標 ${formatYen(goal.targetAmount)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecond)),
              ],
            ),
            const SizedBox(height: 8),
            SavingsProgressBar(
              current: goal.currentBalance,
              projected: result.projectedAtDeadline,
              target: goal.targetAmount,
            ),
            const SizedBox(height: 6),
            const Row(children: [
              _Legend(color: null, label: '現在'),
              SizedBox(width: 12),
              _Legend(color: AppColors.lavenderSoft, label: '期限時点の見込み'),
            ]),
            const SizedBox(height: 10),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('目標額が未設定です。「編集」から目標額と期限を決めると、到達の見込みを計算します',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.5)),
            ),
          AmountRow(
            label: '期限時点の見込み',
            value: formatYen(result.projectedAtDeadline),
            emphasized: true,
            diff: base == null ? null : DiffText(result.projectedAtDeadline - base.projectedAtDeadline),
          ),
          AmountRow(
            label: '毎月の貯金${result.monthlySurplusToSavings > 0 ? '（余り${formatAmount(result.monthlySurplusToSavings)}円を含む）' : ''}',
            value: formatYen(result.monthlySavingsInflow),
            diff: base == null ? null : DiffText(result.monthlySavingsInflow - base.monthlySavingsInflow),
          ),
          AmountRow(
            label: '年間の貯金（ボーナス${formatAmount(result.annualBonusContributions)}円を含む）',
            value: formatYen(result.annualSavings),
            diff: base == null ? null : DiffText(result.annualSavings - base.annualSavings),
          ),
          if (goal.hasTarget) ...[
            AmountRow(
              label: '目標に届く見込み',
              value: achieved == null ? '届かない見込み' : '${achieved.year}年${achieved.month}月',
              valueColor: achievedInTime ? AppColors.success : Colors.redAccent,
            ),
            if (!achievedInTime && result.requiredMonthlyToHitGoal != null)
              AmountRow(
                label: '期限に間に合う毎月の貯金（2人の合計）',
                value: formatYen(result.requiredMonthlyToHitGoal!),
              ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color? color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 10, height: 10,
      decoration: BoxDecoration(color: color ?? appAccent(context), borderRadius: BorderRadius.circular(3)),
    ),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
  ]);
}

// 現在の残高（濃い色）と期限時点の見込み（淡い色）を重ねた進捗バー
class SavingsProgressBar extends StatelessWidget {
  final int current;
  final int projected;
  final int target;

  const SavingsProgressBar({super.key, required this.current, required this.projected, required this.target});

  @override
  Widget build(BuildContext context) {
    double ratio(int v) => target <= 0 ? 0 : (v / target).clamp(0.0, 1.0);
    final percent = target <= 0 ? 0 : (current * 100 ~/ target);
    return Semantics(
      label: '貯金の進捗 $percent%（期限時点の見込み ${target <= 0 ? 0 : projected * 100 ~/ target}%）',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 12,
          child: Stack(children: [
            Container(color: AppColors.navySurface),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio(projected),
              child: Container(color: AppColors.lavenderSoft),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio(current),
              child: Container(color: appAccent(context)),
            ),
          ]),
        ),
      ),
    );
  }
}
