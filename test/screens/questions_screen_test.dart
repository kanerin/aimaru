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

  QuestionAnswer buildAnswer({required String uid, required String text}) => QuestionAnswer(
        id: '2026-08-17_$uid',
        coupleId: 'couple-1',
        dateKey: '2026-08-17',
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
}
