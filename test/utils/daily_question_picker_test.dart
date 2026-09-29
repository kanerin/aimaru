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
