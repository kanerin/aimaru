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

  group('JapanHolidays - 国民の休日', () {
    // 祝日法第3条第3項。前日と翌日が「国民の祝日」である平日は休日になる。
    // 実際に起きるのは敬老の日（9月第3月曜）と秋分の日が1日空く年だけ。
    test('敬老の日と秋分の日に挟まれた平日は国民の休日になる（2026年）', () {
      expect(JapanHolidays.nameFor(DateTime(2026, 9, 21)), '敬老の日');
      expect(JapanHolidays.nameFor(DateTime(2026, 9, 22)), '国民の休日');
      expect(JapanHolidays.nameFor(DateTime(2026, 9, 23)), '秋分の日');
    });

    test('過去の該当年でも同じように休日になる（2015年）', () {
      expect(JapanHolidays.nameFor(DateTime(2015, 9, 22)), '国民の休日');
    });

    test('敬老の日と秋分の日が離れている年は発生しない（2025年）', () {
      expect(JapanHolidays.nameFor(DateTime(2025, 9, 15)), '敬老の日');
      expect(JapanHolidays.nameFor(DateTime(2025, 9, 23)), '秋分の日');
      expect(JapanHolidays.isHoliday(DateTime(2025, 9, 22)), isFalse);
    });

    // 5/3〜5/5は真ん中も祝日なので、名前がみどりの日から変わってはいけない。
    test('祝日が3日続く5/3〜5/5は名前が変わらない', () {
      expect(JapanHolidays.nameFor(DateTime(2026, 5, 3)), '憲法記念日');
      expect(JapanHolidays.nameFor(DateTime(2026, 5, 4)), 'みどりの日');
      expect(JapanHolidays.nameFor(DateTime(2026, 5, 5)), 'こどもの日');
    });

    // 国民の休日・振替休日は「国民の祝日」ではないので、これらを起点に
    // さらに挟まれ判定をしてはいけない（休日が芋づる式に増える）。
    test('国民の休日を起点に休日が連鎖しない', () {
      // 2026年9月の休日は21・22・23の3日だけ
      final september = [
        for (var d = 1; d <= 30; d++) DateTime(2026, 9, d),
      ].where(JapanHolidays.isHoliday).map((d) => d.day).toList();

      expect(september, [21, 22, 23]);
    });

    test('振替休日の翌日が祝日でも国民の休日を増やさない（2026年5月）', () {
      expect(JapanHolidays.nameFor(DateTime(2026, 5, 6)), '振替休日');
      expect(JapanHolidays.isHoliday(DateTime(2026, 5, 7)), isFalse);
    });
  });

  group('JapanHolidays - 非祝日', () {
    test('平日は祝日として扱わない', () {
      expect(JapanHolidays.isHoliday(DateTime(2026, 8, 12)), isFalse);
      expect(JapanHolidays.nameFor(DateTime(2026, 8, 12)), isNull);
    });
  });
}
