import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/utils/recurring_events.dart';

// 毎年繰り返す予定の展開。
//
// カレンダーは保存された日付をそのままキーにして描くため、展開しないと
// 誕生日や記念日が登録した1日にしか出ない。生年月日で登録された誕生日は
// どの年にも現れず、「追加したのに反映されない」という形で現れていた。
void main() {
  AimaruEvent build({
    String id = 'e1',
    String title = 'miwaの誕生日',
    required DateTime date,
    DateTime? endDate,
    bool recurring = true,
  }) =>
      AimaruEvent(
        id: id,
        coupleId: 'couple-1',
        title: title,
        date: date,
        endDate: endDate,
        type: EventType.celebrity,
        createdBy: 'user-me',
        recurring: recurring,
        allDay: recurring,
      );

  group('occurrenceIn', () {
    test('指定した年の同じ月日を返す', () {
      expect(
        occurrenceIn(2027, DateTime(1990, 6, 15)),
        DateTime(2027, 6, 15),
      );
    });

    test('時刻は元の予定のものを保つ', () {
      final result = occurrenceIn(2027, DateTime(1990, 6, 15, 19, 30));

      expect(result.hour, 19);
      expect(result.minute, 30);
    });

    test('2月29日は平年なら2月28日へ丸め、3月へ繰り上げない', () {
      expect(occurrenceIn(2027, DateTime(2024, 2, 29)), DateTime(2027, 2, 28));
    });

    test('2月29日は閏年ならそのまま', () {
      expect(occurrenceIn(2028, DateTime(2024, 2, 29)), DateTime(2028, 2, 29));
    });
  });

  group('nextOccurrence', () {
    test('今年の分がまだなら今年を返す', () {
      final result = nextOccurrence(
        DateTime(1990, 12, 24),
        from: DateTime(2026, 8, 12),
      );

      expect(result, DateTime(2026, 12, 24));
    });

    test('今年の分が過ぎていれば来年を返す', () {
      final result = nextOccurrence(
        DateTime(1990, 6, 15),
        from: DateTime(2026, 8, 12),
      );

      expect(result, DateTime(2027, 6, 15));
    });

    test('当日は「過ぎていない」として今年を返す', () {
      final result = nextOccurrence(
        DateTime(1990, 8, 12),
        from: DateTime(2026, 8, 12, 23, 0),
      );

      expect(result, DateTime(2026, 8, 12));
    });
  });

  group('expandRecurringEvents', () {
    test('生年月日で登録した誕生日が、表示する年にも現れる', () {
      final birthday = build(date: DateTime(1990, 6, 15));
      final source = {
        DateTime(1990, 6, 15): [birthday],
      };

      final result = expandRecurringEvents(source, years: [2026, 2027]);

      expect(result[DateTime(2026, 6, 15)]?.single.title, 'miwaの誕生日');
      expect(result[DateTime(2027, 6, 15)]?.single.title, 'miwaの誕生日');
      // 元の日付も残す
      expect(result[DateTime(1990, 6, 15)]?.single.title, 'miwaの誕生日');
    });

    // 日をまたぐ予定を繰り返しにすると、登録年はsource側が全日ぶん持つので
    // 気づきにくいが、展開先の年では初日にしか出ていなかった。
    test('日をまたぐ繰り返し予定は、展開先の年でも同じ日数ぶん占める', () {
      final trip = build(
        title: '結婚記念日旅行',
        date: DateTime(2026, 9, 26),
        endDate: DateTime(2026, 9, 28),
      );
      final source = {
        DateTime(2026, 9, 26): [trip],
        DateTime(2026, 9, 27): [trip],
        DateTime(2026, 9, 28): [trip],
      };

      final result = expandRecurringEvents(source, years: [2027]);

      expect(result[DateTime(2027, 9, 26)]?.single.title, '結婚記念日旅行');
      expect(result[DateTime(2027, 9, 27)]?.single.title, '結婚記念日旅行');
      expect(result[DateTime(2027, 9, 28)]?.single.title, '結婚記念日旅行');
      expect(result[DateTime(2027, 9, 29)], isNull);
    });

    test('終了日のない繰り返し予定は展開先でも1日だけ', () {
      final source = {
        DateTime(1990, 6, 15): [build(date: DateTime(1990, 6, 15))],
      };

      final result = expandRecurringEvents(source, years: [2027]);

      expect(result[DateTime(2027, 6, 15)]?.single.title, 'miwaの誕生日');
      expect(result[DateTime(2027, 6, 16)], isNull);
    });

    test('繰り返しでない予定は展開しない', () {
      final source = {
        DateTime(2026, 8, 22): [
          build(date: DateTime(2026, 8, 22), title: 'デート', recurring: false),
        ],
      };

      final result = expandRecurringEvents(source, years: [2026, 2027]);

      expect(result[DateTime(2027, 8, 22)], isNull);
      expect(result[DateTime(2026, 8, 22)]?.single.title, 'デート');
    });

    test('登録年と展開先が重なっても二重に置かない', () {
      final source = {
        DateTime(2026, 6, 15): [build(date: DateTime(2026, 6, 15))],
      };

      final result = expandRecurringEvents(source, years: [2026, 2027]);

      expect(result[DateTime(2026, 6, 15)]!.length, 1);
    });

    test('同じ日に複数の予定があってもすべて残る', () {
      final source = {
        DateTime(1990, 6, 15): [build(id: 'a', date: DateTime(1990, 6, 15))],
        DateTime(1995, 6, 15): [
          build(id: 'b', title: '別の誕生日', date: DateTime(1995, 6, 15)),
        ],
      };

      final result = expandRecurringEvents(source, years: [2027]);

      expect(result[DateTime(2027, 6, 15)]!.length, 2);
    });

    test('2月29日の記念日を平年へ展開しても3月へ滑らない', () {
      final source = {
        DateTime(2024, 2, 29): [build(date: DateTime(2024, 2, 29), title: '記念日')],
      };

      final result = expandRecurringEvents(source, years: [2027]);

      expect(result[DateTime(2027, 3, 1)], isNull);
      expect(result[DateTime(2027, 2, 28)]?.single.title, '記念日');
    });
  });
}
