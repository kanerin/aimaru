// トーク画面のセンターラインに、日付を跨いだところへ区切りを出すための
// 純粋なロジック（#68: LINEのような日付表示の追加要望）。
// ウィジェット側（chat_screen.dart）から日時比較・整形をこちらへ切り出し、
// Firebase無しで単体テストできるようにしている。

// 直前のメッセージ（無ければnull）と比べて、日付区切りを出すべきかを返す。
// 一覧の先頭（previousがnull）は常に区切りを出す。
bool shouldShowDateDivider(DateTime? previous, DateTime current) {
  if (previous == null) return true;
  return previous.year != current.year ||
      previous.month != current.month ||
      previous.day != current.day;
}
