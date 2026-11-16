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

  // dailyQuestionは今日の質問としてサーバーが用意したもの。既定では
  // 「用意されていない日」（null）にして、手書きの質問が出るようにする。
  Widget wrap(
    Stream<List<QuestionAnswer>> stream, {
    Future<String?>? dailyQuestion,
    Future<void> Function(String, String)? submit,
    Stream<List<QuestionComment>>? comments,
    Future<void> Function(String dateKey, String text)? sendComment,
  }) =>
      MaterialApp(
        home: QuestionsScreen(
          coupleId: 'couple-1',
          memberIds: const [uidA, uidB],
          partnerName: 'パートナー',
          currentUidOverride: uidA,
          nowOverride: now,
          answersStreamOverride: stream,
          dailyQuestionFutureOverride: dailyQuestion ?? Future.value(null),
          submitOverride: submit,
          commentsStreamOverride: comments ?? Stream.value(const <QuestionComment>[]),
          sendCommentOverride: sendComment,
        ),
      );

  // 今日の質問の取得（Future）が済んで、回答のストリームを待つところまで進める。
  Future<void> pumpScreen(
    WidgetTester tester,
    Stream<List<QuestionAnswer>> stream, {
    Future<String?>? dailyQuestion,
  }) async {
    await tester.pumpWidget(wrap(stream, dailyQuestion: dailyQuestion));
    await tester.pump();
  }

  QuestionAnswer buildAnswer({
    required String uid,
    required String text,
    String dateKey = '2026-08-17',
    String? question,
  }) =>
      QuestionAnswer(
        id: '${dateKey}_$uid',
        coupleId: 'couple-1',
        dateKey: dateKey,
        uid: uid,
        text: text,
        createdAt: now,
        question: question,
      );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<QuestionAnswer>>();
    await pumpScreen(tester, controller.stream);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<QuestionAnswer>>();
    await pumpScreen(tester, controller.stream);

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('誰も回答していなければ質問と入力欄を表示する', (tester) async {
    final controller = StreamController<List<QuestionAnswer>>();
    await pumpScreen(tester, controller.stream);

    controller.add([]);
    await tester.pump();

    expect(find.text(pickDailyQuestion(now)), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('回答する'), findsOneWidget);

    await controller.close();
  });

  group('今日の質問', () {
    testWidgets('質問の取得中はローディング表示', (tester) async {
      final question = Completer<String?>();
      await tester.pumpWidget(wrap(const Stream.empty(), dailyQuestion: question.future));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      question.complete('2人で行きたい雪国の街は？');
      await tester.pump();
    });

    testWidgets('サーバーが用意した質問があれば、手書きの質問ではなくそれを出す', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await pumpScreen(tester, controller.stream,
          dailyQuestion: Future.value('2人で行きたい雪国の街は？'));

      controller.add([]);
      await tester.pump();

      expect(find.text('2人で行きたい雪国の街は？'), findsOneWidget);
      expect(find.text(pickDailyQuestion(now)), findsNothing);
      expect(find.byType(TextField), findsOneWidget);

      await controller.close();
    });

    testWidgets('質問を読めなかったら、相手と違う質問に答えないようエラー表示にする', (tester) async {
      final question = Completer<String?>();
      await tester.pumpWidget(wrap(const Stream.empty(), dailyQuestion: question.future));

      question.completeError(Exception('unavailable'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('読み込みに失敗'), findsOneWidget);
      expect(find.text(pickDailyQuestion(now)), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('回答の送信', () {
    testWidgets('送信に失敗したら入力を残して通知し、ボタンを押し直せる', (tester) async {
      await tester.pumpWidget(wrap(
        Stream.value(const <QuestionAnswer>[]),
        submit: (_, __) async => throw Exception('permission-denied'),
      ));
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), '水族館');
      await tester.tap(find.text('回答する'));
      await tester.pump();
      await tester.pump();

      expect(find.text('回答の送信に失敗しました。もう一度お試しください'), findsOneWidget);
      expect(find.text('水族館'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('送信に成功したら入力内容を渡す', (tester) async {
      String? sent;
      await tester.pumpWidget(wrap(
        Stream.value(const <QuestionAnswer>[]),
        submit: (text, _) async => sent = text,
      ));
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), '動物園');
      await tester.tap(find.text('回答する'));
      await tester.pump();

      expect(sent, '動物園');
      expect(find.textContaining('送信に失敗'), findsNothing);
    });
  });

  testWidgets('自分だけ回答済みならパートナーの回答は伏せて待機表示にする', (tester) async {
    final controller = StreamController<List<QuestionAnswer>>();
    await pumpScreen(tester, controller.stream);

    controller.add([buildAnswer(uid: uidA, text: '水族館に行きたい')]);
    await tester.pump();

    expect(find.text('水族館に行きたい'), findsOneWidget);
    expect(find.textContaining('パートナーが回答すると表示されます'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await controller.close();
  });

  testWidgets('両者回答済みなら両方の回答を表示する', (tester) async {
    final controller = StreamController<List<QuestionAnswer>>();
    await pumpScreen(tester, controller.stream);

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

  group('連続回答日数（ストリーク）', () {
    testWidgets('連続が途切れていても表示は消さず0日と出す', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await pumpScreen(tester, controller.stream);

      controller.add([buildAnswer(uid: uidA, text: '今日の回答')]);
      await tester.pump();

      expect(find.text('🔥 0日連続'), findsOneWidget);

      await controller.close();
    });

    testWidgets('今日を含めて2人とも連続で回答していればストリークを表示する', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await pumpScreen(tester, controller.stream);

      controller.add([
        buildAnswer(uid: uidA, dateKey: '2026-08-17', text: '今日のわたし'),
        buildAnswer(uid: uidB, dateKey: '2026-08-17', text: '今日のあいて'),
        buildAnswer(uid: uidA, dateKey: '2026-08-16', text: '昨日のわたし'),
        buildAnswer(uid: uidB, dateKey: '2026-08-16', text: '昨日のあいて'),
      ]);
      await tester.pump();

      expect(find.text('🔥 2日連続'), findsOneWidget);

      await controller.close();
    });
  });

  group('これまでの質問（過去分の閲覧）', () {
    testWidgets('過去分が無ければ履歴の見出しを出さない', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await pumpScreen(tester, controller.stream);

      controller.add([buildAnswer(uid: uidA, text: '今日の回答')]);
      await tester.pump();

      expect(find.text('これまでの質問'), findsNothing);

      await controller.close();
    });

    testWidgets('過去の日付の質問と2人の回答を新しい順に表示する', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await pumpScreen(tester, controller.stream);

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

    testWidgets('過去の質問は、回答と一緒に残した質問文を出す', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await pumpScreen(tester, controller.stream);

      controller.add([
        buildAnswer(uid: uidA, dateKey: '2026-08-16', text: '昨日のわたし', question: '昨日の質問は？'),
      ]);
      await tester.pump();

      expect(find.text('昨日の質問は？'), findsOneWidget);
      expect(find.text(questionForDateKey('2026-08-16')!), findsNothing);

      await controller.close();
    });

    testWidgets('自分が回答していない日も、相手の回答に残った質問文を出す', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await pumpScreen(tester, controller.stream);

      controller.add([
        buildAnswer(uid: uidB, dateKey: '2026-08-16', text: '相手の回答', question: '昨日の質問は？'),
      ]);
      await tester.pump();

      expect(find.text('昨日の質問は？'), findsOneWidget);

      await controller.close();
    });

    testWidgets('過去分でも自分が回答していない日は相手の回答を伏せる', (tester) async {
      final controller = StreamController<List<QuestionAnswer>>();
      await pumpScreen(tester, controller.stream);

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
      await pumpScreen(tester, controller.stream);

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

  group('回答へのコメント', () {
    QuestionComment buildComment({
      required String senderId,
      required String text,
      String dateKey = '2026-08-17',
      DateTime? createdAt,
    }) =>
        QuestionComment(
          id: '$dateKey-$text',
          coupleId: 'couple-1',
          dateKey: dateKey,
          text: text,
          senderId: senderId,
          createdAt: createdAt ?? now,
        );

    final bothAnswered = [
      buildAnswer(uid: uidA, text: '水族館に行きたい'),
      buildAnswer(uid: uidB, text: '動物園に行きたい'),
    ];

    Future<void> pumpWithComments(
      WidgetTester tester,
      List<QuestionAnswer> answers, {
      Stream<List<QuestionComment>>? comments,
      Future<void> Function(String, String)? sendComment,
    }) async {
      await tester.pumpWidget(wrap(
        Stream.value(answers),
        comments: comments,
        sendComment: sendComment,
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('2人とも回答した日は、その日のコメントを古い順に出し、入力欄を出す', (tester) async {
      await pumpWithComments(tester, bothAnswered, comments: Stream.value([
        buildComment(senderId: uidA, text: '今度行こう', createdAt: DateTime(2026, 8, 17, 21)),
        buildComment(senderId: uidB, text: 'それ意外！', createdAt: DateTime(2026, 8, 17, 20)),
        buildComment(senderId: uidA, dateKey: '2026-08-10', text: '別の日のコメント'),
      ]));

      expect(find.text('それ意外！'), findsOneWidget);
      expect(find.text('今度行こう'), findsOneWidget);
      expect(find.text('別の日のコメント'), findsNothing);
      expect(
        tester.getTopLeft(find.text('それ意外！')).dy,
        lessThan(tester.getTopLeft(find.text('今度行こう')).dy),
      );
      expect(find.textContaining('パートナー ·'), findsOneWidget);
      expect(find.textContaining('あなた ·'), findsOneWidget);
      expect(find.widgetWithText(TextField, '回答にコメント'), findsOneWidget);
    });

    testWidgets('相手がまだ回答していなければコメント欄は出さない', (tester) async {
      await pumpWithComments(tester, [buildAnswer(uid: uidA, text: '水族館に行きたい')]);

      expect(find.widgetWithText(TextField, '回答にコメント'), findsNothing);
      expect(find.text('コメントする'), findsNothing);
    });

    testWidgets('送信すると日付と本文を渡し、入力欄を空にする', (tester) async {
      String? sentDate;
      String? sentText;
      await pumpWithComments(tester, bothAnswered, sendComment: (d, t) async {
        sentDate = d;
        sentText = t;
      });

      await tester.enterText(find.widgetWithText(TextField, '回答にコメント'), '  今度行こう  ');
      await tester.tap(find.byTooltip('コメントを送信'));
      await tester.pump();

      expect(sentDate, '2026-08-17');
      expect(sentText, '今度行こう');
      expect(find.text('  今度行こう  '), findsNothing);
    });

    testWidgets('空のままでは送信しない', (tester) async {
      var called = false;
      await pumpWithComments(tester, bothAnswered, sendComment: (_, __) async => called = true);

      await tester.tap(find.byTooltip('コメントを送信'));
      await tester.pump();

      expect(called, isFalse);
    });

    testWidgets('送信に失敗したら入力を残して通知する', (tester) async {
      await pumpWithComments(tester, bothAnswered,
          sendComment: (_, __) async => throw Exception('permission-denied'));

      await tester.enterText(find.widgetWithText(TextField, '回答にコメント'), '今度行こう');
      await tester.tap(find.byTooltip('コメントを送信'));
      await tester.pump();
      await tester.pump();

      expect(find.text('コメントの送信に失敗しました。もう一度お試しください'), findsOneWidget);
      expect(find.text('今度行こう'), findsOneWidget);
    });

    testWidgets('コメントが読めなくても回答は出し、コメント欄だけでエラーを知らせる', (tester) async {
      await pumpWithComments(tester, bothAnswered,
          comments: Stream.error(Exception('PERMISSION_DENIED')));

      expect(find.text('水族館に行きたい'), findsOneWidget);
      expect(find.text('動物園に行きたい'), findsOneWidget);
      expect(find.text('コメントを読み込めませんでした'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('過去の日は「コメントする」を押すと入力欄を出し、その日付で送る', (tester) async {
      String? sentDate;
      await pumpWithComments(
        tester,
        [
          buildAnswer(uid: uidA, dateKey: '2026-08-16', text: '昨日の自分'),
          buildAnswer(uid: uidB, dateKey: '2026-08-16', text: '昨日の相手'),
        ],
        sendComment: (d, _) async => sentDate = d,
      );

      expect(find.widgetWithText(TextField, '回答にコメント'), findsNothing);
      await tester.ensureVisible(find.text('コメントする'));
      await tester.tap(find.text('コメントする'));
      await tester.pump();

      await tester.enterText(find.widgetWithText(TextField, '回答にコメント'), 'なつかしい');
      await tester.ensureVisible(find.byTooltip('コメントを送信'));
      await tester.tap(find.byTooltip('コメントを送信'));
      await tester.pump();

      expect(sentDate, '2026-08-16');
    });

    testWidgets('過去の日でも自分が回答していなければコメント欄は出さない', (tester) async {
      await pumpWithComments(tester, [
        buildAnswer(uid: uidB, dateKey: '2026-08-16', text: '昨日の相手'),
      ]);

      expect(find.text('コメントする'), findsNothing);
    });
  });
}
