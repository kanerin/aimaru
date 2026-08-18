import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/utils/next_meeting_calculator.dart';

// 次に会う予定の日までの日数計算。
// TimeTreeなど汎用カレンダーには無い、カップル向けアプリ特有の指標。
void main() {
  group('daysUntilNextMeeting', () {
    test('未来の日付は正の日数', () {
      expect(daysUntilNextMeeting(DateTime(2026, 1, 10), DateTime(2026, 1, 1)), 9);
    });

    test('当日は0', () {
      expect(daysUntilNextMeeting(DateTime(2026, 1, 1), DateTime(2026, 1, 1)), 0);
    });

    test('過ぎた日付は負の日数', () {
      expect(daysUntilNextMeeting(DateTime(2026, 1, 1), DateTime(2026, 1, 10)), -9);
    });

    test('時刻部分は無視して日付だけで数える', () {
      expect(
        daysUntilNextMeeting(DateTime(2026, 1, 2, 0, 30), DateTime(2026, 1, 1, 23, 30)),
        1,
      );
    });
  });
}
