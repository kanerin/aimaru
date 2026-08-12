import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/app_theme.dart';

// ── 予定の日時入力（開始・終了・終日）────────────────────
// 新規作成フォームとGoogleカレンダーの予定編集で同じ見た目・同じ操作にするため、
// 両画面からこのウィジェットを使う。
//
// 開始を動かすと終了も同じ長さだけ動く。終了が開始より前になる入力は受け付けず、
// 開始と同時刻以前になった場合は開始の1時間後（終日なら同日）へ寄せる。
class EventDateTimeFields extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<DateTime> onEndChanged;
  // null を渡すと終日の切り替えを出さない
  final ValueChanged<bool>? onAllDayChanged;

  const EventDateTimeFields({
    super.key,
    required this.start,
    required this.end,
    required this.allDay,
    required this.onStartChanged,
    required this.onEndChanged,
    this.onAllDayChanged,
  });

  static final _dateFmt = DateFormat('M月d日（E）', 'ja');
  static final _timeFmt = DateFormat('HH:mm');

  Future<DateTime?> _pickDate(BuildContext context, DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return null;
    return DateTime(picked.year, picked.month, picked.day, current.hour, current.minute);
  }

  Future<DateTime?> _pickTime(BuildContext context, DateTime current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      // 目盛りを回して決めるダイヤル表示。以前は選択円と数字が重なって
      // 読めなかったため入力式にしていたが、timePickerTheme で色を
      // 与えて解消したのでダイヤルに戻している（キーボード入力にも切替可）。
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (picked == null) return null;
    return DateTime(current.year, current.month, current.day, picked.hour, picked.minute);
  }

  // 開始を動かしたぶんだけ終了もずらす。長さを保つほうが直感に合う。
  void _moveStart(DateTime next) {
    final span = end.difference(start);
    onStartChanged(next);
    onEndChanged(next.add(span.isNegative ? const Duration(hours: 1) : span));
  }

  void _setEnd(DateTime next) {
    if (allDay) {
      // 終日は同日終了を許す（1日だけの予定）
      final startDay = DateTime(start.year, start.month, start.day);
      final nextDay  = DateTime(next.year, next.month, next.day);
      onEndChanged(nextDay.isBefore(startDay) ? startDay : next);
      return;
    }
    onEndChanged(next.isAfter(start) ? next : start.add(const Duration(hours: 1)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onAllDayChanged != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('終日', style: TextStyle(fontSize: 13, color: AppColors.textSecond)),
              Switch(
                value: allDay,
                onChanged: onAllDayChanged,
                activeThumbColor: appAccent(context),
              ),
            ],
          ),
        _Row(
          label: '開始',
          date: start,
          allDay: allDay,
          onPickDate: () async {
            final v = await _pickDate(context, start);
            if (v != null) _moveStart(v);
          },
          onPickTime: () async {
            final v = await _pickTime(context, start);
            if (v != null) _moveStart(v);
          },
        ),
        const SizedBox(height: 8),
        _Row(
          label: '終了',
          date: end,
          allDay: allDay,
          onPickDate: () async {
            final v = await _pickDate(context, end);
            if (v != null) _setEnd(v);
          },
          onPickTime: () async {
            final v = await _pickTime(context, end);
            if (v != null) _setEnd(v);
          },
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final DateTime date;
  final bool allDay;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  const _Row({
    required this.label,
    required this.date,
    required this.allDay,
    required this.onPickDate,
    required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 36,
        child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ),
      Expanded(
        flex: 3,
        child: OutlinedButton.icon(
          onPressed: onPickDate,
          icon: const Icon(Icons.calendar_today, size: 14),
          label: Text(EventDateTimeFields._dateFmt.format(date)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.hairlineStrong),
          ),
        ),
      ),
      if (!allDay) ...[
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: onPickTime,
            icon: const Icon(Icons.access_time, size: 14),
            label: Text(EventDateTimeFields._timeFmt.format(date)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.hairlineStrong),
            ),
          ),
        ),
      ],
    ]);
  }
}
