import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/utils/free_time_finder.dart';
import 'package:aimaru/utils/japan_holidays.dart';

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

  group('isDayOff', () {
    test('基本の休日に入っている曜日は休み', () {
      // 2026-08-15 は土曜
      expect(
        isDayOff(DateTime(2026, 8, 15), daysOff: const [DateTime.saturday, DateTime.sunday]),
        isTrue,
      );
      // 2026-08-19 は水曜
      expect(
        isDayOff(DateTime(2026, 8, 19), daysOff: const [DateTime.saturday, DateTime.sunday]),
        isFalse,
      );
    });

    test('平日休みの職種でも指定した曜日が休みになる', () {
      expect(
        isDayOff(DateTime(2026, 8, 19), daysOff: const [DateTime.wednesday]),
        isTrue,
      );
    });

    test('祝日は休み扱いにでき、切ることもできる', () {
      final sportsDay = DateTime(2026, 10, 12); // スポーツの日（月曜）
      expect(JapanHolidays.isHoliday(sportsDay), isTrue);

      expect(isDayOff(sportsDay, daysOff: const []), isTrue);
      expect(
        isDayOff(sportsDay, daysOff: const [], holidaysAreDaysOff: false),
        isFalse,
      );
    });
  });

  group('findFreeDays', () {
    const weekend = [DateTime.saturday, DateTime.sunday];

    test('平日は休みでないので候補に出ない', () {
      // 2026-08-17(月)〜21(金) は平日のみ
      final days = findFreeDays(
        busy: const [],
        from: DateTime(2026, 8, 17),
        to: DateTime(2026, 8, 21, 23, 59),
        daysOff: weekend,
      );

      expect(days, isEmpty);
    });

    test('予定が無い休日はまるごと空いている日として返る', () {
      // 2026-08-22(土), 23(日)
      final days = findFreeDays(
        busy: const [],
        from: DateTime(2026, 8, 22),
        to: DateTime(2026, 8, 23, 23, 59),
        daysOff: weekend,
      );

      expect(days, hasLength(2));
      expect(days.every((d) => d.kind == FreeDayKind.fullDay), isTrue);
      expect(days.first.date, DateTime(2026, 8, 22));
    });

    test('予定の合間に空きがある休日はちょっと会える日として返る', () {
      final days = findFreeDays(
        busy: [
          BusyInterval(
            start: DateTime(2026, 8, 22, 9),
            end: DateTime(2026, 8, 22, 15),
          ),
        ],
        from: DateTime(2026, 8, 22),
        to: DateTime(2026, 8, 22, 23, 59),
        daysOff: weekend,
      );

      expect(days, hasLength(1));
      expect(days.single.kind, FreeDayKind.partial);
      expect(days.single.longestSlot.start, DateTime(2026, 8, 22, 15));
      expect(days.single.longestSlot.end, DateTime(2026, 8, 22, 22));
    });

    test('一日中予定で埋まっている休日は候補に出ない', () {
      final days = findFreeDays(
        busy: [
          BusyInterval(
            start: DateTime(2026, 8, 22),
            end: DateTime(2026, 8, 23),
          ),
        ],
        from: DateTime(2026, 8, 22),
        to: DateTime(2026, 8, 22, 23, 59),
        daysOff: weekend,
      );

      expect(days, isEmpty);
    });

    test('途中から始まる日はまるごと空いているとは扱わない', () {
      // 土曜の15時から探し始めた場合、その日は「1日空いている」ではない
      final days = findFreeDays(
        busy: const [],
        from: DateTime(2026, 8, 22, 15),
        to: DateTime(2026, 8, 22, 23, 59),
        daysOff: weekend,
      );

      expect(days.single.kind, FreeDayKind.partial);
      expect(days.single.longestSlot.start, DateTime(2026, 8, 22, 15));
    });

    test('短すぎる空きしかない休日は候補に出ない', () {
      final days = findFreeDays(
        busy: [
          BusyInterval(
            start: DateTime(2026, 8, 22, 9),
            end: DateTime(2026, 8, 22, 21),
          ),
        ],
        from: DateTime(2026, 8, 22),
        to: DateTime(2026, 8, 22, 23, 59),
        daysOff: weekend,
        minDuration: const Duration(hours: 2),
      );

      expect(days, isEmpty);
    });

    test('Googleカレンダーの予定も塞がりとして扱われる', () {
      final gcal = GCalEventSummary(
        id: 'g1',
        title: '出張',
        start: DateTime(2026, 8, 22, 9),
        end: DateTime(2026, 8, 22, 22),
        allDay: false,
      );

      final days = findFreeDays(
        busy: [intervalForGCalEvent(gcal)],
        from: DateTime(2026, 8, 22),
        to: DateTime(2026, 8, 22, 23, 59),
        daysOff: weekend,
      );

      expect(days, isEmpty);
    });
  });
}
