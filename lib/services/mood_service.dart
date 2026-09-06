import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class MoodService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  MoodService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _entriesRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('moodEntries');

  // ── 今日の気分を保存する（1人1日1件、doc idで上書き）───────
  // 日記と違い書き直すことしか想定していない（時間帯によって気分が変わっても
  // 選び直せばよい）ため、createdAtは常に選び直した時刻で上書きする。
  Future<void> setTodayMood(String coupleId, String dateKey, String mood) async {
    final ref = _entriesRef(coupleId).doc('${dateKey}_$_uid');
    final entry = MoodEntry(
      id:        ref.id,
      coupleId:  coupleId,
      dateKey:   dateKey,
      uid:       _uid,
      mood:      mood,
      createdAt: DateTime.now(),
    );
    await ref.set(entry.toMap());
  }

  // ── 直近の気分を新しい日付順で取得（2人分でlimit件）────────
  Stream<List<MoodEntry>> watchRecentMoods(String coupleId, {int limit = 60}) {
    return _entriesRef(coupleId)
        .orderBy('dateKey', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(MoodEntry.fromDoc).toList());
  }
}
