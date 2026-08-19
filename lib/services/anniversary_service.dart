import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class AnniversaryService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  AnniversaryService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _anniversariesRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('anniversaries');

  // ── 記念日を追加 ──────────────────────────────────
  Future<AnniversaryItem> addAnniversary(String coupleId, String title, DateTime date) async {
    final ref = _anniversariesRef(coupleId).doc();
    final item = AnniversaryItem(
      id:        ref.id,
      coupleId:  coupleId,
      title:     title,
      date:      date,
      createdBy: _uid,
      createdAt: DateTime.now(),
    );
    await ref.set(item.toMap());
    return item;
  }

  // ── 記念日を削除 ──────────────────────────────────
  Future<void> deleteAnniversary(AnniversaryItem item) async {
    await _anniversariesRef(item.coupleId).doc(item.id).delete();
  }

  // ── 一覧をリアルタイム取得 ─────────────────────────
  // 並び順（次の記念日が近い順）は日付だけでは決まらない（毎年繰り返す
  // 「次の周年」を見る必要があるため）、呼び出し側（画面）で計算して並べる。
  Stream<List<AnniversaryItem>> watchAnniversaries(String coupleId) {
    return _anniversariesRef(coupleId).snapshots().map(
        (snap) => snap.docs.map(AnniversaryItem.fromDoc).toList());
  }
}
