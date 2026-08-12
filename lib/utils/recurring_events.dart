import '../models/models.dart';

// ── 毎年繰り返す予定を、表示する年にも現れるようにする ──────────
//
// Firestoreには予定を1件しか持たない（誕生日なら生年月日など、登録時の日付）。
// カレンダーはその日付をそのままキーにして描くため、展開しないと
// 「毎年繰り返す」にしても最初の1日にしか出ない。誕生日は過去の日付で
// 登録されることが多く、その場合はどの年にも現れなくなる。
//
// リマインダー側（functions/src/reminder_logic.ts）は既に繰り返しを解釈して
// いるので、通知は来るのにカレンダーには無い、という食い違いも起きていた。

// 指定した年における発生日。
// 2月29日は平年に存在しないため、月末（2/28）で頭打ちにする。3月へ繰り上げると
// 記念日の月が変わってしまう（リマインダー側と同じ方針）。
DateTime occurrenceIn(int year, DateTime original) {
  final lastDayOfMonth = DateTime(year, original.month + 1, 0).day;
  final day = original.day > lastDayOfMonth ? lastDayOfMonth : original.day;
  return DateTime(year, original.month, day, original.hour, original.minute);
}

// 基準日以降で最初に来る発生日。今年の分が過ぎていれば来年へ送る。
DateTime nextOccurrence(DateTime original, {required DateTime from}) {
  final today = DateTime(from.year, from.month, from.day);
  final thisYear = occurrenceIn(from.year, original);
  final thisYearDay = DateTime(thisYear.year, thisYear.month, thisYear.day);
  return thisYearDay.isBefore(today) ? occurrenceIn(from.year + 1, original) : thisYear;
}

// 日付をキーにした予定のMapへ、繰り返し予定の各年の発生日を足して返す。
// 元の日付の予定はそのまま残す（登録した年にも表示されるべきなので）。
Map<DateTime, List<AimaruEvent>> expandRecurringEvents(
  Map<DateTime, List<AimaruEvent>> source, {
  required Iterable<int> years,
}) {
  final result = <DateTime, List<AimaruEvent>>{};

  void put(DateTime key, AimaruEvent event) {
    final list = result.putIfAbsent(key, () => []);
    // 同じ予定を同じ日に二重に置かない（登録年と展開先が重なる場合）
    if (list.any((e) => e.id == event.id)) return;
    list.add(event);
  }

  source.forEach((key, events) {
    for (final event in events) {
      put(key, event);
      if (!event.recurring) continue;
      for (final year in years) {
        final occurrence = occurrenceIn(year, event.date);
        put(DateTime(occurrence.year, occurrence.month, occurrence.day), event);
      }
    }
  });

  return result;
}
