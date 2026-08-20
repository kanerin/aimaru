// ── 日をまたぐ予定が「またいだ日すべて」に現れるようにする ──────────
//
// カレンダーは日付をキーにしたMapを描くため、開始日にしかキーを置かないと
// 複数日の予定が初日にしか出ない（一覧にも、日付の下のドットにも）。
//
// 終了日の表し方は取得元によって違う:
//   - このアプリの予定(AimaruEvent.endDate) … 最終日「を含む」日時
//   - Googleの終日予定(GCalEventSummary.end) … 翌日を指す排他的な値
// この差を各画面で気にせずに済むよう、日付キーの列挙はここへ集約する。

/// 1件の予定を何日ぶんまで展開するかの上限。
/// データ不整合（誤って年単位の終了日が入る等）で際限なく展開し、
/// カレンダー描画が固まるのを防ぐための保険。
/// 通常の旅行・帰省を想定すれば十分な余裕がある値。
const int kMaxEventSpanDays = 60;

/// 時刻を落として日付だけにする。Mapのキーはこの形に揃える。
/// （QuestionAnswer.dateKeyは同名だが別物の文字列なので dayKey と呼び分ける）
DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

/// 翌日。DSTのある地域でも1日ちょうど進むよう、Durationではなく日付で数える。
DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

/// startの日からlastDayの日まで（両端を含む）の日付キーを昇順で返す。
///
/// lastDayがnull、またはstartより前を指している場合は開始日1件だけを返す。
/// 返り値は必ず1件以上ある。
List<DateTime> daysBetween(
  DateTime start,
  DateTime? lastDay, {
  int maxSpanDays = kMaxEventSpanDays,
}) {
  final startKey = dayKey(start);
  final endKey = lastDay == null ? startKey : dayKey(lastDay);

  final days = <DateTime>[startKey];
  var day = startKey;
  while (day.isBefore(endKey) && days.length < maxSpanDays) {
    day = _nextDay(day);
    days.add(day);
  }
  return days;
}

/// Googleカレンダーの予定が占める最終日（その日を含む）。
///
/// 終日予定のendは「翌日」を指す排他的な値なので1日戻す。
/// 時刻指定でちょうど翌日00:00に終わる予定も、その日には何も無いので前日を最終日とする。
/// 戻した結果が開始日より前になる場合は開始日で頭打ちにする（単日として扱う）。
DateTime gcalLastDay({
  required DateTime start,
  required DateTime end,
  required bool allDay,
}) {
  final startKey = dayKey(start);
  final endKey = dayKey(end);
  final endsAtMidnight = end.hour == 0 && end.minute == 0 && end.second == 0;

  final lastKey = (allDay || endsAtMidnight) && endKey.isAfter(startKey)
      ? DateTime(endKey.year, endKey.month, endKey.day - 1)
      : endKey;

  return lastKey.isBefore(startKey) ? startKey : lastKey;
}
