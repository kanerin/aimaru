import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/event_service.dart';
import '../utils/app_theme.dart';
import 'event_detail_screen.dart';

// ── 予定の検索 ──────────────────────────────────────
// カレンダーを月ごとにめくらなくても、タイトル・メモ・場所から
// 予定を横断して探せるようにする画面。TimeTree・Googleカレンダーが
// 標準で持つ検索機能に相当し、このアプリにはまだ無かった。
class EventSearchScreen extends StatefulWidget {
  final String coupleId;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<AimaruEvent>>? eventsStreamOverride;
  const EventSearchScreen({super.key, required this.coupleId, this.eventsStreamOverride});

  @override
  State<EventSearchScreen> createState() => _EventSearchScreenState();
}

class _EventSearchScreenState extends State<EventSearchScreen> {
  EventService? _eventServiceInstance;
  EventService get _eventService => _eventServiceInstance ??= EventService();

  late final Stream<List<AimaruEvent>> _eventsStream =
      widget.eventsStreamOverride ?? _eventService.watchAllEvents(widget.coupleId);

  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<AimaruEvent> _filter(List<AimaruEvent> events) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return events.where((e) {
      return e.title.toLowerCase().contains(q) ||
          (e.memo?.toLowerCase().contains(q) ?? false) ||
          (e.location?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _openDetail(AimaruEvent event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(event: event, coupleId: widget.coupleId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'タイトル・メモ・場所で検索',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: StreamBuilder<List<AimaruEvent>>(
        stream: _eventsStream,
        builder: (context, snap) {
          // hasDataだけを見ていると、権限エラー等でストリームがエラーに
          // 落ちたときに無限ローディングのまま固まる。
          if (snap.hasError) {
            return const Center(
              child: Text('読み込みに失敗しました\nしばらくしてから開き直してください',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            );
          }
          if (!snap.hasData) {
            return Center(child: CircularProgressIndicator(color: appAccent(context)));
          }
          if (_query.trim().isEmpty) {
            return const Center(
              child: Text('キーワードを入力して予定を検索できます',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            );
          }
          final results = _filter(snap.data!);
          if (results.isEmpty) {
            return const Center(
              child: Text('見つかりませんでした',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: results.length,
            itemBuilder: (ctx, i) => _buildTile(results[i]),
          );
        },
      ),
    );
  }

  Widget _buildTile(AimaruEvent event) {
    final dateStr = event.allDay
        ? DateFormat('M月d日（E）', 'ja').format(event.date)
        : DateFormat('M月d日（E）HH:mm', 'ja').format(event.date);
    return InkWell(
      onTap: () => _openDetail(event),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                )),
                const SizedBox(height: 4),
                Text(dateStr, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                if (event.location != null && event.location!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(event.location!,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}
