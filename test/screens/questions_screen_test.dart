import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/questions_screen.dart';
import 'package:aimaru/utils/daily_question_picker.dart';

// ふたりの質問画面がストリームエラーで無限ローディングのまま固まらないこと、
// 自分/相手の回答状況に応じた表示の出し分けを確かめる。
void main() {
  const uidA = 'user-a';
  const uidB = 'user-b';
  final now = DateTime(2026, 8, 17);

  Widget wrap(Stream<List<QuestionAnswer>> stream) => MaterialApp(
        home: QuestionsScreen(
          coupleId: 'couple-1',
          memberIds: const [uidA, uidB],
          partnerName: 'パートナー',
          currentUidOverride: uidA,
          nowOverride: now,
          answersStreamOverride: stream,
        ),
      );

  QuestionAnswer buildAnswer({
    required String uid,
    required String text,
    String dateKey = '2026-08-17',
  }) =>
      QuestionAnswer(
        id: '${dateKey}_$uid',
        coupleId: 'couple-1',
        dateKey: dateKey,
        uid: uid,
        text: text,
        createdAt: now,
      );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<QuestionAnswer>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<QuestionAnswer>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('誰も回答していなければ質問と入力欄を表示する', (tester) async {
    final controller = StreamController<List<QuestionAnswer>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    expect(find.text(pickDailyQuestion(now)), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('回答する'), findsOneWidget);

    await controller.close();
  });

  testWidgets('自分だけ回答済みならパートナーの回答は伏せて待機表示にする', (tester) async {
    final controller = StreamController<List<QuestionAnswer>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([buildAnswer(uid: uidA, text: '水族館に行きたい')]);
    await tester.pump();

    expect(find.text('水族館に行きたい'), findsOneWidget);
    expect(find.textContaining('パートナーが回答すると表示されます'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await controller.close();
  });

  testWidgets('両者回答済みなら両方の回答を表示する', (tester) async {
    final controller = StreamController<List<QuestionAnswer>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      buildAnswer(uid: uidA, text: '水族館に行きたい'),
      buildAnswer(uid: uidB, text: '動物園に行きたい'),
    ]);
    await tester.pump();

    expect(find.text('水族館に行きたい'), findsOneWidget);
    expect(find.text('動物園に行きたい'), findsOneWidget);
    expect(find.textContaining('回答すると表示されます'), findsNothing);

    await controller.close();
  });

  group('これまでの質問（過去分の閲覧）', () {
    testWidgets('過去分が無ければ履歴の見出しを出さない', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await tester.pumpWidget(wrap(controller.stream));

      controller.add([buildAnswer(uid: uidA, text: '今日の回答')]);
      await tester.pump();

      expect(find.text('これまでの質問'), findsNothing);

      await controller.close();
    });

    testWidgets('過去の日付の質問と2人の回答を新しい順に表示する', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await tester.pumpWidget(wrap(controller.stream));

      controller.add([
        buildAnswer(uid: uidA, dateKey: '2026-08-15', text: '一昨日のわたし'),
        buildAnswer(uid: uidB, dateKey: '2026-08-15', text: '一昨日のあいて'),
        buildAnswer(uid: uidA, dateKey: '2026-08-16', text: '昨日のわたし'),
        buildAnswer(uid: uidB, dateKey: '2026-08-16', text: '昨日のあいて'),
      ]);
      await tester.pump();

      expect(find.text('これまでの質問'), findsOneWidget);
      expect(find.text(questionForDateKey('2026-08-16')!), findsOneWidget);
      expect(find.text('昨日のわたし'), findsOneWidget);
      expect(find.text('昨日のあいて'), findsOneWidget);
      expect(find.text('一昨日のわたし'), findsOneWidget);

      // 新しい日付が先に並ぶ
      final yesterday = tester.getTopLeft(find.text('2026-08-16')).dy;
      final dayBefore = tester.getTopLeft(find.text('2026-08-15')).dy;
      expect(yesterday, lessThan(dayBefore));

      await controller.close();
    });

    testWidgets('過去分でも自分が回答していない日は相手の回答を伏せる', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await tester.pumpWidget(wrap(controller.stream));

      controller.add([
        buildAnswer(uid: uidB, dateKey: '2026-08-16', text: '見えてはいけない回答'),
      ]);
      await tester.pump();

      expect(find.text('見えてはいけない回答'), findsNothing);
      expect(find.textContaining('あなたが回答していないため伏せられています'), findsOneWidget);

      await controller.close();
    });

    testWidgets('今日の分は履歴側に重複して出さない', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await tester.pumpWidget(wrap(controller.stream));

      controller.add([
        buildAnswer(uid: uidA, text: '今日の回答'),
        buildAnswer(uid: uidA, dateKey: '2026-08-16', text: '昨日の回答'),
      ]);
      await tester.pump();

      expect(find.text('今日の回答'), findsOneWidget);
      expect(find.text('2026-08-17'), findsNothing);

      await controller.close();
    });
  });
}
