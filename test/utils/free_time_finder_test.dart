import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/utils/free_time_finder.dart';

// 2人の空き時間検出。共有予定・双方のGoogleカレンダーから、2人とも
// 何も入っていない時間帯を洗い出せているかを検証する。
void main() {
  AimaruEvent buildEvent({
    required DateTime date,
    DateTime? endDate,
    bool allDay = false,
  }) =>
      AimaruEvent(
        id: 'e1',
        coupleId: 'couple-1',
        title: 'デート',
        date: date,
        endDate: endDate,
        type: EventType.date,
        createdBy: 'user-me',
        allDay: allDay,
      );

  group('intervalForEvent', () {
    test('終日予定は日付が変わるまでを塞ぐ', () {
      final interval = intervalForEvent(buildEvent(date: DateTime(2026, 8, 15), allDay: true));

      expect(interval.start, DateTime(2026, 8, 15));
      expect(interval.end, DateTime(2026, 8, 16));
    });

    test('endDate未指定の時刻予定は1時間として扱う', () {
      final interval = intervalForEvent(buildEvent(date: DateTime(2026, 8, 15, 19, 0)));

      expect(interval.start, DateTime(2026, 8, 15, 19, 0));
      expect(interval.end, DateTime(2026, 8, 15, 20, 0));
    });

    test('endDateがあればそれを終了時刻とする', () {
      final interval = intervalForEvent(buildEvent(
        date: DateTime(2026, 8, 15, 19, 0),
        endDate: DateTime(2026, 8, 15, 21, 30),
      ));

      expect(interval.end, DateTime(2026, 8, 15, 21, 30));
    });
  });

  group('intervalForGCalEvent', () {
    test('終日イベントは日付が変わるまでを塞ぐ', () {
      final event = GCalEventSummary(
        id: 'g1', title: '出張', start: DateTime(2026, 8, 15, 3), end: DateTime(2026, 8, 15, 3), allDay: true,
      );

      final interval = intervalForGCalEvent(event);

      expect(interval.start, DateTime(2026, 8, 15));
      expect(interval.end, DateTime(2026, 8, 16));
    });

    test('時刻指定イベントはそのままの開始・終了を使う', () {
      final event = GCalEventSummary(
        id: 'g1', title: '会議', start: DateTime(2026, 8, 15, 10), end: DateTime(2026, 8, 15, 11), allDay: false,
      );

      final interval = intervalForGCalEvent(event);

      expect(interval.start, DateTime(2026, 8, 15, 10));
      expect(interval.end, DateTime(2026, 8, 15, 11));
    });
  });

  group('findFreeSlots', () {
    test('予定が無ければ1日分の時間帯がまるごと空く', () {
      final slots = findFreeSlots(
        busy: [],
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 8, 15, 23, 59),
        dayStartHour: 9,
        dayEndHour: 22,
      );

      expect(slots, hasLength(1));
      expect(slots.single.start, DateTime(2026, 8, 15, 9));
      expect(slots.single.end, DateTime(2026, 8, 15, 22));
    });

    test('丸一日塞がっていれば空き時間は無い', () {
      final slots = findFreeSlots(
        busy: [BusyInterval(start: DateTime(2026, 8, 15), end: DateTime(2026, 8, 16))],
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 8, 15, 23, 59),
      );

      expect(slots, isEmpty);
    });

    test('予定と予定の間が空き時間として出る', () {
      final slots = findFreeSlots(
        busy: [
          BusyInterval(start: DateTime(2026, 8, 15, 10), end: DateTime(2026, 8, 15, 12)),
          BusyInterval(start: DateTime(2026, 8, 15, 15), end: DateTime(2026, 8, 15, 16)),
        ],
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 8, 15, 23, 59),
        dayStartHour: 9,
        dayEndHour: 22,
      );

      expect(slots, hasLength(3));
      expect(slots[0].start, DateTime(2026, 8, 15, 9));
      expect(slots[0].end, DateTime(2026, 8, 15, 10));
      expect(slots[1].start, DateTime(2026, 8, 15, 12));
      expect(slots[1].end, DateTime(2026, 8, 15, 15));
      expect(slots[2].start, DateTime(2026, 8, 15, 16));
      expect(slots[2].end, DateTime(2026, 8, 15, 22));
    });

    test('片方だけの予定でも塞がる（誰の予定かは区別しない）', () {
      final slots = findFreeSlots(
        busy: [BusyInterval(start: DateTime(2026, 8, 15, 9), end: DateTime(2026, 8, 15, 22))],
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 8, 15, 23, 59),
      );

      expect(slots, isEmpty);
    });

    test('重なる予定はまとめて1つの空白として扱う', () {
      final slots = findFreeSlots(
        busy: [
          BusyInterval(start: DateTime(2026, 8, 15, 10), end: DateTime(2026, 8, 15, 13)),
          BusyInterval(start: DateTime(2026, 8, 15, 12), end: DateTime(2026, 8, 15, 14)),
        ],
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 8, 15, 23, 59),
        dayStartHour: 9,
        dayEndHour: 22,
      );

      expect(slots, hasLength(2));
      expect(slots[0].end, DateTime(2026, 8, 15, 10));
      expect(slots[1].start, DateTime(2026, 8, 15, 14));
    });

    test('minDurationより短い隙間は除外する', () {
      final slots = findFreeSlots(
        busy: [
          BusyInterval(start: DateTime(2026, 8, 15, 10), end: DateTime(2026, 8, 15, 12)),
          BusyInterval(start: DateTime(2026, 8, 15, 12, 30), end: DateTime(2026, 8, 15, 14)),
        ],
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 8, 15, 23, 59),
        dayStartHour: 9,
        dayEndHour: 22,
        minDuration: const Duration(hours: 1),
      );

      // 12:00-12:30 の30分は minDuration(1時間) 未満なので出てこない
      expect(slots.any((s) => s.start == DateTime(2026, 8, 15, 12)), isFalse);
    });

    test('複数日にまたがって毎日の時間帯を探す', () {
      final slots = findFreeSlots(
        busy: [],
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 8, 16, 23, 59),
        dayStartHour: 9,
        dayEndHour: 22,
      );

      expect(slots, hasLength(2));
      expect(slots[0].start, DateTime(2026, 8, 15, 9));
      expect(slots[1].start, DateTime(2026, 8, 16, 9));
    });

    test('fromが日中なら初日はfromから始まる', () {
      final slots = findFreeSlots(
        busy: [],
        from: DateTime(2026, 8, 15, 14),
        to: DateTime(2026, 8, 15, 23, 59),
        dayStartHour: 9,
        dayEndHour: 22,
      );

      expect(slots.single.start, DateTime(2026, 8, 15, 14));
    });

    test('toが日中なら最終日はtoで終わる', () {
      final slots = findFreeSlots(
        busy: [],
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 8, 15, 18),
        dayStartHour: 9,
        dayEndHour: 22,
      );

      expect(slots.single.end, DateTime(2026, 8, 15, 18));
    });

    test('toがfrom以前なら空き時間は無い', () {
      final slots = findFreeSlots(
        busy: [],
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 8, 14),
      );

      expect(slots, isEmpty);
    });
  });
}
