import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/question_service.dart';
import '../utils/app_theme.dart';
import '../utils/daily_question_picker.dart';
import '../utils/question_streak.dart';
import '../widgets/section_label.dart';

// ── ふたりの質問（デイリー質問）─────────────────────────
// TimeTreeなど競合のカレンダー機能には無い「お互いを知る」体験。
// サービス終了したPairyの移行先として比較されるSumOne/Twinestが持つ
// 質問カード機能に近い差別化要素。2人とも回答するまでパートナーの回答は
// 伏せておき、相手の回答に引っ張られない素直な回答を引き出す。
//
// 今日の分だけでなく、過去の質問と回答も同じ画面から振り返れる
// （ふたりの日記と同じく、直近をまとめて1本のストリームで読む）。
class QuestionsScreen extends StatefulWidget {
  final String coupleId;
  final List<String> memberIds;
  final String partnerName;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<QuestionAnswer>>? answersStreamOverride;
  // テストからFirebase Authに触れずに「自分」を差し込むための注入ポイント。
  final String? currentUidOverride;
  // テストから「今日」を固定するための注入ポイント。
  final DateTime? nowOverride;

  const QuestionsScreen({
    super.key,
    required this.coupleId,
    required this.memberIds,
    required this.partnerName,
    this.answersStreamOverride,
    this.currentUidOverride,
    this.nowOverride,
  });

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  QuestionService? _serviceInstance;
  QuestionService get _service => _serviceInstance ??= QuestionService();

  late final DateTime _now = widget.nowOverride ?? DateTime.now();
  late final String _dateKey = DateFormat('yyyy-MM-dd').format(_now);
  late final String _question = pickDailyQuestion(_now);

  late final Stream<List<QuestionAnswer>> _answersStream =
      widget.answersStreamOverride ?? _service.watchRecentAnswers(widget.coupleId);

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

  Future<void> _submit() async {
    final text = _answerController.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    await _service.submitAnswer(widget.coupleId, _dateKey, text);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('ふたりの質問')),
      body: StreamBuilder<List<QuestionAnswer>>(
        stream: _answersStream,
        builder: (context, snap) {
          // hasDataだけを見ていると、権限エラー等でストリームがエラーに
          // 落ちたときに無限ローディングのまま固まる。
          if (snap.hasError) {
            return const Center(
              child: Text('読み込みに失敗しました\nしばらくしてから開き直してください',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            );
          }
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildQuestionCard(streak),
                const SizedBox(height: 20),
                if (myAnswer == null)
                  _buildAnswerInput()
                else ...[
                  _buildAnswerTile('あなた', myAnswer.text),
                  const SizedBox(height: 12),
                  partnerAnswer != null
                      ? _buildAnswerTile(widget.partnerName, partnerAnswer.text)
                      : _buildWaitingTile(),
                ],
                if (historyDates.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const SectionLabel('これまでの質問'),
                  for (final date in historyDates) ...[
                    _buildHistoryCard(
                      date,
                      answerOf(_uid, date),
                      partnerUid.isEmpty ? null : answerOf(partnerUid, date),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionCard(int streak) => Container(
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
            if (streak > 0)
              Text('🔥 $streak日連続',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: appAccent(context))),
          ],
        ),
        const SizedBox(height: 8),
        Text(_question, style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.5)),
      ],
    ),
  );

  Widget _buildAnswerInput() => Column(
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
        onPressed: _submitting ? null : _submit,
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

  // 過去1日分。その日の質問は日付から復元する（質問文はFirestoreに持たない）。
  // 「自分が回答するまで相手の回答は見えない」ルールは過去分にも同じく効かせる。
  // ここを緩めると、答えずに待って相手の回答だけ読む、が成立してしまう。
  Widget _buildHistoryCard(String dateKey, QuestionAnswer? mine, QuestionAnswer? partner) {
    final question = questionForDateKey(dateKey);
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
