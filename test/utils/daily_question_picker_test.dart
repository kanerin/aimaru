import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/utils/daily_question_picker.dart';

void main() {
  group('pickDailyQuestion', () {
    test('同じ日付なら常に同じ質問を返す', () {
      final a = pickDailyQuestion(DateTime(2026, 8, 17));
      final b = pickDailyQuestion(DateTime(2026, 8, 17));

      expect(a, b);
      expect(dailyQuestions, contains(a));
    });

    test('日付が違えば異なる質問になりうる（隣接日で少なくとも1組は変わる）', () {
      final questions = [
        for (var d = 0; d < dailyQuestions.length; d++)
          pickDailyQuestion(DateTime(2026, 1, 1).add(Duration(days: d))),
      ];

      expect(questions.toSet().length, greaterThan(1));
    });

    test('質問数を超える日数が経っても範囲外アクセスにならない', () {
      final question = pickDailyQuestion(DateTime(2026, 8, 31));
      final later = pickDailyQuestion(DateTime(2030, 12, 31));

      expect(dailyQuestions, contains(question));
      expect(later, isNotEmpty);
    });
  });

  group('pickDailyQuestion（2026-09-30以降の重複対策）', () {
    test('切り替え前の日付は従来どおりの質問のまま（履歴が変わらない）', () {
      expect(pickDailyQuestion(DateTime(2026, 8, 17)),
          dailyQuestions[DateTime(2026, 8, 17).difference(DateTime(2026, 1, 1)).inDays % 30]);
    });

    test('切り替え後の120日間は同じ質問が出ない', () {
      final start = DateTime(2026, 9, 30);
      final questions = [
        for (var d = 0; d < 120; d++) pickDailyQuestion(start.add(Duration(days: d))),
      ];
      // 追加60問 + 全90問の周回の頭60問分は互いに異なる。
      expect(questions.take(60).toSet().length, 60);
      expect(questions.take(60).any(dailyQuestions.contains), isFalse);
    });

    test('年をまたいでも前日と同じ質問にならない', () {
      final questions = [
        for (var d = 0; d < 400; d++)
          pickDailyQuestion(DateTime(2026, 9, 30).add(Duration(days: d))),
      ];
      for (var i = 1; i < questions.length; i++) {
        expect(questions[i], isNot(questions[i - 1]));
      }
    });
  });

  group('allDailyQuestions', () {
    test('同じ質問が重複して入っていない（重複すると回答済みの質問がまた出る）', () {
      expect(allDailyQuestions.toSet().length, allDailyQuestions.length);
    });

    test('半年以上、毎日ちがう質問を出せるだけの数がある', () {
      expect(allDailyQuestions.length, greaterThanOrEqualTo(200));
    });

    test('日付から決まる質問はすべて含まれている', () {
      for (var d = 0; d < 800; d++) {
        final question = pickDailyQuestion(DateTime(2026, 1, 1).add(Duration(days: d)));
        expect(allDailyQuestions, contains(question));
      }
    });
  });

  group('pickUnaskedQuestion', () {
    final date = DateTime(2026, 10, 4);

    test('まだ何も出していなければ、日付から決まる質問を返す（古い版の相手と揃う）', () {
      expect(pickUnaskedQuestion(date, {}), pickDailyQuestion(date));
    });

    test('日付から決まる質問が出題済みなら、別の未出題の質問を返す', () {
      final preferred = pickDailyQuestion(date);

      final picked = pickUnaskedQuestion(date, {preferred: '2026-09-01'});

      expect(picked, isNot(preferred));
    });

    test('出題済みの質問は、未出題のものが残っている限り選ばない', () {
      final askedOn = <String, String>{};
      var day = DateTime(2026, 10, 4);
      // 表にある全問を、1日1問ずつ出し切るまで選び続ける。
      final total = allDailyQuestions.length;

      for (var i = 0; i < total; i++) {
        final picked = pickUnaskedQuestion(day, askedOn);
        expect(askedOn.containsKey(picked), isFalse, reason: '${i + 1}日目に出題済みの質問が出た');
        askedOn[picked] = day.toIso8601String().substring(0, 10);
        day = day.add(const Duration(days: 1));
      }

      expect(askedOn.length, total);
    });

    test('全問を出し切った後は、いちばん長く出していない質問に戻る', () {
      final all = allDailyQuestions;
      final askedOn = {for (final q in all) q: '2026-06-15'};
      final oldest = all.firstWhere((q) => q != pickDailyQuestion(date));
      askedOn[oldest] = '2026-01-01';

      expect(pickUnaskedQuestion(date, askedOn), oldest);
    });
  });

  group('questionForDateKey', () {
    test("'yyyy-MM-dd'のキーからその日の質問を復元できる", () {
      expect(questionForDateKey('2026-08-17'), pickDailyQuestion(DateTime(2026, 8, 17)));
    });

    test('解釈できないキーならnullを返す', () {
      expect(questionForDateKey('not-a-date'), isNull);
      expect(questionForDateKey(''), isNull);
    });
  });
}
