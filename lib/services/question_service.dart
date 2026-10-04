import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../utils/daily_question_picker.dart';

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

  CollectionReference<Map<String, dynamic>> _dailyQuestionsRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('dailyQuestions');

  // ── その日の質問を取得する（無ければ決めて保存する）────────────
  // 質問は couples/{coupleId}/dailyQuestions/{dateKey} に1日1件だけ保存し、
  // 2人とも同じドキュメントを読む。各端末がアプリ内の表から計算していた頃は、
  // アプリの版が違うと同じ日でも別の質問になっていた。
  // 先に開いた側が、そのカップルにまだ出していない質問から選んで保存する。
  // 2人が同時に開いても1件に決まるよう、保存はトランザクションで行い、
  // firestore.rulesでも作成後の変更・削除を許可していない。
  Future<String> ensureDailyQuestion(String coupleId, DateTime date) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final ref = _dailyQuestionsRef(coupleId).doc(dateKey);

    final saved = _savedQuestion(await ref.get());
    if (saved != null) return saved;

    final candidate = await _pickCandidate(coupleId, date, dateKey);
    return _db.runTransaction((tx) async {
      // 候補を選んでいる間に相手が先に保存していたら、そちらに合わせる。
      final current = _savedQuestion(await tx.get(ref));
      if (current != null) return current;
      tx.set(ref, {
        'question':  candidate,
        'dateKey':   dateKey,
        'createdBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return candidate;
    });
  }

  String? _savedQuestion(DocumentSnapshot<Map<String, dynamic>> snap) {
    final question = snap.data()?['question'];
    return question is String && question.isNotEmpty ? question : null;
  }

  // まだ保存されていない日の質問を、これまでの出題履歴から選ぶ。
  Future<String> _pickCandidate(String coupleId, DateTime date, String dateKey) async {
    final results = await Future.wait([
      _dailyQuestionsRef(coupleId).get(),
      _answersRef(coupleId).get(),
    ]);

    // 日付キー → その日に保存した質問
    final savedByDate = <String, String>{};
    for (final doc in results[0].docs) {
      final question = (doc.data() as Map<String, dynamic>)['question'];
      if (question is String && question.isNotEmpty) savedByDate[doc.id] = question;
    }

    // 質問文 → 最後に出した日付キー
    final askedOn = <String, String>{};
    void markAsked(String question, String askedDateKey) {
      final last = askedOn[question];
      if (last == null || last.compareTo(askedDateKey) < 0) askedOn[question] = askedDateKey;
    }

    savedByDate.forEach((askedDateKey, question) => markAsked(question, askedDateKey));

    for (final doc in results[1].docs) {
      final data = doc.data() as Map<String, dynamic>;
      final answeredDateKey = data['dateKey'];
      if (answeredDateKey is! String) continue;
      final answeredQuestion = data['question'];

      if (answeredDateKey == dateKey) {
        // 質問を保存しない古い版のアプリを使う相手が、今日すでに回答している。
        // 相手が見たのは日付から決まる質問なので、回答と質問がずれないよう
        // それに合わせる。
        return answeredQuestion is String && answeredQuestion.isNotEmpty
            ? answeredQuestion
            : pickDailyQuestion(date);
      }

      // 質問を保存していなかった頃の回答は、日付から当時の質問を復元する。
      final question = answeredQuestion is String && answeredQuestion.isNotEmpty
          ? answeredQuestion
          : savedByDate[answeredDateKey] ?? questionForDateKey(answeredDateKey);
      if (question != null) markAsked(question, answeredDateKey);
    }

    return pickUnaskedQuestion(date, askedOn);
  }

  // ── 今日の質問に回答する（1人1日1件、doc idで上書きを防ぐ）───
  // [question]は回答した質問文。履歴で「何に答えたか」を表示するために残す。
  Future<void> submitAnswer(String coupleId, String dateKey, String text,
      {String? question}) async {
    final ref = _answersRef(coupleId).doc('${dateKey}_$_uid');
    final answer = QuestionAnswer(
      id:        ref.id,
      coupleId:  coupleId,
      dateKey:   dateKey,
      uid:       _uid,
      text:      text,
      question:  question,
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
