import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/event_service.dart';
import '../utils/app_theme.dart';

// ── ゴミ箱（削除した予定）────────────────────────────
// 誤って削除した予定を30日以内なら復元できるようにする画面。
// 実体はEventService.deleteEventが即消しせずdeletedAtを立てるだけに
// しているので、ここではそれを一覧・復元・完全削除するだけ。
class TrashScreen extends StatefulWidget {
  final String coupleId;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<AimaruEvent>>? eventsStreamOverride;
  const TrashScreen({super.key, required this.coupleId, this.eventsStreamOverride});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  EventService? _eventServiceInstance;
  EventService get _eventService => _eventServiceInstance ??= EventService();

  late final Stream<List<AimaruEvent>> _eventsStream =
      widget.eventsStreamOverride ?? _eventService.watchDeletedEvents(widget.coupleId);

  Future<void> _restore(AimaruEvent event) => _eventService.restoreEvent(event);

  Future<void> _permanentlyDelete(AimaruEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('完全に削除しますか？'),
        content: Text('「${event.title}」を完全に削除します。この操作は取り消せません。',
          style: const TextStyle(color: AppColors.textSecond, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('完全に削除する', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _eventService.permanentlyDeleteEvent(event);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('ゴミ箱')),
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
          final events = snap.data!;
          if (events.isEmpty) {
            return const Center(
              child: Text('ゴミ箱は空です\n削除した予定は30日間ここに残ります',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            itemBuilder: (ctx, i) => _buildTile(events[i]),
          );
        },
      ),
    );
  }

  Widget _buildTile(AimaruEvent event) {
    final dateStr = DateFormat('M月d日', 'ja').format(event.date);
    return Container(
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
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.restore, color: AppColors.textSecond),
          tooltip: '元に戻す',
          onPressed: () => _restore(event),
        ),
        IconButton(
          icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
          tooltip: '完全に削除',
          onPressed: () => _permanentlyDelete(event),
        ),
      ]),
    );
  }
}
