import '../models/models.dart';

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
