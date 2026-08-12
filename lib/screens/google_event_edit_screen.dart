import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/google_calendar_service.dart';
import '../services/google_calendar_cache_service.dart';
import '../utils/app_theme.dart';

// ── Googleカレンダー由来の自分の予定を編集する画面 ──
// AimaruEventではなく、Google Calendar上の実データ(GCalEventSummary)を直接編集する。
class GoogleEventEditScreen extends StatefulWidget {
  final String coupleId;
  final GCalEventSummary event;

  const GoogleEventEditScreen({super.key, required this.coupleId, required this.event});

  @override
  State<GoogleEventEditScreen> createState() => _GoogleEventEditScreenState();
}

class _GoogleEventEditScreenState extends State<GoogleEventEditScreen> {
  final _calendarService = GoogleCalendarService();
  final _cacheService    = GoogleCalendarCacheService();

  late final _titleCtrl = TextEditingController(text: widget.event.title);
  late DateTime _start = widget.event.start;
  late DateTime _end   = widget.event.end;
  bool _saving   = false;
  bool _deleting = false;

  bool get _busy => _saving || _deleting;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _start,
      firstDate: DateTime(2020), lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final duration = _end.difference(_start);
      _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute);
      _end   = _start.add(duration.isNegative ? const Duration(hours: 1) : duration);
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final target = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(target),
      // ダイヤル表示だと選択円と数字が重なって見づらいため、入力式にする
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked == null) return;
    setState(() {
      final updated = DateTime(target.year, target.month, target.day, picked.hour, picked.minute);
      if (isStart) {
        _start = updated;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        _end = updated;
      }
    });
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タイトルを入力してください')),
      );
      return;
    }
    setState(() => _saving = true);

    final ok = await _calendarService.updateGoogleEvent(
      eventId: widget.event.id,
      title: _titleCtrl.text.trim(),
      start: _start,
      end: _end,
      allDay: widget.event.allDay,
    );

    if (!ok) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('更新に失敗しました。もう一度お試しください')),
        );
      }
      return;
    }

    await _resyncCache(_start);

    if (mounted) Navigator.of(context).pop(true);
  }

  // カップル間で共有しているキャッシュにも反映されるよう、周辺期間を再同期
  Future<void> _resyncCache(DateTime around) async {
    final rangeStart = DateTime(around.year, around.month - 1, 1);
    final rangeEnd   = DateTime(around.year, around.month + 2, 0, 23, 59);
    final refreshed  = await _calendarService.fetchEvents(start: rangeStart, end: rangeEnd);
    await _cacheService.pushMyEvents(widget.coupleId, refreshed);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('この予定を削除しますか？'),
        content: Text(
          '「${widget.event.title}」をGoogleカレンダーから削除します。この操作は取り消せません。',
          style: const TextStyle(color: AppColors.textSecond, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除する', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await _calendarService.deleteEvent(widget.event.id);
      // 削除は元の日付の周辺を再取得しないとキャッシュに残り続ける
      await _resyncCache(widget.event.start);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr  = DateFormat('M月d日（E）', 'ja').format(_start);
    final startStr = DateFormat('HH:mm').format(_start);
    final endStr   = DateFormat('HH:mm').format(_end);

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: const Text('Googleカレンダーの予定を編集'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: appAccent(context)),
                  )
                : Text('保存', style: TextStyle(color: appAccentSoft(context), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.event, size: 14, color: Color(0xFF4285F4)),
              SizedBox(width: 6),
              Text('Googleカレンダーの予定', style: TextStyle(fontSize: 11, color: Color(0xFF4285F4))),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: 'タイトル'),
          ),
          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 14),
            label: Text(dateStr),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.hairlineStrong),
            ),
          ),

          if (!widget.event.allDay) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(true),
                  icon: const Icon(Icons.access_time, size: 14),
                  label: Text('開始 $startStr'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.hairlineStrong),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(false),
                  icon: const Icon(Icons.access_time, size: 14),
                  label: Text('終了 $endStr'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.hairlineStrong),
                  ),
                ),
              ),
            ]),
          ],

          const SizedBox(height: 28),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _delete,
              child: _deleting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                  : const Text('この予定を削除', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
