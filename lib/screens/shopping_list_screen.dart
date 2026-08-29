import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/shopping_list_service.dart';
import '../utils/app_theme.dart';

// ── 買い物リスト ──────────────────────────────────────
// 市場調査（2026年8月、propose-feature）で夫婦・カップル向けアプリの
// 人気機能として挙がっていた「買い物リスト」。TimeTreeにはこの概念自体が
// 無い差別化要素。todos（やりたいことリスト）・chores（家事分担）とは別に、
// 日用品・食材の買い出しを2人で共有する。
class ShoppingListScreen extends StatefulWidget {
  final String coupleId;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<ShoppingItem>>? itemsStreamOverride;
  // テストからfake_cloud_firestore等を差し込むための注入ポイント。
  final ShoppingListService? shoppingListServiceOverride;

  const ShoppingListScreen({
    super.key,
    required this.coupleId,
    this.itemsStreamOverride,
    this.shoppingListServiceOverride,
  });

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  // ShoppingListService() は生成時にFirebaseFirestore.instanceへ即座に触れる
  // ため、itemsStreamOverrideを使うテストではFirebase初期化なしに動けるよう
  // 実際に使うときまで生成を遅らせる。
  ShoppingListService? _serviceInstance;
  ShoppingListService get _service =>
      _serviceInstance ??= widget.shoppingListServiceOverride ?? ShoppingListService();
  final _titleController = TextEditingController();
  final _quantityController = TextEditingController();

  late final Stream<List<ShoppingItem>> _itemsStream =
      widget.itemsStreamOverride ?? _service.watchItems(widget.coupleId);

  @override
  void dispose() {
    _titleController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final quantity = _quantityController.text.trim();
    _titleController.clear();
    _quantityController.clear();
    await _service.addItem(widget.coupleId, title, quantity: quantity.isEmpty ? null : quantity);
  }

  Future<void> _delete(ShoppingItem item) async {
    await _service.deleteItem(item);
  }

  Future<void> _clearDone() async {
    await _service.clearDone(widget.coupleId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: const Text('買い物リスト'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '購入済みをまとめて削除',
            onPressed: _clearDone,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ShoppingItem>>(
              stream: _itemsStream,
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
                final items = snap.data!;
                if (items.isEmpty) {
                  return const Center(
                    child: Text('まだ買い物リストは空です\n買うものを書いておきましょう',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) => _buildTile(items[i]),
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
            child: Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _titleController,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '買うもの...',
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _quantityController,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '数量',
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
          ),
        ],
      ),
    );
  }

  Widget _buildTile(ShoppingItem item) {
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
                  value: item.done,
                  onChanged: (v) => _service.setDone(item, v ?? false),
                  activeColor: appAccent(context),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            color: item.done ? AppColors.textMuted : AppColors.textPrimary,
                            decoration: item.done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (item.quantity != null && item.quantity!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: appAccent(context).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              item.quantity!,
                              style: TextStyle(fontSize: 10.5, color: appAccent(context)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.textMuted),
                  tooltip: '削除',
                  onPressed: () => _delete(item),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
