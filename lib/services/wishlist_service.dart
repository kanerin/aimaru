import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

// ── ほしいものリスト ──────────────────────────────────
// アイテム本体（wishlistItems）と、パートナーが「予約」したかどうか
// （wishlistReservations）を別コレクションに分けている。予約は
// firestore.rulesで予約した本人しか読めないようにしてあるため、
// 欲しいものを追加した側は自分のリストが予約されたかどうかを知らない
// （サプライズを壊さないため）。このクラスもその境界に合わせて、
// 予約系のメソッドは常に「自分が予約したもの」だけを扱う。
class WishlistService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  WishlistService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _itemsRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('wishlistItems');

  CollectionReference _reservationsRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('wishlistReservations');

  // ── アイテムを追加 ────────────────────────────────
  Future<WishlistItem> addItem(String coupleId, String text, {String? url}) async {
    final ref = _itemsRef(coupleId).doc();
    final item = WishlistItem(
      id:        ref.id,
      coupleId:  coupleId,
      text:      text,
      url:       url,
      addedBy:   _uid,
      createdAt: DateTime.now(),
    );
    await ref.set(item.toMap());
    return item;
  }

  // ── アイテムを削除（自分が追加した分のみ、firestore.rulesでも強制）───
  Future<void> deleteItem(WishlistItem item) async {
    await _itemsRef(item.coupleId).doc(item.id).delete();
  }

  // ── 一覧をリアルタイム取得（新しい順）────────────────────
  Stream<List<WishlistItem>> watchItems(String coupleId) {
    return _itemsRef(coupleId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(WishlistItem.fromDoc).toList());
  }

  // ── 「用意する」（予約）。相手が追加したアイテムにのみ実行できる
  // （自分が追加したアイテムへの予約はfirestore.rulesで拒否される）────
  Future<void> reserveItem(String coupleId, String itemId) {
    return _reservationsRef(coupleId).doc(itemId).set({
      'reservedBy': _uid,
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ── 予約を取り消す ────────────────────────────────
  Future<void> unreserveItem(String coupleId, String itemId) {
    return _reservationsRef(coupleId).doc(itemId).delete();
  }

  // ── 自分が予約した(=用意すると決めた)アイテムIDの集合。
  // reservedBy == 自分 という、firestore.rulesの読み取り条件と完全に一致する
  // 絞り込みクエリのため、予約状態を追加した本人に見せてしまう心配は無い
  // （bug_report_serviceのwatchMyReportsと同じ「自分の分だけ絞り込む」設計）───
  Stream<Set<String>> watchMyReservedItemIds(String coupleId) {
    return _reservationsRef(coupleId)
        .where('reservedBy', isEqualTo: _uid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }
}
