import 'package:flutter/material.dart';

import '../../../utils/app_theme.dart';
import '../domain/budget_calculator.dart';
import '../domain/budget_plan.dart';
import '../domain/budget_result.dart';
import '../domain/money.dart';
import '../domain/year_month.dart';
import 'budget_projection_chart.dart';

// ── 貯金推移グラフ ─────────────────────────────────────
// 確定プランとシミュレーションの月次残高を重ねて比べる。どのプランを
// 重ねるかはチップで切り替える（多すぎると線が読めないため）。
class BudgetProjectionScreen extends StatefulWidget {
  final List<BudgetPlan> plans;

  const BudgetProjectionScreen({super.key, required this.plans});

  @override
  State<BudgetProjectionScreen> createState() => _BudgetProjectionScreenState();
}

class _BudgetProjectionScreenState extends State<BudgetProjectionScreen> {
  // 確定プランが先頭に来る並び（BudgetPlanRepository.watchPlans）を前提に、
  // 最初の数件だけ重ねた状態で開く
  static const _initiallyShown = 3;

  late final Set<int> _shown = {
    for (var i = 0; i < widget.plans.length && i < _initiallyShown; i++) i,
  };

  late final List<BudgetResult> _results = [
    for (final p in widget.plans) BudgetCalculator.calculate(p),
  ];

  Color _colorFor(BuildContext context, int index) {
    final palette = <Color>[
      appAccent(context),
      AppColors.pinkAccent,
      AppColors.success,
      AppColors.partnerColor,
      const Color(0xFF6FA0DC),
      AppColors.textSecond,
    ];
    return palette[index % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final series = [
      for (final i in _shown.toList()..sort())
        ProjectionSeries(
          label: widget.plans[i].name,
          color: _colorFor(context, i),
          points: _results[i].projection,
          startingBalance: _results[i].startingBalance,
          start: YearMonth.fromDate(widget.plans[i].savingsGoal.startDate),
          targetAmount: widget.plans[i].savingsGoal.hasTarget
              ? widget.plans[i].savingsGoal.targetAmount
              : null,
        ),
    ];

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('貯金の推移')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 16, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.navyCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: BudgetProjectionChart(series: series),
          ),
          const SizedBox(height: 8),
          const Text('点線は目標額。各月の入金（毎月の貯金・ボーナス・余りの移し替え）を反映した月末の残高です',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textMuted, height: 1.5)),
          const SizedBox(height: 16),
          const Text('比べるプラン',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (var i = 0; i < widget.plans.length; i++)
            _buildPlanRow(context, i),
        ],
      ),
    );
  }

  Widget _buildPlanRow(BuildContext context, int i) {
    final plan = widget.plans[i];
    final result = _results[i];
    final shown = _shown.contains(i);
    final color = _colorFor(context, i);
    final achieved = result.goalAchievedDate;
    // CheckboxListTile（ListTile系）はMaterial祖先の上でないとタップ時の
    // インクが描画されないため、背景色はContainerではなくMaterialに持たせる
    // （todos_screen.dartと同じ）。
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: shown ? AppColors.navyCard : AppColors.navySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: shown ? color.withValues(alpha: 0.6) : AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: CheckboxListTile(
          value: shown,
          activeColor: color,
          onChanged: (v) =>
              setState(() => v == true ? _shown.add(i) : _shown.remove(i)),
          controlAffinity: ListTileControlAffinity.leading,
          title: Row(children: [
            Container(width: 14, height: 3, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(plan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
            if (plan.isActive) ...[
              const SizedBox(width: 6),
              Text('確定',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: appAccent(context),
                      fontWeight: FontWeight.w700)),
            ],
          ]),
          subtitle: Text(
            '期限時点 ${formatYen(result.projectedAtDeadline)}'
            '${achieved == null ? '' : '・目標到達 ${achieved.year}年${achieved.month}月'}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecond),
          ),
        ),
      ),
    );
  }
}
