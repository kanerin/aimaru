import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/app_theme.dart';
import 'aimaru_time_picker.dart';

// ── 開始を動かしたときの終了の追従先 ────────────────────
// 長さを保つほうが直感に合う。元の長さが負（壊れた状態）なら1時間に正す。
// ウィジェットから切り出してあるのは、ここが単体テストの対象になるため。
DateTime followStart({
  required DateTime oldStart,
  required DateTime oldEnd,
  required DateTime newStart,
}) {
  final span = oldEnd.difference(oldStart);
  return newStart.add(span.isNegative ? const Duration(hours: 1) : span);
}

// ── 終了として受け付ける値 ──────────────────────────
// 終了が開始より前になる入力は通さない。終日は「同じ日に終わる」＝1日だけの
// 予定として正当なので、日付単位で比較する。
DateTime clampEnd({
  required DateTime start,
  required DateTime end,
  required bool allDay,
}) {
  if (allDay) {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay   = DateTime(end.year, end.month, end.day);
    return endDay.isBefore(startDay) ? startDay : endDay;
  }
  return end.isAfter(start) ? end : start.add(const Duration(hours: 1));
}

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
    // Flutter標準のshowTimePickerは選択円が48dp固定で、数字より大きく
    // 隣の目盛りに被って読みにくかった。大きさを決められる自前の
    // ダイヤル（widgets/aimaru_time_picker.dart）を使う。
    final picked = await showAimaruTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return null;
    return DateTime(current.year, current.month, current.day, picked.hour, picked.minute);
  }

  void _moveStart(DateTime next) {
    onStartChanged(next);
    onEndChanged(followStart(oldStart: start, oldEnd: end, newStart: next));
  }

  void _setEnd(DateTime next) {
    onEndChanged(clampEnd(start: start, end: next, allDay: allDay));
  }

  void _setAllDay(bool next) {
    onAllDayChanged!(next);
    if (next) return;
    // 終日の間は開始も終了も同じ日の0:00になっている（1日だけの予定は
    // 開始日＝最終日）。そのまま時刻指定へ戻すと end == start になり、
    // Googleは時刻指定の予定に end > start を求めるため保存できない。
    onEndChanged(clampEnd(start: start, end: end, allDay: false));
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
                onChanged: _setAllDay,
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
