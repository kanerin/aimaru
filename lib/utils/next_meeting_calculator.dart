// ── 次に会う予定の日までの日数を計算する ────────────────────
// 遠距離・多忙などで頻繁に会えないカップルが「次に会える日」を
// カウントダウンできるようにする、TimeTreeのような汎用カレンダーには
// 無いカップル向けアプリ特有の指標。

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// 正: 未来、0: 当日、負: 過ぎた日
int daysUntilNextMeeting(DateTime meetingDate, DateTime today) {
  return _dateOnly(meetingDate).difference(_dateOnly(today)).inDays;
}
