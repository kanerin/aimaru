// ── ふたりの質問の連続回答日数（ストリーク）─────────────────
// サービス終了したPairyの移行先として比較されるTwinestは「付き合った日数」の
// カウンター表示を持つが、AIMARUは既存の「ふたりの質問」に日々の継続を
// 可視化する仕組みが無かった。新しいFirestoreコレクションやcrudは増やさず、
// 既存の回答履歴（QuestionAnswer）から純粋関数で連続日数を数える。

import 'package:intl/intl.dart';
import '../models/models.dart';

/// [answers]（`watchRecentAnswers`で取れる直近の回答一覧）から、
/// [memberIds] 全員が回答した日が [today] を起点に何日連続で続いているかを数える。
///
/// 今日分がまだ全員分揃っていなくても、昨日までの連続が保たれていれば
/// 継続中として数える（日付が変わった直後に0へ戻ると、寝る前に回答する
/// 習慣のカップルの連続記録が毎晩リセットされて見えてしまうため）。
/// カップル成立前などmemberIdsが2人に満たない場合は常に0を返す。
int computeQuestionStreak(
  List<QuestionAnswer> answers,
  List<String> memberIds,
  DateTime today,
) {
  if (memberIds.length < 2) return 0;

  final uidsByDateKey = <String, Set<String>>{};
  for (final answer in answers) {
    uidsByDateKey.putIfAbsent(answer.dateKey, () => <String>{}).add(answer.uid);
  }

  bool bothAnswered(DateTime date) {
    final uids = uidsByDateKey[DateFormat('yyyy-MM-dd').format(date)];
    if (uids == null) return false;
    return memberIds.every(uids.contains);
  }

  var cursor = DateTime(today.year, today.month, today.day);
  if (!bothAnswered(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!bothAnswered(cursor)) return 0;
  }

  var streak = 0;
  while (bothAnswered(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}
