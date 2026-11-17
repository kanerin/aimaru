import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/question_service.dart';
import '../utils/app_theme.dart';
import '../utils/daily_question_picker.dart';
import '../utils/question_streak.dart';
import '../widgets/question_comment_thread.dart';
import '../widgets/section_label.dart';

// ── ふたりの質問（デイリー質問）─────────────────────────
// TimeTreeなど競合のカレンダー機能には無い「お互いを知る」体験。
// サービス終了したPairyの移行先として比較されるSumOne/Twinestが持つ
// 質問カード機能に近い差別化要素。2人とも回答するまでパートナーの回答は
// 伏せておき、相手の回答に引っ張られない素直な回答を引き出す。
//
// 今日の分だけでなく、過去の質問と回答も同じ画面から振り返れる
// （直近をまとめて1本のストリームで読む）。
//
// 今日の質問は、前の晩にサーバーがGeminiで作ったもの（dailyQuestions/{dateKey}）
// を出す。手書きの質問を日付で回していた頃は3か月で同じ質問に戻っていた。
// サーバー側の用意が止まっていた日だけ、手書きの質問（daily_question_picker.dart）
// から出す。
class QuestionsScreen extends StatefulWidget {
  final String coupleId;
  final List<String> memberIds;
  final String partnerName;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<QuestionAnswer>>? answersStreamOverride;
  // テストから今日の質問文（サーバーが用意したもの。無ければnull）を
  // 直接流し込むための注入ポイント。未指定時は本番のFirestoreから読む。
  final Future<String?>? dailyQuestionFutureOverride;
  // テストからFirebase Authに触れずに「自分」を差し込むための注入ポイント。
  final String? currentUidOverride;
  // テストから「今日」を固定するための注入ポイント。
  final DateTime? nowOverride;
  // テストから回答の送信（成功/失敗）を差し込むための注入ポイント。
  final Future<void> Function(String text, String question)? submitOverride;
  // テストから回答へのコメント（エラー/データ）と、その送信を差し込むための注入ポイント。
  final Stream<List<QuestionComment>>? commentsStreamOverride;
  final Future<void> Function(String dateKey, String text)? sendCommentOverride;

  const QuestionsScreen({
    super.key,
    required this.coupleId,
    required this.memberIds,
    required this.partnerName,
    this.answersStreamOverride,
    this.dailyQuestionFutureOverride,
    this.currentUidOverride,
    this.nowOverride,
    this.submitOverride,
    this.commentsStreamOverride,
    this.sendCommentOverride,
  });

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  QuestionService? _serviceInstance;
  QuestionService get _service => _serviceInstance ??= QuestionService();

  late final DateTime _now = widget.nowOverride ?? DateTime.now();
  late final String _dateKey = DateFormat('yyyy-MM-dd').format(_now);
  late final Future<String?> _dailyQuestionFuture =
      widget.dailyQuestionFutureOverride ?? _service.fetchDailyQuestion(_dateKey);

  late final Stream<List<QuestionAnswer>> _answersStream =
      widget.answersStreamOverride ?? _service.watchRecentAnswers(widget.coupleId);

  late final Stream<List<QuestionComment>> _commentsStream =
      widget.commentsStreamOverride ?? _service.watchRecentComments(widget.coupleId);

  String get _uid => widget.currentUidOverride ?? FirebaseAuth.instance.currentUser!.uid;
  String get _partnerUid =>
      widget.memberIds.firstWhere((id) => id != _uid, orElse: () => '');

  final _answerController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _submit(String question) async {
    final text = _answerController.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final override = widget.submitOverride;
      if (override != null) {
        await override(text, question);
      } else {
        await _service.submitAnswer(widget.coupleId, _dateKey, text, question: question);
      }
    } catch (_) {
      // 失敗しても入力欄は消さず、押し直せる状態に戻す（送信中のまま固まらない）。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回答の送信に失敗しました。もう一度お試しください')),
        );
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _sendComment(String dateKey, String text) {
    final override = widget.sendCommentOverride;
    if (override != null) return override(dateKey, text);
    return _service.addComment(widget.coupleId, dateKey, text);
  }

  static const _loadErrorMessage = Center(
    child: Text('読み込みに失敗しました\nしばらくしてから開き直してください',
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('ふたりの質問')),
      body: FutureBuilder<String?>(
        future: _dailyQuestionFuture,
        builder: (context, questionSnap) {
          // 読めなかったときに手書きの質問へ切り替えると、相手と違う質問に
          // 答えてしまうので、エラーとして止める（無い日だけ切り替える）。
          if (questionSnap.hasError) return _loadErrorMessage;
          if (questionSnap.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: appAccent(context)));
          }
          return _buildBody(questionSnap.data ?? pickDailyQuestion(_now));
        },
      ),
    );
  }

  // コメントは回答とは別のストリーム。読めなくても回答は見せ、
  // コメント欄だけで失敗を知らせる（画面全体をエラーにしない）。
  Widget _buildBody(String question) {
    return StreamBuilder<List<QuestionComment>>(
      stream: _commentsStream,
      builder: (context, commentSnap) => _buildAnswersBody(question, commentSnap),
    );
  }

  Widget _buildAnswersBody(String question, AsyncSnapshot<List<QuestionComment>> commentSnap) {
    return StreamBuilder<List<QuestionAnswer>>(
      stream: _answersStream,
      builder: (context, snap) {
        // hasDataだけを見ていると、権限エラー等でストリームがエラーに
        // 落ちたときに無限ローディングのまま固まる。
        if (snap.hasError) return _loadErrorMessage;
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: appAccent(context)));
        }

        final answers = snap.data!;
        QuestionAnswer? answerOf(String uid, String dateKey) {
          for (final a in answers) {
            if (a.uid == uid && a.dateKey == dateKey) return a;
          }
          return null;
        }

        final myAnswer = answerOf(_uid, _dateKey);
        final partnerUid = _partnerUid;
        final partnerAnswer = partnerUid.isEmpty ? null : answerOf(partnerUid, _dateKey);
        final streak = computeQuestionStreak(answers, widget.memberIds, _now);

        // 過去の日付（今日を除く）を新しい順に。ストリームはFirestore側でも
        // 新しい順に並んでいるが、テストからの注入では順序を保証できないため
        // ここでも並べ替える。
        final historyDates = answers
            .map((a) => a.dateKey)
            .where((d) => d != _dateKey)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

        // コメント欄は2人とも回答した日だけ出す。片方が未回答のうちに
        // やり取りできると、回答前に相手の答えをほのめかされてしまうため。
        Widget commentThread(String dateKey, {bool expanded = false}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: QuestionCommentThread(
            key: ValueKey('comments-$dateKey'),
            comments: commentSnap.hasData
                ? (commentSnap.data!.where((c) => c.dateKey == dateKey).toList()
                    ..sort((a, b) => a.createdAt.compareTo(b.createdAt)))
                : null,
            hasError: commentSnap.hasError,
            myUid: _uid,
            partnerName: widget.partnerName,
            initiallyExpanded: expanded,
            onSend: (text) => _sendComment(dateKey, text),
          ),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildQuestionCard(question, streak),
              const SizedBox(height: 20),
              if (myAnswer == null)
                _buildAnswerInput(question)
              else ...[
                _buildAnswerTile('あなた', myAnswer.text),
                const SizedBox(height: 12),
                if (partnerAnswer != null) ...[
                  _buildAnswerTile(widget.partnerName, partnerAnswer.text),
                  commentThread(_dateKey, expanded: true),
                ] else
                  _buildWaitingTile(),
              ],
              if (historyDates.isNotEmpty) ...[
                const SizedBox(height: 28),
                const SectionLabel('これまでの質問'),
                for (final date in historyDates) ...[
                  _buildHistoryCard(
                    date,
                    answerOf(_uid, date),
                    partnerUid.isEmpty ? null : answerOf(partnerUid, date),
                    commentThread,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuestionCard(String question, int streak) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.navySurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('今日の質問', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            // 0日でも消さずに出しておく。途切れたときに表示ごと消えると、
            // 連続記録の機能そのものが無くなったように見えるため。
            Text('🔥 $streak日連続',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: streak > 0 ? appAccent(context) : AppColors.textMuted,
              )),
          ],
        ),
        const SizedBox(height: 8),
        Text(question, style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.5)),
      ],
    ),
  );

  Widget _buildAnswerInput(String question) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _answerController,
        maxLines: 3,
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        decoration: const InputDecoration(hintText: '答えを入力'),
      ),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: _submitting ? null : () => _submit(question),
        child: const Text('回答する'),
      ),
    ],
  );

  Widget _buildAnswerTile(String label, String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.navySurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
      ],
    ),
  );

  Widget _buildWaitingTile() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.navySurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Row(children: [
      const Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
      const SizedBox(width: 8),
      Expanded(
        child: Text('${widget.partnerName}が回答すると表示されます',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ),
    ]),
  );

  // 過去1日分。その日の質問は回答と一緒に残した質問文を出し、それが無い
  // 古い回答（手書きの質問を日付で選んでいた頃）は日付から復元する。
  // 「自分が回答するまで相手の回答は見えない」ルールは過去分にも同じく効かせる。
  // ここを緩めると、答えずに待って相手の回答だけ読む、が成立してしまう。
  Widget _buildHistoryCard(
    String dateKey,
    QuestionAnswer? mine,
    QuestionAnswer? partner,
    Widget Function(String dateKey) commentThread,
  ) {
    final question = mine?.question ?? partner?.question ?? questionForDateKey(dateKey);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateKey, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          if (question != null) ...[
            const SizedBox(height: 6),
            Text(question, style: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary, height: 1.5)),
          ],
          if (mine != null) ...[
            const SizedBox(height: 10),
            _buildAnswerLine('あなた', mine.text),
          ],
          if (partner != null) ...[
            const SizedBox(height: 8),
            mine != null
                ? _buildAnswerLine(widget.partnerName, partner.text)
                : Text('${widget.partnerName}の回答は、あなたが回答していないため伏せられています',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.5)),
          ],
          if (mine != null && partner != null) commentThread(dateKey),
        ],
      ),
    );
  }

  Widget _buildAnswerLine(String label, String text) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      const SizedBox(height: 2),
      Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
    ],
  );
}
