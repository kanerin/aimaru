import 'package:flutter_test/flutter_test.dart';
import 'package:aimaru/utils/japan_holidays.dart';

void main() {
  group('JapanHolidays - 固定祝日', () {
    test('元日 (1/1)', () {
      expect(JapanHolidays.nameFor(DateTime(2026, 1, 1)), '元日');
    });

    test('建国記念の日 (2/11)', () {
      expect(JapanHolidays.nameFor(DateTime(2026, 2, 11)), '建国記念の日');
    });

    test('憲法記念日・みどりの日・こどもの日 (5/3-5/5)', () {
      expect(JapanHolidays.nameFor(DateTime(2026, 5, 3)), '憲法記念日');
      expect(JapanHolidays.nameFor(DateTime(2026, 5, 4)), 'みどりの日');
      expect(JapanHolidays.nameFor(DateTime(2026, 5, 5)), 'こどもの日');
    });

    test('山の日 (8/11)', () {
      expect(JapanHolidays.nameFor(DateTime(2026, 8, 11)), '山の日');
    });

    test('文化の日・勤労感謝の日', () {
      expect(JapanHolidays.nameFor(DateTime(2026, 11, 3)), '文化の日');
      expect(JapanHolidays.nameFor(DateTime(2026, 11, 23)), '勤労感謝の日');
    });
  });

  group('JapanHolidays - ハッピーマンデー', () {
    test('成人の日は1月の第2月曜日', () {
      final d = DateTime(2026, 1, 12); // 2026年1月の第2月曜
      expect(d.weekday, DateTime.monday);
      expect(JapanHolidays.nameFor(d), '成人の日');
    });

    test('海の日は7月の第3月曜日', () {
      final d = DateTime(2026, 7, 20);
      expect(d.weekday, DateTime.monday);
      expect(JapanHolidays.nameFor(d), '海の日');
    });

    test('敬老の日は9月の第3月曜日', () {
      final d = DateTime(2026, 9, 21);
      expect(d.weekday, DateTime.monday);
      expect(JapanHolidays.nameFor(d), '敬老の日');
    });

    test('スポーツの日は10月の第2月曜日', () {
      final d = DateTime(2026, 10, 12);
      expect(d.weekday, DateTime.monday);
      expect(JapanHolidays.nameFor(d), 'スポーツの日');
    });
  });

  group('JapanHolidays - 春分・秋分', () {
    test('2024年の春分の日は3/20、秋分の日は9/22', () {
      expect(JapanHolidays.nameFor(DateTime(2024, 3, 20)), '春分の日');
      expect(JapanHolidays.nameFor(DateTime(2024, 9, 22)), '秋分の日');
    });

    test('2026年の春分の日は3/20', () {
      expect(JapanHolidays.nameFor(DateTime(2026, 3, 20)), '春分の日');
    });
  });

  group('JapanHolidays - 振替休日', () {
    test('祝日が日曜なら翌月曜が振替休日になる', () {
      // 2027年11月23日(勤労感謝の日)は火曜のため対象外の年を避け、
      // 実際に日曜に当たる祝日を検証する: 2025年11月23日は日曜
      final holiday = DateTime(2025, 11, 23);
      expect(holiday.weekday, DateTime.sunday);
      expect(JapanHolidays.nameFor(holiday), '勤労感謝の日');

      final substitute = DateTime(2025, 11, 24);
      expect(JapanHolidays.nameFor(substitute), '振替休日');
    });
  });

  group('JapanHolidays - 非祝日', () {
    test('平日は祝日として扱わない', () {
      expect(JapanHolidays.isHoliday(DateTime(2026, 8, 12)), isFalse);
      expect(JapanHolidays.nameFor(DateTime(2026, 8, 12)), isNull);
    });
  });
}
