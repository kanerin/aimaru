import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/app_theme.dart';
import '../domain/budget_plan.dart';
import '../domain/budget_plan_diff.dart';
import '../domain/budget_result.dart';
import '../domain/money.dart';

// ── 家計画面で共通に使う部品 ─────────────────────────────

// 8,000,000 → '800万'、1,234,567 → '123万'（グラフの目盛り用。細かい桁は省く）
String formatManYen(int amount) {
  final man = (amount / 10000).round();
  return '${formatAmount(man)}万';
}

String formatDateTimeShort(DateTime d) =>
    '${d.year}/${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

// 警告の文言。数字の意味（不足・マイナス・未達）は計算エンジン側の
// BudgetWarning.amountの約束に合わせる。
String budgetWarningMessage(BudgetWarning warning, BudgetPlan plan, BudgetResult result) {
  switch (warning.type) {
    case BudgetWarningType.livingShortfall:
      return '生活費口座が毎月${formatYen(warning.amount)}不足しています';
    case BudgetWarningType.negativeRemaining:
      return '${plan.memberName(warning.memberId, fallback: 'メンバー')}の自由に使えるお金が'
          '毎月${formatYen(warning.amount)}マイナスです';
    case BudgetWarningType.goalNotReached:
      final required = result.requiredMonthlyToHitGoal;
      final hint = required == null
          ? ''
          : '（毎月の貯金を2人で合計${formatYen(required)}にすると間に合います）';
      return '期限（${formatDateJa(plan.savingsGoal.deadline)}）までに目標まで'
          '${formatYen(warning.amount)}足りません$hint';
    case BudgetWarningType.excessiveSurplus:
      final percent = result.netRequired > 0 ? warning.amount * 100 ~/ result.netRequired : 0;
      return '生活費口座の余りが毎月${formatYen(warning.amount)}（必要額の$percent%）あります。'
          '貯金へ移すか、入金額を見直せます';
  }
}

// 角丸・罫線つきのカード（既存画面のカードと同じ見た目）
class BudgetSectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const BudgetSectionCard({super.key, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    decoration: BoxDecoration(
      color: AppColors.navyCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(title, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
            )),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

// 確定プランとの差分（+5,000円 / -5,000円）。0のときは何も出さない。
class DiffText extends StatelessWidget {
  final int diff;
  // 増えると良い数字（自由に使えるお金・貯金）ならtrue。色の向きに使う。
  final bool higherIsBetter;
  final double fontSize;

  const DiffText(this.diff, {super.key, this.higherIsBetter = true, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    if (diff == 0) return const SizedBox.shrink();
    final good = higherIsBetter ? diff > 0 : diff < 0;
    return Text(
      formatSignedYen(diff),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: good ? AppColors.success : Colors.redAccent,
      ),
    );
  }
}

// 1行の「ラベル … 金額」
class AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;
  final Widget? diff;

  const AmountRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueColor,
    this.diff,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(label, style: TextStyle(
            fontSize: emphasized ? 13 : 12.5,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
            color: emphasized ? AppColors.textPrimary : AppColors.textSecond,
          )),
        ),
        if (diff != null) ...[diff!, const SizedBox(width: 6)],
        Text(value, style: TextStyle(
          fontSize: emphasized ? 14 : 12.5,
          fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
          color: valueColor ?? AppColors.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        )),
      ],
    ),
  );
}

// 警告の一覧（無ければ何も出さない）
class BudgetWarningsCard extends StatelessWidget {
  final BudgetPlan plan;
  final BudgetResult result;

  const BudgetWarningsCard({super.key, required this.plan, required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.warnings.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in result.warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB8862B)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      budgetWarningMessage(w, plan, result),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── 金額のスライダー + 数値入力 ────────────────────────────
// スライダーで大まかに動かし、数値入力でぴったりの額にする。どちらから
// 変えても即座にonChangedが呼ばれ、画面側で再計算する。
// スライダーの上限は max か「今の値の1.5倍」の大きい方（上限を超える額を
// 数値入力したときにスライダーが振り切れて動かせなくなるのを防ぐ）。
class AmountSliderField extends StatefulWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int max;
  final int step;
  final String unit;
  // 確定プランでの値。違っていればラベルの横に差分を出す。
  final int? baselineValue;
  final bool higherIsBetter;

  const AmountSliderField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 300000,
    this.step = 1000,
    this.unit = '円',
    this.baselineValue,
    this.higherIsBetter = true,
  });

  @override
  State<AmountSliderField> createState() => _AmountSliderFieldState();
}

class _AmountSliderFieldState extends State<AmountSliderField> {
  late final _controller = TextEditingController(text: formatAmount(widget.value));

  @override
  void didUpdateWidget(covariant AmountSliderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // スライダー側で変わったときだけ入力欄を書き換える（入力中の文字を
    // 毎回整形し直すとカーソルが飛ぶため、値が食い違うときに限る）
    if (parseAmount(_controller.text) != widget.value) {
      _controller.text = formatAmount(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _sliderMax {
    final base = widget.max;
    if (widget.value <= base) return base;
    final grown = (widget.value * 3 ~/ 2);
    return (grown + widget.step - 1) ~/ widget.step * widget.step;
  }

  String _format(int v) => widget.unit == '円' ? formatYen(v) : '${formatAmount(v)}${widget.unit}';

  @override
  Widget build(BuildContext context) {
    final max = _sliderMax;
    final clamped = widget.value.clamp(0, max).toDouble();
    final baseline = widget.baselineValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(widget.label, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                  if (baseline != null && baseline != widget.value)
                    widget.unit == '円'
                        ? DiffText(widget.value - baseline, higherIsBetter: widget.higherIsBetter)
                        : Text('（確定: ${_format(baseline)}）',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            SizedBox(
              width: 132,
              child: TextField(
                controller: _controller,
                textAlign: TextAlign.end,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,０-９\-]'))],
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: widget.unit,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (text) {
                  final v = parseAmount(text);
                  if (v != null && v != widget.value) widget.onChanged(v);
                },
                onSubmitted: (_) => _controller.text = formatAmount(widget.value),
              ),
            ),
          ]),
          // テーマ既定の未選択トラックは背景とほぼ同色で、どこまで動かせるかが
          // 見えないため、トラックの色を明示する
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: appAccent(context),
              inactiveTrackColor: AppColors.lavenderSoft.withValues(alpha: 0.55),
              thumbColor: appAccent(context),
              trackHeight: 4,
            ),
            child: Slider(
            value: clamped,
            min: 0,
            max: max.toDouble(),
            divisions: (max ~/ widget.step).clamp(1, 1000),
            label: _format(widget.value),
            semanticFormatterCallback: (v) => _format(v.round()),
            onChanged: (v) {
              final stepped = (v / widget.step).round() * widget.step;
              if (stepped != widget.value) widget.onChanged(stepped);
            },
            ),
          ),
        ],
      ),
    );
  }
}
