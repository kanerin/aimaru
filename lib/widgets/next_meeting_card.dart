import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/couple_service.dart';
import '../utils/next_meeting_calculator.dart';
import '../utils/app_theme.dart';

// ── 設定画面に置く「次に会う日」カード ────────────────────
// 遠距離・多忙などで頻繁に会えないカップル向けに、次に会える日まで
// カウントダウンする。TimeTreeなど汎用カレンダーには無い、カップル
// 向けアプリ特有の指標（記念日カードと同じ考え方）。
class NextMeetingCard extends StatefulWidget {
  final String coupleId;
  final DateTime? initialNextMeetingDate;
  final ValueChanged<DateTime?>? onSaved;

  // テスト用の注入ポイント。未指定時は本番のCoupleService/DatePicker/現在時刻を使う。
  final CoupleService? coupleServiceOverride;
  final Future<DateTime?> Function(BuildContext context, DateTime? initial)? pickDateOverride;
  final DateTime Function()? nowOverride;

  const NextMeetingCard({
    super.key,
    required this.coupleId,
    this.initialNextMeetingDate,
    this.onSaved,
    this.coupleServiceOverride,
    this.pickDateOverride,
    this.nowOverride,
  });

  @override
  State<NextMeetingCard> createState() => _NextMeetingCardState();
}

class _NextMeetingCardState extends State<NextMeetingCard> {
  CoupleService? _coupleServiceInstance;
  CoupleService get _coupleService =>
      widget.coupleServiceOverride ?? (_coupleServiceInstance ??= CoupleService());

  late DateTime? _nextMeetingDate = widget.initialNextMeetingDate;
  bool _saving = false;

  DateTime get _now => (widget.nowOverride ?? DateTime.now)();

  @override
  void didUpdateWidget(covariant NextMeetingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 親（設定画面）が非同期でカップル情報を読み込み終えた後に
    // initialNextMeetingDate がnullから確定値へ変わるケースがあるため、
    // その変化だけ追従する。
    if (oldWidget.initialNextMeetingDate != widget.initialNextMeetingDate) {
      _nextMeetingDate = widget.initialNextMeetingDate;
    }
  }

  Future<void> _save(DateTime? date) async {
    setState(() => _saving = true);
    try {
      await _coupleService.setNextMeetingDate(widget.coupleId, date);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('次に会う日の保存に失敗しました')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _nextMeetingDate = date;
      _saving = false;
    });
    widget.onSaved?.call(date);
  }

  Future<void> _pickDate() async {
    final now = _now;
    final picked = widget.pickDateOverride != null
        ? await widget.pickDateOverride!(context, _nextMeetingDate)
        : await showDatePicker(
            context: context,
            initialDate: _nextMeetingDate ?? now,
            firstDate: now,
            lastDate: DateTime(now.year + 5),
          );
    if (picked == null || !mounted) return;
    await _save(picked);
  }

  @override
  Widget build(BuildContext context) {
    final nextMeetingDate = _nextMeetingDate;
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
              const Text('🗓️ 次に会う日', style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
              )),
              Row(children: [
                if (nextMeetingDate != null)
                  IconButton(
                    tooltip: '次に会う日をクリア',
                    onPressed: _saving ? null : () => _save(null),
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textSecond),
                  ),
                IconButton(
                  tooltip: nextMeetingDate == null ? '次に会う日を設定' : '次に会う日を変更',
                  onPressed: _saving ? null : _pickDate,
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(nextMeetingDate == null ? Icons.add : Icons.edit_outlined,
                          size: 18, color: AppColors.textSecond),
                ),
              ]),
            ],
          ),
          if (nextMeetingDate == null)
            const Text(
              '次に会う予定の日を設定すると、会えるまでの日数が表示されます',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5),
            )
          else
            _NextMeetingSummaryView(nextMeetingDate: nextMeetingDate, today: _now),
        ],
      ),
    );
  }
}

class _NextMeetingSummaryView extends StatelessWidget {
  final DateTime nextMeetingDate;
  final DateTime today;
  const _NextMeetingSummaryView({required this.nextMeetingDate, required this.today});

  @override
  Widget build(BuildContext context) {
    final daysUntil = daysUntilNextMeeting(nextMeetingDate, today);
    final String message;
    if (daysUntil > 0) {
      message = '💛 会えるまであと$daysUntil日';
    } else if (daysUntil == 0) {
      message = '🎉 今日、会えます！';
    } else {
      message = '予定の日を過ぎています。日付を更新しましょう';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          DateFormat('yyyy年M月d日').format(nextMeetingDate),
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          style: daysUntil < 0
              ? const TextStyle(fontSize: 11.5, color: AppColors.textSecond)
              : TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: appAccent(context)),
        ),
      ],
    );
  }
}
