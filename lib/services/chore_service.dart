import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class ChoreService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  ChoreService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _choresRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('chores');

  // ── 家事を追加 ────────────────────────────────────
  Future<ChoreItem> addChore(String coupleId, String title, {String? assignedTo}) async {
    final ref = _choresRef(coupleId).doc();
    final chore = ChoreItem(
      id:         ref.id,
      coupleId:   coupleId,
      title:      title,
      assignedTo: assignedTo,
      createdBy:  _uid,
      createdAt:  DateTime.now(),
    );
    await ref.set(chore.toMap());
    return chore;
  }

  // ── 完了/未完了を切り替え ─────────────────────────
  Future<void> setDone(ChoreItem chore, bool done) async {
    await _choresRef(chore.coupleId).doc(chore.id).update({'done': done});
  }

  // ── 担当者を変更（nullで「どちらでも」に戻す）─────────
  Future<void> setAssignee(ChoreItem chore, String? assignedTo) async {
    await _choresRef(chore.coupleId).doc(chore.id).update({'assignedTo': assignedTo});
  }

  // ── 家事を削除 ────────────────────────────────────
  Future<void> deleteChore(ChoreItem chore) async {
    await _choresRef(chore.coupleId).doc(chore.id).delete();
  }

  // ── 完了済みを一括で未完了に戻す（週次リセット想定）───────
  Future<void> resetAllDone(String coupleId) async {
    final snap = await _choresRef(coupleId).where('done', isEqualTo: true).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'done': false});
    }
    await batch.commit();
  }

  // ── 一覧をリアルタイム取得（未完了→完了、それぞれ新しい順）───
  Stream<List<ChoreItem>> watchChores(String coupleId) {
    return _choresRef(coupleId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          final chores = snap.docs.map(ChoreItem.fromDoc).toList();
          chores.sort((a, b) {
            if (a.done != b.done) return a.done ? 1 : -1;
            return b.createdAt.compareTo(a.createdAt);
          });
          return chores;
        });
  }
}
