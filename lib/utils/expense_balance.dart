import '../models/models.dart';

// ── 割り勘の精算額の計算 ─────────────────────────────
// カップル（2人）前提で、それぞれが払った合計の差の半分を
// 「多く払った方が受け取るべき額」として返す。3人以上は現状の
// ペア機能では発生しないため未対応（0円扱いにする）。
class ExpenseBalance {
  // 追加で払うべき人。精算済み（amount == 0）ならnull。
  final String? owedByUid;
  // 受け取るべき人。精算済み（amount == 0）ならnull。
  final String? owedToUid;
  final int amount;

  const ExpenseBalance({this.owedByUid, this.owedToUid, this.amount = 0});
}

ExpenseBalance calculateBalance(List<ExpenseItem> expenses, List<String> memberIds) {
  if (memberIds.length != 2) return const ExpenseBalance();

  final paidTotals = <String, int>{};
  for (final expense in expenses) {
    paidTotals[expense.paidBy] = (paidTotals[expense.paidBy] ?? 0) + expense.amount;
  }

  final a = memberIds[0];
  final b = memberIds[1];
  final diff = (paidTotals[a] ?? 0) - (paidTotals[b] ?? 0);
  // 差が奇数だと端数(1円)が出るが、割り勘アプリとしては切り捨てで十分。
  final half = diff.abs() ~/ 2;
  if (half == 0) return const ExpenseBalance();

  return diff > 0
      ? ExpenseBalance(owedByUid: b, owedToUid: a, amount: half)
      : ExpenseBalance(owedByUid: a, owedToUid: b, amount: half);
}
