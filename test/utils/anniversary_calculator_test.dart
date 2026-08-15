import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/utils/anniversary_calculator.dart';

// 記念日からの経過日数・次の節目（100日ごと）・次の周年までの日数計算。
// TimeTreeなど汎用カレンダーには無い、カップル向けアプリ特有の指標。
void main() {
  group('daysTogether', () {
    test('記念日当日は1日目', () {
      expect(daysTogether(DateTime(2026, 1, 1), DateTime(2026, 1, 1)), 1);
    });

    test('翌日は2日目', () {
      expect(daysTogether(DateTime(2026, 1, 1), DateTime(2026, 1, 2)), 2);
    });

    test('100日後は100日目', () {
      expect(daysTogether(DateTime(2026, 1, 1), DateTime(2026, 4, 10)), 100);
    });

    test('時刻部分は無視して日付だけで数える', () {
      expect(
        daysTogether(DateTime(2026, 1, 1, 23, 30), DateTime(2026, 1, 2, 0, 30)),
        2,
      );
    });

    test('記念日が未来の場合は0', () {
      expect(daysTogether(DateTime(2026, 5, 1), DateTime(2026, 1, 1)), 0);
    });
  });

  group('summarizeAnniversary（100日ごとの節目）', () {
    test('99日目 → 100日記念日まであと1日', () {
      final s = summarizeAnniversary(DateTime(2026, 1, 1), DateTime(2026, 4, 9));
      expect(s.daysTogether, 99);
      expect(s.nextMilestoneDay, 100);
      expect(s.daysUntilNextMilestone, 1);
    });

    test('ちょうど100日目 → 今日が節目（あと0日）', () {
      final s = summarizeAnniversary(DateTime(2026, 1, 1), DateTime(2026, 4, 10));
      expect(s.daysTogether, 100);
      expect(s.nextMilestoneDay, 100);
      expect(s.daysUntilNextMilestone, 0);
    });

    test('101日目 → 次は200日記念日', () {
      final s = summarizeAnniversary(DateTime(2026, 1, 1), DateTime(2026, 4, 11));
      expect(s.daysTogether, 101);
      expect(s.nextMilestoneDay, 200);
      expect(s.daysUntilNextMilestone, 99);
    });
  });

  group('summarizeAnniversary（周年）', () {
    test('付き合って半年（今年の月日はまだ来ていない） → 1周年', () {
      // 2026-01-01開始、今日は2026-08-15。今年の記念日(2026-01-01)は既に過ぎているので次は2027年。
      final s = summarizeAnniversary(DateTime(2026, 1, 1), DateTime(2026, 8, 15));
      expect(s.nextAnniversaryYearCount, 1);
      expect(s.nextAnniversaryDate, DateTime(2027, 1, 1));
      expect(s.daysUntilNextAnniversary, DateTime(2027, 1, 1).difference(DateTime(2026, 8, 15)).inDays);
    });

    test('記念日を設定したその日 → 1周年まで', () {
      final s = summarizeAnniversary(DateTime(2026, 8, 15), DateTime(2026, 8, 15));
      expect(s.nextAnniversaryYearCount, 1);
      expect(s.nextAnniversaryDate, DateTime(2027, 8, 15));
    });

    test('1年前の記念日で、今日がちょうど1周年 → あと0日', () {
      final s = summarizeAnniversary(DateTime(2025, 8, 15), DateTime(2026, 8, 15));
      expect(s.nextAnniversaryYearCount, 1);
      expect(s.daysUntilNextAnniversary, 0);
    });

    test('3周年を迎えた当日から1日進むと、次は4周年', () {
      final s = summarizeAnniversary(DateTime(2023, 8, 15), DateTime(2026, 8, 16));
      expect(s.nextAnniversaryYearCount, 4);
      expect(s.nextAnniversaryDate, DateTime(2027, 8, 15));
    });

    test('うるう年2/29の記念日は、平年では2/28扱いになる', () {
      // 2024-02-29開始。2026年は平年なので2/28に落ちる。
      final s = summarizeAnniversary(DateTime(2024, 2, 29), DateTime(2026, 1, 1));
      expect(s.nextAnniversaryDate, DateTime(2026, 2, 28));
    });
  });
}
