import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/google_calendar_service.dart';
import '../services/google_calendar_cache_service.dart';
import '../utils/app_theme.dart';
import '../widgets/event_datetime_fields.dart';
import '../widgets/section_label.dart';

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
  // 終日予定の end は「翌日」を指す排他的な値で届くので、表示上は最終日へ戻す
  late final DateTime _initialEnd = widget.event.allDay
      ? _exclusiveEndToLastDay(widget.event.start, widget.event.end)
      : widget.event.end;
  late DateTime _end = _initialEnd;
  late bool _allDay = widget.event.allDay;
  bool _saving   = false;
  bool _deleting = false;

  bool get _busy => _saving || _deleting;

  static DateTime _exclusiveEndToLastDay(DateTime start, DateTime end) {
    final last = end.subtract(const Duration(days: 1));
    return last.isBefore(start) ? start : last;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タイトルを入力してください')),
      );
      return;
    }
    setState(() => _saving = true);

    // 日時を触っていないなら送らない。送り直すと終日/時刻指定を取り違えたときに
    // 元の予定を壊してしまうため、変更したときだけ差し替える。
    final dateChanged = !_start.isAtSameMomentAs(widget.event.start) ||
        !_end.isAtSameMomentAs(_initialEnd) ||
        _allDay != widget.event.allDay;

    final result = await _calendarService.updateGoogleEvent(
      eventId: widget.event.id,
      title: _titleCtrl.text.trim(),
      start: dateChanged ? _start : null,
      end: dateChanged ? _end : null,
      allDay: _allDay,
    );

    if (!result.ok) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新できませんでした: ${result.error}')),
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
      final result = await _calendarService.deleteEvent(widget.event.id);
      if (!result.ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('削除できませんでした: ${result.error}')),
          );
        }
        return;
      }
      // 削除は元の日付の周辺を再取得しないとキャッシュに残り続ける
      await _resyncCache(widget.event.start);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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

          const SectionLabel('日時'),
          EventDateTimeFields(
            start: _start,
            end: _end,
            allDay: _allDay,
            onStartChanged: (v) => setState(() => _start = v),
            onEndChanged: (v) => setState(() => _end = v),
            onAllDayChanged: (v) => setState(() => _allDay = v),
          ),

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
