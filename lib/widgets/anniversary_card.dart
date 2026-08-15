import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/couple_service.dart';
import '../utils/anniversary_calculator.dart';
import '../utils/app_theme.dart';

// ── 設定画面に置く「記念日」カード ──────────────────────
// 付き合い始めた日を設定すると、経過日数・100日ごとの節目・周年までの
// 日数を表示する。TimeTreeなど汎用カレンダーには無い、カップル向け
// アプリ特有の指標（COUPPLYなど競合が訴求している）。
class AnniversaryCard extends StatefulWidget {
  final String coupleId;
  final DateTime? initialAnniversary;
  final ValueChanged<DateTime>? onSaved;

  // テスト用の注入ポイント。未指定時は本番のCoupleService/DatePicker/現在時刻を使う。
  final CoupleService? coupleServiceOverride;
  final Future<DateTime?> Function(BuildContext context, DateTime? initial)? pickDateOverride;
  final DateTime Function()? nowOverride;

  const AnniversaryCard({
    super.key,
    required this.coupleId,
    this.initialAnniversary,
    this.onSaved,
    this.coupleServiceOverride,
    this.pickDateOverride,
    this.nowOverride,
  });

  @override
  State<AnniversaryCard> createState() => _AnniversaryCardState();
}

class _AnniversaryCardState extends State<AnniversaryCard> {
  CoupleService? _coupleServiceInstance;
  CoupleService get _coupleService =>
      widget.coupleServiceOverride ?? (_coupleServiceInstance ??= CoupleService());

  late DateTime? _anniversary = widget.initialAnniversary;
  bool _saving = false;

  DateTime get _now => (widget.nowOverride ?? DateTime.now)();

  @override
  void didUpdateWidget(covariant AnniversaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 親（設定画面）が非同期でカップル情報を読み込み終えた後に initialAnniversary が
    // nullから確定値へ変わるケースがあるため、その変化だけ追従する。
    if (oldWidget.initialAnniversary != widget.initialAnniversary) {
      _anniversary = widget.initialAnniversary;
    }
  }

  Future<void> _pickDate() async {
    final now = _now;
    final picked = widget.pickDateOverride != null
        ? await widget.pickDateOverride!(context, _anniversary)
        : await showDatePicker(
            context: context,
            initialDate: _anniversary ?? now,
            firstDate: DateTime(now.year - 50),
            lastDate: now, // 未来の記念日は選べない（daysTogetherの計算を単純に保つため）
          );
    if (picked == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await _coupleService.setAnniversary(widget.coupleId, picked);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('記念日の保存に失敗しました')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _anniversary = picked;
      _saving = false;
    });
    widget.onSaved?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final anniversary = _anniversary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🎉 記念日', style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
              )),
              IconButton(
                tooltip: anniversary == null ? '記念日を設定' : '記念日を変更',
                onPressed: _saving ? null : _pickDate,
                icon: _saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(anniversary == null ? Icons.add : Icons.edit_outlined,
                        size: 18, color: AppColors.textSecond),
              ),
            ],
          ),
          if (anniversary == null)
            const Text(
              '付き合い始めた日を設定すると、経過日数や次の記念日までの日数が表示されます',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5),
            )
          else
            _AnniversarySummaryView(anniversary: anniversary, today: _now),
        ],
      ),
    );
  }
}

class _AnniversarySummaryView extends StatelessWidget {
  final DateTime anniversary;
  final DateTime today;
  const _AnniversarySummaryView({required this.anniversary, required this.today});

  @override
  Widget build(BuildContext context) {
    final summary = summarizeAnniversary(anniversary, today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          '${DateFormat('yyyy年M月d日').format(anniversary)}から',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          '💕 付き合って${summary.daysTogether}日目',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: appAccent(context)),
        ),
        const SizedBox(height: 6),
        Text(
          summary.daysUntilNextMilestone == 0
              ? '🎉 今日は${summary.nextMilestoneDay}日記念日です！'
              : '${summary.nextMilestoneDay}日記念日まであと${summary.daysUntilNextMilestone}日',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecond),
        ),
        Text(
          summary.daysUntilNextAnniversary == 0
              ? '🎉 今日は${summary.nextAnniversaryYearCount}周年記念日です！'
              : '${summary.nextAnniversaryYearCount}周年まであと${summary.daysUntilNextAnniversary}日',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecond),
        ),
      ],
    );
  }
}
