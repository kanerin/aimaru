import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/chore_service.dart';
import '../utils/app_theme.dart';

// ── 家事分担 ──────────────────────────────────────────
// 同棲・二人暮らしのカップル向け「家事分担」チェックリスト。市場調査
// （2026年8月、propose-feature）で家事分担・交換日記が人気機能として
// 挙がっており、交換日記（DiaryScreen）は先に実装済みのため対になる機能
// として追加する。TimeTreeにはこの概念自体が無い差別化要素。
class ChoresScreen extends StatefulWidget {
  final String coupleId;
  final List<String> memberIds;
  final String partnerName;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<ChoreItem>>? choresStreamOverride;
  // テストからfake_cloud_firestore等を差し込むための注入ポイント。
  final ChoreService? choreServiceOverride;
  // テストからFirebase Authに触れずに「自分」を差し込むための注入ポイント。
  final String? currentUidOverride;

  const ChoresScreen({
    super.key,
    required this.coupleId,
    required this.memberIds,
    required this.partnerName,
    this.choresStreamOverride,
    this.choreServiceOverride,
    this.currentUidOverride,
  });

  @override
  State<ChoresScreen> createState() => _ChoresScreenState();
}

class _ChoresScreenState extends State<ChoresScreen> {
  // ChoreService() は生成時にFirebaseFirestore.instanceへ即座に触れるため、
  // choresStreamOverrideを使うテストではFirebase初期化なしに動けるよう
  // 実際に使うときまで生成を遅らせる。
  ChoreService? _choreServiceInstance;
  ChoreService get _choreService =>
      _choreServiceInstance ??= widget.choreServiceOverride ?? ChoreService();
  final _controller = TextEditingController();

  late final Stream<List<ChoreItem>> _choresStream =
      widget.choresStreamOverride ?? _choreService.watchChores(widget.coupleId);

  String get _uid => widget.currentUidOverride ?? FirebaseAuth.instance.currentUser!.uid;
  String get _partnerUid =>
      widget.memberIds.firstWhere((id) => id != _uid, orElse: () => '');

  // 新規追加時の担当者選択。null = どちらでも。
  String? _newAssignee;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _assigneeLabel(String? uid) {
    if (uid == null || uid.isEmpty) return 'どちらでも';
    if (uid == _uid) return '自分';
    return widget.partnerName;
  }

  Future<void> _add() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    _controller.clear();
    await _choreService.addChore(widget.coupleId, title, assignedTo: _newAssignee);
  }

  Future<void> _delete(ChoreItem chore) async {
    await _choreService.deleteChore(chore);
  }

  Future<void> _resetAllDone() async {
    await _choreService.resetAllDone(widget.coupleId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: const Text('家事分担'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '完了をまとめてリセット',
            onPressed: _resetAllDone,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChoreItem>>(
              stream: _choresStream,
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
                final chores = snap.data!;
                if (chores.isEmpty) {
                  return const Center(
                    child: Text('まだ家事がありません\nやることを書いて分担しましょう',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: chores.length,
                  itemBuilder: (ctx, i) => _buildTile(chores[i]),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: const BoxDecoration(
              color: AppColors.navyCard,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    _buildAssigneeChip(null, 'どちらでも'),
                    _buildAssigneeChip(_uid, '自分'),
                    if (_partnerUid.isNotEmpty)
                      _buildAssigneeChip(_partnerUid, widget.partnerName),
                  ],
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: '家事を入力...',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _add,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: appAccent(context), shape: BoxShape.circle),
                      child: const Icon(Icons.add, color: Colors.white, size: 20),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssigneeChip(String? uid, String label) {
    final selected = _newAssignee == uid;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _newAssignee = uid),
      selectedColor: appAccent(context).withValues(alpha: 0.25),
      backgroundColor: AppColors.navySurface,
      labelStyle: TextStyle(
        color: selected ? appAccent(context) : AppColors.textMuted,
      ),
    );
  }

  Widget _buildTile(ChoreItem chore) {
    return Dismissible(
      key: ValueKey(chore.id),
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
      onDismissed: (_) => _delete(chore),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        // CheckboxListTile（ListTile系）はMaterial祖先の上でないと
        // タップ時のインクスプラッシュが描画されない（背景色に隠れて見えなく
        // なるとFlutterが警告する）ため、背景色はここではなくMaterialに持たせる。
        child: Material(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Checkbox(
                  value: chore.done,
                  onChanged: (v) => _choreService.setDone(chore, v ?? false),
                  activeColor: appAccent(context),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chore.title,
                          style: TextStyle(
                            fontSize: 14,
                            color: chore.done ? AppColors.textMuted : AppColors.textPrimary,
                            decoration: chore.done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: appAccent(context).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _assigneeLabel(chore.assignedTo),
                            style: TextStyle(fontSize: 10.5, color: appAccent(context)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.textMuted),
                  tooltip: '削除',
                  onPressed: () => _delete(chore),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
