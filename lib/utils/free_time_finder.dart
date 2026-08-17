import '../models/models.dart';
import 'japan_holidays.dart';

// ── 2人の空き時間検出 ──────────────────────────────────
//
// 共有予定（AimaruEvent）と双方のGoogleカレンダーキャッシュ
// （GCalEventSummary）はどちらもFirestore上の1箇所（couples/{coupleId}配下）
// に既に集まっている。TimeTreeのような大手が構造的に持てない優位性は
// ここにあり、「2人とも空いている時間」をアプリ側で計算して提案できる。

class BusyInterval {
  final DateTime start;
  final DateTime end;
  const BusyInterval({required this.start, required this.end});
}

class FreeSlot {
  final DateTime start;
  final DateTime end;
  const FreeSlot({required this.start, required this.end});
  Duration get duration => end.difference(start);
}

// 予定1件の終了時刻。終日は日付が変わるまで、時刻指定は endDate（無ければ
// 1時間）をそのまま使う。event_form_screen.dart の新規作成時デフォルト
// （endDate未指定なら+1時間）と揃えている。
BusyInterval intervalForEvent(AimaruEvent event) {
  if (event.allDay) {
    final day = DateTime(event.date.year, event.date.month, event.date.day);
    return BusyInterval(start: day, end: day.add(const Duration(days: 1)));
  }
  return BusyInterval(
    start: event.date,
    end: event.endDate ?? event.date.add(const Duration(hours: 1)),
  );
}

BusyInterval intervalForGCalEvent(GCalEventSummary event) {
  if (event.allDay) {
    final day = DateTime(event.start.year, event.start.month, event.start.day);
    return BusyInterval(start: day, end: day.add(const Duration(days: 1)));
  }
  return BusyInterval(start: event.start, end: event.end);
}

// 重なる・隣接する予定をひとまとめにする（開始時刻順）
List<BusyInterval> _mergeIntervals(List<BusyInterval> intervals) {
  if (intervals.isEmpty) return [];
  final sorted = [...intervals]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <BusyInterval>[sorted.first];
  for (final current in sorted.skip(1)) {
    final last = merged.last;
    if (current.start.isAfter(last.end)) {
      merged.add(current);
    } else if (current.end.isAfter(last.end)) {
      merged[merged.length - 1] = BusyInterval(start: last.start, end: current.end);
    }
  }
  return merged;
}

// [from, to) の範囲のうち、各日 [dayStartHour, dayEndHour) の時間帯だけを
// 対象に、busy のどれとも重ならず minDuration 以上続く時間帯を探す。
// busy は2人分の予定（共有予定＋双方のGoogleカレンダー）を渡す想定で、
// 誰の予定かは区別しない（どちらか一方が塞がっていれば2人とも動けないため）。
List<FreeSlot> findFreeSlots({
  required List<BusyInterval> busy,
  required DateTime from,
  required DateTime to,
  Duration minDuration = const Duration(hours: 1),
  int dayStartHour = 9,
  int dayEndHour = 22,
}) {
  if (!to.isAfter(from)) return [];
  final merged = _mergeIntervals(busy);
  final slots = <FreeSlot>[];

  var day = DateTime(from.year, from.month, from.day);
  final lastDay = DateTime(to.year, to.month, to.day);

  while (!day.isAfter(lastDay)) {
    final dayStart = DateTime(day.year, day.month, day.day, dayStartHour);
    final dayEnd = DateTime(day.year, day.month, day.day, dayEndHour);
    final windowStart = dayStart.isBefore(from) ? from : dayStart;
    final windowEnd = dayEnd.isAfter(to) ? to : dayEnd;

    if (windowEnd.isAfter(windowStart)) {
      var cursor = windowStart;
      for (final b in merged) {
        if (!b.end.isAfter(cursor)) continue;
        if (!b.start.isBefore(windowEnd)) break;
        if (b.start.isAfter(cursor)) {
          final gap = FreeSlot(start: cursor, end: b.start);
          if (gap.duration >= minDuration) slots.add(gap);
        }
        if (b.end.isAfter(cursor)) cursor = b.end;
      }
      if (windowEnd.isAfter(cursor)) {
        final gap = FreeSlot(start: cursor, end: windowEnd);
        if (gap.duration >= minDuration) slots.add(gap);
      }
    }

    day = day.add(const Duration(days: 1));
  }

  return slots;
}

// ── 休みの日だけを対象にする ────────────────────────────
//
// 「空いている時間」を平日の深夜まで含めて並べても実際には会えない。
// 2人の基本の休日（CoupleModel.daysOff）と祝日を休みとみなし、
// その日だけを探索対象にすることで、実際に会える候補だけが並ぶ。

/// その日が「休み」かどうか。
/// 基本の休日に入っている曜日か、（設定していれば）日本の祝日なら休み。
bool isDayOff(
  DateTime day, {
  required List<int> daysOff,
  bool holidaysAreDaysOff = true,
}) {
  if (daysOff.contains(day.weekday)) return true;
  if (holidaysAreDaysOff && JapanHolidays.isHoliday(day)) return true;
  return false;
}

/// 休みの日の空き具合。
/// fullDay: その日の活動時間帯がまるごと空いている（1日デートできる）
/// partial: 予定の合間に会える時間がある（ちょっと会える）
enum FreeDayKind { fullDay, partial }

class FreeDay {
  final DateTime date;
  final FreeDayKind kind;
  final List<FreeSlot> slots;

  const FreeDay({required this.date, required this.kind, required this.slots});

  /// その日でいちばん長く空いている時間帯
  FreeSlot get longestSlot =>
      slots.reduce((a, b) => a.duration >= b.duration ? a : b);

  Duration get totalFree =>
      slots.fold(Duration.zero, (sum, s) => sum + s.duration);
}

/// [from, to] のうち休みの日について、空き具合を日単位でまとめる。
///
/// busy には2人分の予定（共有予定＋双方のGoogleカレンダー）を渡す。
/// 予定がまったく無く活動時間帯がまるごと空いていれば fullDay、
/// 予定の合間に minDuration 以上の空きがあれば partial として返す。
/// 今日のように途中から始まる日は、時間帯が丸ごと空いているとは言えないため
/// fullDay にはしない。
List<FreeDay> findFreeDays({
  required List<BusyInterval> busy,
  required DateTime from,
  required DateTime to,
  required List<int> daysOff,
  bool holidaysAreDaysOff = true,
  Duration minDuration = const Duration(hours: 2),
  int dayStartHour = 9,
  int dayEndHour = 22,
}) {
  if (!to.isAfter(from)) return [];

  final result = <FreeDay>[];
  var day = DateTime(from.year, from.month, from.day);
  final lastDay = DateTime(to.year, to.month, to.day);

  while (!day.isAfter(lastDay)) {
    final current = day;
    day = day.add(const Duration(days: 1));

    if (!isDayOff(current, daysOff: daysOff, holidaysAreDaysOff: holidaysAreDaysOff)) {
      continue;
    }

    final dayStart = DateTime(current.year, current.month, current.day, dayStartHour);
    final dayEnd = DateTime(current.year, current.month, current.day, dayEndHour);

    final slots = findFreeSlots(
      busy: busy,
      from: from.isAfter(dayStart) ? from : dayStart,
      to: to.isBefore(dayEnd) ? to : dayEnd,
      minDuration: minDuration,
      dayStartHour: dayStartHour,
      dayEndHour: dayEndHour,
    );
    if (slots.isEmpty) continue;

    // 活動時間帯がまるごと1つの空きで埋まっていれば「1日空いている」
    final isFullDay = slots.length == 1 &&
        !slots.first.start.isAfter(dayStart) &&
        !slots.first.end.isBefore(dayEnd);

    result.add(FreeDay(
      date: current,
      kind: isFullDay ? FreeDayKind.fullDay : FreeDayKind.partial,
      slots: slots,
    ));
  }

  return result;
}
