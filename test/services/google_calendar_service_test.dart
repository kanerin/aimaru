import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/google_calendar_service.dart';

// Googleカレンダーとの値の受け渡しで壊れやすい2点を検証する。
//
// どちらも実際に不具合として現れた箇所:
// - googleapis は RFC3339 を DateTime.parse で読むためUTCが返り、
//   そのまま表示すると9時間ずれていた
// - 終日の end.date は排他的（翌日）で、アプリ内の「最終日」とずれる
void main() {
  group('normalizeGCalDateTime', () {
    test('時刻付きはローカル時刻へ直す', () {
      // Googleは 2026-08-14T19:00:00+09:00 を UTC 10:00 として返す
      final fromGoogle = DateTime.utc(2026, 8, 14, 10, 0);

      final result = normalizeGCalDateTime(fromGoogle, isAllDay: false);

      expect(result!.isUtc, isFalse);
      // 同じ瞬間を指したまま、ローカルの壁時計として読める
      expect(result.isAtSameMomentAs(fromGoogle), isTrue);
      expect(result, fromGoogle.toLocal());
    });

    test('終日は年月日をそのまま使い、タイムゾーンでずらさない', () {
      // 終日の date は日付だけを表すUTC値として返る
      final fromGoogle = DateTime.utc(2026, 8, 14);

      final result = normalizeGCalDateTime(fromGoogle, isAllDay: true);

      expect(result, DateTime(2026, 8, 14));
      expect(result!.isUtc, isFalse);
      // toLocal() に任せると負のオフセットの地域で前日へ落ちるため、
      // 日付が動いていないことを明示的に確かめる
      expect(result.day, 14);
    });

    test('nullはnullのまま返す', () {
      expect(normalizeGCalDateTime(null, isAllDay: false), isNull);
      expect(normalizeGCalDateTime(null, isAllDay: true), isNull);
    });
  });

  group('allDayEndExclusive', () {
    test('1日だけの終日予定は翌日が終了になる', () {
      final result = allDayEndExclusive(
        start: DateTime(2026, 8, 14),
        lastDay: DateTime(2026, 8, 14),
      );

      expect(result, DateTime(2026, 8, 15));
    });

    test('複数日にまたがる終日予定は最終日の翌日になる', () {
      final result = allDayEndExclusive(
        start: DateTime(2026, 8, 14),
        lastDay: DateTime(2026, 8, 16),
      );

      expect(result, DateTime(2026, 8, 17));
    });

    test('最終日が開始より前でも、必ず開始の翌日以降になる', () {
      final result = allDayEndExclusive(
        start: DateTime(2026, 8, 14),
        lastDay: DateTime(2026, 8, 10),
      );

      expect(result, DateTime(2026, 8, 15));
    });

    test('時刻が混ざっていても日付だけを見る', () {
      final result = allDayEndExclusive(
        start: DateTime(2026, 8, 14, 22, 30),
        lastDay: DateTime(2026, 8, 14, 3, 15),
      );

      expect(result, DateTime(2026, 8, 15));
    });

    test('月をまたぐ最終日でも翌日が正しく出る', () {
      final result = allDayEndExclusive(
        start: DateTime(2026, 8, 30),
        lastDay: DateTime(2026, 8, 31),
      );

      expect(result, DateTime(2026, 9, 1));
    });
  });
}
