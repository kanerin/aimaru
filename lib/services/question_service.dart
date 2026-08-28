import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class QuestionService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  QuestionService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _answersRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('questionAnswers');

  // ── 今日の質問に回答する（1人1日1件、doc idで上書きを防ぐ）───
  Future<void> submitAnswer(String coupleId, String dateKey, String text) async {
    final ref = _answersRef(coupleId).doc('${dateKey}_$_uid');
    final answer = QuestionAnswer(
      id:        ref.id,
      coupleId:  coupleId,
      dateKey:   dateKey,
      uid:       _uid,
      text:      text,
      createdAt: DateTime.now(),
    );
    await ref.set(answer.toMap());
  }

  // ── その日の2人分の回答をリアルタイム取得 ────────────────
  Stream<List<QuestionAnswer>> watchAnswers(String coupleId, String dateKey) {
    return _answersRef(coupleId)
        .where('dateKey', isEqualTo: dateKey)
        .snapshots()
        .map((snap) => snap.docs.map(QuestionAnswer.fromDoc).toList());
  }

  // ── 直近の回答を新しい日付順で取得（2人分でlimit件）────────
  // 「今日の質問」と「これまでの質問」の履歴を1本のストリームで賄う。
  // dateKeyは'yyyy-MM-dd'の固定長なので辞書順＝日付順になり、
  // 単一フィールドのorderByで済む（複合インデックス不要）。
  Stream<List<QuestionAnswer>> watchRecentAnswers(String coupleId, {int limit = 60}) {
    return _answersRef(coupleId)
        .orderBy('dateKey', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(QuestionAnswer.fromDoc).toList());
  }
}
