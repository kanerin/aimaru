import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class ShoppingListService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  ShoppingListService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _itemsRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('shoppingItems');

  // ── アイテムを追加 ────────────────────────────────
  Future<ShoppingItem> addItem(String coupleId, String title, {String? quantity}) async {
    final ref = _itemsRef(coupleId).doc();
    final item = ShoppingItem(
      id:        ref.id,
      coupleId:  coupleId,
      title:     title,
      quantity:  quantity,
      createdBy: _uid,
      createdAt: DateTime.now(),
    );
    await ref.set(item.toMap());
    return item;
  }

  // ── 購入済み/未購入を切り替え ─────────────────────
  Future<void> setDone(ShoppingItem item, bool done) async {
    await _itemsRef(item.coupleId).doc(item.id).update({'done': done});
  }

  // ── アイテムを削除 ────────────────────────────────
  Future<void> deleteItem(ShoppingItem item) async {
    await _itemsRef(item.coupleId).doc(item.id).delete();
  }

  // ── 購入済みを一括で削除（買い物が終わったらリストから消す）─
  Future<void> clearDone(String coupleId) async {
    final snap = await _itemsRef(coupleId).where('done', isEqualTo: true).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ── 一覧をリアルタイム取得（未購入→購入済み、それぞれ新しい順）───
  Stream<List<ShoppingItem>> watchItems(String coupleId) {
    return _itemsRef(coupleId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          final items = snap.docs.map(ShoppingItem.fromDoc).toList();
          items.sort((a, b) {
            if (a.done != b.done) return a.done ? 1 : -1;
            return b.createdAt.compareTo(a.createdAt);
          });
          return items;
        });
  }
}
