import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';
import '../services/wishlist_service.dart';
import '../utils/app_theme.dart';
import '../widgets/confirm_delete_dialog.dart';

// ── ほしいものリスト ──────────────────────────────────
// 市場調査（propose-feature）でカップル・夫婦向けアプリのレビュー記事に
// 挙がっていた「プレゼント用のほしいものリスト」。買い物リスト（日用品・
// 食材）とは別に、記念日・誕生日に贈るものを共有する。パートナーが
// 「用意する」を押したかどうかは、追加した本人（欲しい側）には表示しない
// ——サプライズを壊さないための設計（firestore.rulesのwishlistReservations
// を参照）。TimeTreeにはこの概念自体が無い差別化要素。
class WishlistScreen extends StatefulWidget {
  final String coupleId;
  final List<String> memberIds;
  final String partnerName;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<WishlistItem>>? itemsStreamOverride;
  final Stream<Set<String>>? reservedIdsStreamOverride;
  // テストからfake_cloud_firestore等を差し込むための注入ポイント。
  final WishlistService? wishlistServiceOverride;
  // テストからFirebase Authに触れずに「自分」を差し込むための注入ポイント。
  final String? currentUidOverride;

  const WishlistScreen({
    super.key,
    required this.coupleId,
    required this.memberIds,
    required this.partnerName,
    this.itemsStreamOverride,
    this.reservedIdsStreamOverride,
    this.wishlistServiceOverride,
    this.currentUidOverride,
  });

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  // WishlistService() は生成時にFirebaseFirestore.instanceへ即座に触れるため、
  // ストリームのoverrideを使うテストではFirebase初期化なしに動けるよう
  // 実際に使うときまで生成を遅らせる。
  WishlistService? _serviceInstance;
  WishlistService get _service =>
      _serviceInstance ??= widget.wishlistServiceOverride ?? WishlistService();

  final _textController = TextEditingController();
  final _urlController = TextEditingController();

  late final Stream<List<WishlistItem>> _itemsStream =
      widget.itemsStreamOverride ?? _service.watchItems(widget.coupleId);
  late final Stream<Set<String>> _reservedIdsStream =
      widget.reservedIdsStreamOverride ?? _service.watchMyReservedItemIds(widget.coupleId);

  String get _uid => widget.currentUidOverride ?? FirebaseAuth.instance.currentUser!.uid;

  @override
  void dispose() {
    _textController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final url = _urlController.text.trim();
    _textController.clear();
    _urlController.clear();
    try {
      await _service.addItem(widget.coupleId, text, url: url.isEmpty ? null : url);
    } catch (e) {
      _textController.text = text;
      _urlController.text = url;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('追加に失敗しました。もう一度お試しください')),
        );
      }
    }
  }

  Future<void> _delete(WishlistItem item) async {
    try {
      await _service.deleteItem(item);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除に失敗しました。もう一度お試しください')),
        );
      }
    }
  }

  // ゴミ箱を持たないコレクションのため、元に戻せない削除は必ず確認を挟む。
  Future<void> _confirmAndDelete(WishlistItem item) async {
    final confirmed = await confirmDelete(
      context,
      title: 'ほしいものを削除',
      message: '「${item.text}」を削除します。元に戻せません。',
    );
    if (!confirmed) return;
    await _delete(item);
  }

  Future<void> _toggleReserve(WishlistItem item, bool reserved) async {
    if (reserved) {
      await _service.unreserveItem(widget.coupleId, item.id);
    } else {
      await _service.reserveItem(widget.coupleId, item.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('ほしいものリスト')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<WishlistItem>>(
              stream: _itemsStream,
              builder: (context, itemsSnap) {
                // hasDataだけを見ていると、権限エラー等でストリームがエラーに
                // 落ちたときに無限ローディングのまま固まる。
                if (itemsSnap.hasError) {
                  return const Center(
                    child: Text('読み込みに失敗しました\nしばらくしてから開き直してください',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
                  );
                }
                if (!itemsSnap.hasData) {
                  return Center(child: CircularProgressIndicator(color: appAccent(context)));
                }
                final items = itemsSnap.data!;
                if (items.isEmpty) {
                  return const Center(
                    child: Text('まだほしいものリストは空です\n欲しいものを書いておきましょう',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
                  );
                }
                return StreamBuilder<Set<String>>(
                  stream: _reservedIdsStream,
                  builder: (context, reservedSnap) {
                    // 予約状態は補助的な表示のため、取得に失敗しても一覧自体は
                    // 表示を続ける（「予約する」操作ができないだけにする）。
                    final reservedIds = reservedSnap.data ?? const <String>{};
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) =>
                          _buildTile(items[i], reservedIds.contains(items[i].id)),
                    );
                  },
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
              children: [
                TextField(
                  controller: _textController,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '欲しいもの...',
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _add(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'リンク（任意）',
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

  Widget _buildTile(WishlistItem item, bool reservedByMe) {
    final isMine = item.addedBy == _uid;
    final tile = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.text,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
                if (item.url != null && item.url!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.url!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 6),
                Text(isMine ? 'あなたが追加' : '${widget.partnerName}が追加',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (isMine)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.textMuted),
              tooltip: '削除',
              onPressed: () => _confirmAndDelete(item),
            )
          else
            InkWell(
              onTap: () => _toggleReserve(item, reservedByMe),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: reservedByMe
                      ? appAccent(context).withValues(alpha: 0.18)
                      : AppColors.navy,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: reservedByMe ? appAccent(context) : AppColors.hairline),
                ),
                child: Text(
                  reservedByMe ? '予約済み\n(自分にだけ表示)' : '🎁 用意する',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: reservedByMe ? appAccent(context) : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (!isMine) return tile;

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
      confirmDismiss: (_) => confirmDelete(
        context,
        title: 'ほしいものを削除',
        message: '「${item.text}」を削除します。元に戻せません。',
      ),
      onDismissed: (_) => _delete(item),
      child: tile,
    );
  }
}
