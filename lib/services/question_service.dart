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

  // ── その日の質問文を取得する ─────────────────────────
  // 前の晩にCloud Functions（prepareTomorrowQuestion）がGeminiで作って
  // dailyQuestions/{dateKey}に置く。まだ無い（生成が止まっていた）日はnullを
  // 返し、画面側で手書きの質問（daily_question_picker.dart）に切り替える。
  Future<String?> fetchDailyQuestion(String dateKey) async {
    final doc = await _db.collection('dailyQuestions').doc(dateKey).get();
    final text = doc.data()?['text'];
    return text is String && text.isNotEmpty ? text : null;
  }

  // ── 今日の質問に回答する（1人1日1件、doc idで上書きを防ぐ）───
  // 質問文も一緒に残し、過去の質問を振り返るときに使う。
  Future<void> submitAnswer(
    String coupleId,
    String dateKey,
    String text, {
    String? question,
  }) async {
    final ref = _answersRef(coupleId).doc('${dateKey}_$_uid');
    final answer = QuestionAnswer(
      id:        ref.id,
      coupleId:  coupleId,
      dateKey:   dateKey,
      uid:       _uid,
      text:      text,
      createdAt: DateTime.now(),
      question:  question,
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

  CollectionReference _commentsRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('questionComments');

  // ── 回答へのコメントを追加する ─────────────────────────
  // その日の質問（dateKey）ごとのやり取り。firestore.rulesで、その日に
  // 自分が回答済みでなければ書けないようにしてある。
  Future<void> addComment(String coupleId, String dateKey, String text) async {
    final ref = _commentsRef(coupleId).doc();
    final comment = QuestionComment(
      id:        ref.id,
      coupleId:  coupleId,
      dateKey:   dateKey,
      text:      text,
      senderId:  _uid,
      createdAt: DateTime.now(),
    );
    await ref.set(comment.toMap());
  }

  // ── 直近のコメントを新しい日付順で取得 ────────────────────
  // 画面に出す「今日」と「これまでの質問」のぶんを1本のストリームで賄う
  // （watchRecentAnswersと同じく、単一フィールドのorderByで複合インデックス
  // 不要）。同じ日の中の並び（古い順）は画面側で整える。
  Stream<List<QuestionComment>> watchRecentComments(String coupleId, {int limit = 300}) {
    return _commentsRef(coupleId)
        .orderBy('dateKey', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(QuestionComment.fromDoc).toList());
  }
}
