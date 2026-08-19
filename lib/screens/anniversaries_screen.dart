import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/anniversary_service.dart';
import '../utils/anniversary_calculator.dart';
import '../utils/app_theme.dart';

// ── 複数記念日リスト ──────────────────────────────────
// 設定画面の「記念日」カードは付き合い始めた日1件のみ。プロポーズ・入籍・
// 初デートなど、それ以外に追いたい記念日をここでまとめて管理し、
// 次の記念日が近い順にカウントダウン表示する。
class AnniversariesScreen extends StatefulWidget {
  final String coupleId;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<AnniversaryItem>>? anniversariesStreamOverride;
  final DateTime Function()? nowOverride;
  final Future<DateTime?> Function(BuildContext context, DateTime? initial)? pickDateOverride;

  const AnniversariesScreen({
    super.key,
    required this.coupleId,
    this.anniversariesStreamOverride,
    this.nowOverride,
    this.pickDateOverride,
  });

  @override
  State<AnniversariesScreen> createState() => _AnniversariesScreenState();
}

class _AnniversariesScreenState extends State<AnniversariesScreen> {
  // AnniversaryService() は生成時にFirebaseFirestore.instanceへ即座に触れるため、
  // anniversariesStreamOverrideを使うテストではFirebase初期化なしに動けるよう
  // 実際に使うときまで生成を遅らせる。
  AnniversaryService? _serviceInstance;
  AnniversaryService get _service => _serviceInstance ??= AnniversaryService();

  late final Stream<List<AnniversaryItem>> _anniversariesStream =
      widget.anniversariesStreamOverride ?? _service.watchAnniversaries(widget.coupleId);

  DateTime get _now => (widget.nowOverride ?? DateTime.now)();

  Future<void> _addAnniversary() async {
    final titleController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('記念日を追加'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: '例: プロポーズ記念日'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, titleController.text.trim()),
            child: const Text('次へ'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;

    final now = _now;
    final date = widget.pickDateOverride != null
        ? await widget.pickDateOverride!(context, now)
        : await showDatePicker(
            context: context,
            initialDate: now,
            firstDate: DateTime(now.year - 50),
            lastDate: now, // 未来の記念日は選べない（daysTogetherの計算を単純に保つため）
          );
    if (date == null || !mounted) return;

    await _service.addAnniversary(widget.coupleId, title, date);
  }

  Future<void> _delete(AnniversaryItem item) async {
    await _service.deleteAnniversary(item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('記念日リスト')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAnniversary,
        backgroundColor: appAccent(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<AnniversaryItem>>(
        stream: _anniversariesStream,
        builder: (context, snap) {
          // hasDataだけを見ていると、権限エラー等でストリームがエラーに
          // 落ちたときに無限ローディングのまま固まる
          // （本番でFirestoreルール未反映のまま実際に発生した不具合と同じ経路）。
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
          final items = List<AnniversaryItem>.from(snap.data!)
            ..sort((a, b) => summarizeAnniversary(a.date, _now).daysUntilNextAnniversary
                .compareTo(summarizeAnniversary(b.date, _now).daysUntilNextAnniversary));
          if (items.isEmpty) {
            return const Center(
              child: Text('まだ記念日がありません\nプロポーズや入籍日など、追いたい記念日を登録しましょう',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: items.length,
            itemBuilder: (ctx, i) => _buildTile(items[i]),
          );
        },
      ),
    );
  }

  Widget _buildTile(AnniversaryItem item) {
    final summary = summarizeAnniversary(item.date, _now);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      onDismissed: (_) => _delete(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
            )),
            const SizedBox(height: 4),
            Text(
              '${DateFormat('yyyy年M月d日').format(item.date)}から',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              summary.daysUntilNextAnniversary == 0
                  ? '🎉 今日は${summary.nextAnniversaryYearCount}周年記念日です！'
                  : '${summary.nextAnniversaryYearCount}周年まであと${summary.daysUntilNextAnniversary}日',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: appAccent(context)),
            ),
          ],
        ),
      ),
    );
  }
}
