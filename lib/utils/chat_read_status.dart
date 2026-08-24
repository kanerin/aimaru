// トーク画面の自分の最後のメッセージに「既読」を出すかどうかの純粋な判定
// （LINEのような既読表示。TimeTreeには無く、Pairyの移行先として比較される
// SumOne・Twinest等の1対1トーク寄りの体験に近い差別化要素）。
// ウィジェット側（chat_screen.dart）から時刻比較のロジックを切り出し、
// Firebase無しで単体テストできるようにしている。

// パートナーの最終既読時刻（未読状態ならnull）が、対象メッセージの送信時刻
// 以降であれば既読とみなす。
bool isReadByPartner(DateTime messageTimestamp, DateTime? partnerLastReadAt) {
  if (partnerLastReadAt == null) return false;
  return !partnerLastReadAt.isBefore(messageTimestamp);
}
