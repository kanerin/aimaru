import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/utils/question_streak.dart';

void main() {
  const uidA = 'user-a';
  const uidB = 'user-b';
  final today = DateTime(2026, 8, 17);

  QuestionAnswer answer(String uid, String dateKey) => QuestionAnswer(
        id: '${dateKey}_$uid',
        coupleId: 'couple-1',
        dateKey: dateKey,
        uid: uid,
        text: 'テキスト',
        createdAt: today,
      );

  test('回答が無ければ0', () {
    expect(computeQuestionStreak([], const [uidA, uidB], today), 0);
  });

  test('カップル未成立（メンバーが1人以下）なら常に0', () {
    final answers = [answer(uidA, '2026-08-17')];
    expect(computeQuestionStreak(answers, const [uidA], today), 0);
    expect(computeQuestionStreak(answers, const [], today), 0);
  });

  test('今日2人とも回答していれば1', () {
    final answers = [answer(uidA, '2026-08-17'), answer(uidB, '2026-08-17')];
    expect(computeQuestionStreak(answers, const [uidA, uidB], today), 1);
  });

  test('今日は片方しか回答していなくても連続していれば数える', () {
    final answers = [
      answer(uidA, '2026-08-17'),
      answer(uidA, '2026-08-16'),
      answer(uidB, '2026-08-16'),
      answer(uidA, '2026-08-15'),
      answer(uidB, '2026-08-15'),
    ];
    expect(computeQuestionStreak(answers, const [uidA, uidB], today), 2);
  });

  test('今日も昨日も2人揃っていなければ0', () {
    final answers = [answer(uidA, '2026-08-17')];
    expect(computeQuestionStreak(answers, const [uidA, uidB], today), 0);
  });

  test('間に1人しか回答していない日があると連続はそこで途切れる', () {
    final answers = [
      answer(uidA, '2026-08-17'),
      answer(uidB, '2026-08-17'),
      answer(uidA, '2026-08-16'),
      // uidBは2026-08-16に未回答 → 連続はここまで
      answer(uidA, '2026-08-15'),
      answer(uidB, '2026-08-15'),
    ];
    expect(computeQuestionStreak(answers, const [uidA, uidB], today), 1);
  });

  test('連続する日数分を正しく数える', () {
    final answers = <QuestionAnswer>[];
    for (final dateKey in ['2026-08-17', '2026-08-16', '2026-08-15', '2026-08-14']) {
      answers.add(answer(uidA, dateKey));
      answers.add(answer(uidB, dateKey));
    }
    expect(computeQuestionStreak(answers, const [uidA, uidB], today), 4);
  });
}
