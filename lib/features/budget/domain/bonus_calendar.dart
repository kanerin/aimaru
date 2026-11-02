import 'budget_plan.dart';

// ── ボーナスをカレンダーに表示するための日付算出 ───────────────
// 予定（events）として書き込むのではなく、確定プランから毎回算出して
// カレンダーに重ねて表示する（祝日と同じ扱い）。予定として保存すると
// プランを変えるたびに作り直し・消し忘れが起き、相手に「新しい予定」の
// 通知まで飛んでしまうため。
class BonusCalendarEntry {
  final String memberId;
  final String memberName;
  final int amount;
  final DateTime date;
  // 支給日が未設定で、月初に「ボーナス月」として置いたもの
  final bool isMonthOnly;

  const BonusCalendarEntry({
    required this.memberId,
    required this.memberName,
    required this.amount,
    required this.date,
    required this.isMonthOnly,
  });

  String get label => isMonthOnly ? '$memberNameのボーナス月' : '$memberNameのボーナス';
}

// dayにボーナスが支給される（または支給日未設定でdayがその月の1日の）
// メンバーの一覧。支給日がその月に無い日付（2月30日など）なら月末に寄せる。
List<BonusCalendarEntry> bonusEntriesOn(BudgetPlan plan, DateTime day) {
  final entries = <BonusCalendarEntry>[];
  for (final m in plan.members) {
    for (final b in m.bonuses) {
      if (b.month != day.month) continue;
      final lastDay = DateTime(day.year, day.month + 1, 0).day;
      final payDay = b.payDay == null ? 1 : b.payDay!.clamp(1, lastDay);
      if (payDay != day.day) continue;
      entries.add(BonusCalendarEntry(
        memberId:    m.memberId,
        memberName:  m.displayName,
        amount:      b.amount,
        date:        DateTime(day.year, day.month, payDay),
        isMonthOnly: b.payDay == null,
      ));
    }
  }
  return entries;
}
