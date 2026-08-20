import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/utils/event_days.dart';

// 日をまたぐ予定の日付キー列挙。
//
// 開始日にしかキーを置かないと、複数日の予定が初日にしか出ない
// （一覧にも、ミニカレンダーの日付下のドットにも）。実際に
// 「複数日にまたがる予定の・が初日にしかつかない」という報告が上がった。
void main() {
  group('daysBetween', () {
    test('終了日がなければ開始日の1件だけ', () {
      expect(
        daysBetween(DateTime(2026, 9, 26, 10, 30), null),
        [DateTime(2026, 9, 26)],
      );
    });

    test('同じ日で終わる予定も1件だけ', () {
      expect(
        daysBetween(DateTime(2026, 9, 26, 10), DateTime(2026, 9, 26, 18)),
        [DateTime(2026, 9, 26)],
      );
    });

    test('日をまたぐ予定は両端を含めて全日ぶん返す', () {
      expect(
        daysBetween(DateTime(2026, 9, 26, 10), DateTime(2026, 9, 28, 18)),
        [DateTime(2026, 9, 26), DateTime(2026, 9, 27), DateTime(2026, 9, 28)],
      );
    });

    test('月をまたいでも連続した日付になる', () {
      expect(
        daysBetween(DateTime(2026, 9, 29), DateTime(2026, 10, 2)),
        [
          DateTime(2026, 9, 29),
          DateTime(2026, 9, 30),
          DateTime(2026, 10, 1),
          DateTime(2026, 10, 2),
        ],
      );
    });

    test('年をまたいでも連続した日付になる', () {
      expect(
        daysBetween(DateTime(2026, 12, 31), DateTime(2027, 1, 2)),
        [DateTime(2026, 12, 31), DateTime(2027, 1, 1), DateTime(2027, 1, 2)],
      );
    });

    // データ不整合で終了日が開始日より前になっていても、
    // 空を返して予定が消えるより単日として出したほうが害が小さい。
    test('終了日が開始日より前でも開始日の1件を返す', () {
      expect(
        daysBetween(DateTime(2026, 9, 26), DateTime(2026, 9, 20)),
        [DateTime(2026, 9, 26)],
      );
    });

    test('展開の上限を超えない（描画が固まるのを防ぐ保険）', () {
      final days = daysBetween(DateTime(2026, 1, 1), DateTime(2030, 1, 1));
      expect(days.length, kMaxEventSpanDays);
    });

    test('上限は呼び出し側で狭められる', () {
      expect(
        daysBetween(DateTime(2026, 9, 26), DateTime(2026, 12, 31), maxSpanDays: 3),
        [DateTime(2026, 9, 26), DateTime(2026, 9, 27), DateTime(2026, 9, 28)],
      );
    });
  });

  group('gcalLastDay', () {
    // Googleの終日予定のendは「翌日」を指す。そのまま最終日として扱うと
    // 1日多く表示されてしまう。
    test('終日予定のendは排他的なので1日戻す', () {
      expect(
        gcalLastDay(
          start: DateTime(2026, 9, 26),
          end: DateTime(2026, 9, 29),
          allDay: true,
        ),
        DateTime(2026, 9, 28),
      );
    });

    test('1日だけの終日予定は開始日と同じ日', () {
      expect(
        gcalLastDay(
          start: DateTime(2026, 9, 26),
          end: DateTime(2026, 9, 27),
          allDay: true,
        ),
        DateTime(2026, 9, 26),
      );
    });

    // 排他的でない（endが開始日と同じ）壊れたデータでも開始日で頭打ちにする。
    test('終日でendが開始日と同じでも開始日より前へ戻さない', () {
      expect(
        gcalLastDay(
          start: DateTime(2026, 9, 26),
          end: DateTime(2026, 9, 26),
          allDay: true,
        ),
        DateTime(2026, 9, 26),
      );
    });

    test('時刻指定の予定はendの日付がそのまま最終日', () {
      expect(
        gcalLastDay(
          start: DateTime(2026, 9, 26, 22),
          end: DateTime(2026, 9, 27, 2),
          allDay: false,
        ),
        DateTime(2026, 9, 27),
      );
    });

    // 翌日00:00ちょうどに終わる予定は、その日には何も無い。
    test('時刻指定でちょうど翌日00:00に終わる予定は前日が最終日', () {
      expect(
        gcalLastDay(
          start: DateTime(2026, 9, 26, 19),
          end: DateTime(2026, 9, 27),
          allDay: false,
        ),
        DateTime(2026, 9, 26),
      );
    });

    test('同日で完結する時刻指定の予定は開始日と同じ日', () {
      expect(
        gcalLastDay(
          start: DateTime(2026, 9, 26, 10),
          end: DateTime(2026, 9, 26, 12),
          allDay: false,
        ),
        DateTime(2026, 9, 26),
      );
    });
  });
}
