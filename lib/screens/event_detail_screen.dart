import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/event_service.dart';
import '../services/google_calendar_service.dart';
import '../utils/app_theme.dart';
import 'event_form_screen.dart';

class EventDetailScreen extends StatefulWidget {
  final AimaruEvent event;
  final String coupleId;
  const EventDetailScreen({super.key, required this.event, required this.coupleId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final _eventService    = EventService();
  final _calendarService = GoogleCalendarService();
  final _pageCtrl        = PageController();
  int _page = 0;
  bool _deleting = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EventFormScreen(
        coupleId: widget.coupleId, existing: widget.event,
      )),
    );
    // 保存された場合は一覧側の最新データを見せるため詳細画面を閉じる
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('この予定を削除しますか？'),
        content: Text('「${widget.event.title}」を削除します。ゴミ箱に移動し、30日間は設定画面から復元できます。',
          style: const TextStyle(color: AppColors.textSecond, fontSize: 13)),
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
      await _eventService.deleteEvent(widget.event);
      if (widget.event.googleCalendarEventId != null) {
        await _calendarService.deleteEvent(widget.event.googleCalendarEventId!);
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final dateStr = DateFormat('M月d日（E）HH:mm', 'ja').format(e.date);

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: _edit,
            child: const Text('編集', style: TextStyle(color: AppColors.lavenderSoft, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (e.imageUrls.isNotEmpty) ...[
            SizedBox(
              height: 220,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: PageView.builder(
                      controller: _pageCtrl,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemCount: e.imageUrls.length,
                      itemBuilder: (ctx, i) => CachedNetworkImage(
                        imageUrl: e.imageUrls[i],
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: AppColors.navySurface),
                      ),
                    ),
                  ),
                  if (e.imageUrls.length > 1)
                    Positioned(
                      bottom: 10, left: 0, right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(e.imageUrls.length, (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: 5, height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page ? Colors.white : Colors.white38,
                          ),
                        )),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          Text('${e.type.emoji} ${e.title}', style: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.cream,
          )),
          const SizedBox(height: 14),

          _MetaRow(icon: Icons.calendar_today, text: dateStr),
          if (e.location != null) _MetaRow(icon: Icons.location_on_outlined, text: e.location!),
          _MetaRow(icon: Icons.repeat, text: e.recurring ? '毎年繰り返し' : '繰り返しなし'),

          if (e.memo != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Text(e.memo!, style: const TextStyle(
                fontSize: 13, color: AppColors.textSecond, height: 1.7,
              )),
            ),
          ],

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.navySurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            height: 48,
            child: Row(children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: const Center(child: Text('G', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF4285F4),
                ))),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('Googleカレンダー同期', style: TextStyle(
                fontSize: 12.5, color: AppColors.textSecond,
              ))),
              Text(
                e.googleCalendarEventId != null ? '同期済み' : '未同期',
                style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600,
                  color: e.googleCalendarEventId != null ? AppColors.success : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 10),
            ]),
          ),

          const SizedBox(height: 28),
          Center(
            child: TextButton(
              onPressed: _deleting ? null : _delete,
              child: _deleting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                  : const Text('この予定を削除', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 15, color: AppColors.textMuted),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecond)),
    ]),
  );
}
