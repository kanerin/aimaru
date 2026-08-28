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
      final question = pickDailyQuestion(DateTime(2026, 12, 31));

      expect(dailyQuestions, contains(question));
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
