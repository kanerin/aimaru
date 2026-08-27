import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class DiaryService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  DiaryService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _entriesRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('diaryEntries');

  // ── 自分の日記を保存する（1人1日1件、doc idで上書き）───────
  // すでにその日の分があれば内容を書き直す（ふたりの質問と違い書き直しを許す）。
  Future<void> saveEntry(String coupleId, String dateKey, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final ref = _entriesRef(coupleId).doc('${dateKey}_$_uid');
    final existing = await ref.get();
    final createdAt = existing.exists
        ? (existing.data() as Map<String, dynamic>)['createdAt'] as Timestamp
        : Timestamp.fromDate(DateTime.now());
    final entry = DiaryEntry(
      id:        ref.id,
      coupleId:  coupleId,
      dateKey:   dateKey,
      uid:       _uid,
      text:      trimmed,
      createdAt: createdAt.toDate(),
      updatedAt: DateTime.now(),
    );
    await ref.set(entry.toMap());
  }

  // ── 自分の日記を削除する ──────────────────────────────
  Future<void> deleteEntry(String coupleId, String dateKey) async {
    await _entriesRef(coupleId).doc('${dateKey}_$_uid').delete();
  }

  // ── 直近の日記を新しい日付順で取得（2人分でlimit件）────────
  Stream<List<DiaryEntry>> watchRecentEntries(String coupleId, {int limit = 60}) {
    return _entriesRef(coupleId)
        .orderBy('dateKey', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(DiaryEntry.fromDoc).toList());
  }
}
