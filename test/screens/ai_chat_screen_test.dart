import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/screens/ai_chat_screen.dart';
import 'package:aimaru/services/gemini_service.dart';

// AIチャットで、応答待ち中に次のメッセージを送れてしまう不具合を防げていることを確かめる。
//
// 送信ボタン・Enterキー・画像送信のどれにも「応答待ち中は弾く」ガードが無いと、
// 2つの呼び出しが独立に完了してしまい、片方が先に届いたあとで
// もう片方（例えばエラー応答）が遅れて出てくる。ユーザーからは
// 「何も送っていないのにエラーが届いた」ように見える。
void main() {
  Widget wrap({
    required Future<GeminiReply> Function(
      String message,
      List<Map<String, String>> history, {
      required String eventsContext,
    }) sendMessageOverride,
  }) =>
      MaterialApp(
        home: AiChatScreen(
          coupleId: 'couple-1',
          sendMessageOverride: sendMessageOverride,
          buildEventsContextOverride: () async => 'なし',
        ),
      );

  testWidgets('応答待ち中は送信ボタンをタップしても2回目のAI呼び出しをしない', (tester) async {
    var callCount = 0;
    final firstReplyCompleter = Completer<GeminiReply>();

    await tester.pumpWidget(wrap(
      sendMessageOverride: (message, history, {required eventsContext}) {
        callCount++;
        return firstReplyCompleter.future;
      },
    ));

    await tester.enterText(find.byType(TextField), '今週末デートしたい');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();

    expect(callCount, 1);
    expect(find.text('今週末デートしたい'), findsOneWidget);

    // 応答待ち中に同じボタンをもう一度タップしても、2回目の呼び出しは発生しない
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    expect(callCount, 1);

    firstReplyCompleter.complete(const GeminiReply.text('いいですね、日程を教えてください'));
    await tester.pump();
    await tester.pump();

    expect(find.text('いいですね、日程を教えてください'), findsOneWidget);

    // 「思考中」インジケータのドットが仕込むタイマーを掃除してからテストを終える
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('応答が届いたあとは次のメッセージを送信できる', (tester) async {
    var callCount = 0;

    await tester.pumpWidget(wrap(
      sendMessageOverride: (message, history, {required eventsContext}) async {
        callCount++;
        return const GeminiReply.text('了解しました');
      },
    ));

    await tester.enterText(find.byType(TextField), 'ひとつめ');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump();

    expect(callCount, 1);

    await tester.enterText(find.byType(TextField), 'ふたつめ');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump();

    expect(callCount, 2);
    expect(find.text('ふたつめ'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('エラー応答は最後に送ったメッセージへの返答として1件だけ表示される', (tester) async {
    final firstReplyCompleter = Completer<GeminiReply>();

    await tester.pumpWidget(wrap(
      sendMessageOverride: (message, history, {required eventsContext}) {
        if (message == 'ひとつめ') return firstReplyCompleter.future;
        return Future.value(const GeminiReply.text('了解しました'));
      },
    ));

    await tester.enterText(find.byType(TextField), 'ひとつめ');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();

    // 応答待ち中は次を送れないので、1件目の応答が遅れて届いた場合でも
    // それより後の会話として別のエラーが割り込むことはない。
    firstReplyCompleter.complete(const GeminiReply.text('エラーが発生しました。もう一度試してください。'));
    await tester.pump();
    await tester.pump();

    expect(find.text('エラーが発生しました。もう一度試してください。'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ふたつめ');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump();

    expect(find.text('了解しました'), findsOneWidget);
    // 「ふたつめ」を送った後に、1件目由来のエラーが重複して出てきたりはしない
    expect(find.text('エラーが発生しました。もう一度試してください。'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
  });
}
