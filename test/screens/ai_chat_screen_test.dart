import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/screens/ai_chat_screen.dart';
import 'package:aimaru/services/gemini_service.dart';
import 'package:aimaru/services/notification_settings_service.dart';
import 'package:aimaru/services/shopping_list_service.dart';

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

  group('アプリの操作(action)の確認カード', () {
    const coupleId = 'couple-1';
    const meUid = 'user-me';

    Widget wrapAction({
      required GeminiReply reply,
      FakeFirebaseFirestore? db,
    }) {
      final firestore = db ?? FakeFirebaseFirestore();
      return MaterialApp(
        home: AiChatScreen(
          coupleId: coupleId,
          buildEventsContextOverride: () async => 'なし',
          sendMessageOverride: (message, history, {required eventsContext}) async => reply,
          notificationSettingsServiceOverride:
              NotificationSettingsService(firestore: firestore, uid: meUid),
          shoppingListServiceOverride: ShoppingListService(firestore: firestore, uid: meUid),
        ),
      );
    }

    Future<void> sendAnyMessage(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), '設定変更のお願い');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('通知をOFFにする指示は確認カードを出し、実行すると設定に反映される', (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(wrapAction(
        db: db,
        reply: GeminiReply.action(GeminiAction.toggle(GeminiActionType.notifyOnNewEvent, false)),
      ));

      await sendAnyMessage(tester);

      expect(find.text('実行する'), findsOneWidget);
      expect(find.textContaining('通知をOFFにします'), findsOneWidget);

      await tester.tap(find.text('実行する'));
      await tester.pump();

      final doc = await db.collection('users').doc(meUid).get();
      expect(doc.data()!['notifyOnNewEvent'], isFalse);
      expect(find.text('設定しました ✅'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('リマインダー分数の変更が反映される', (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(wrapAction(
        db: db,
        reply: GeminiReply.action(GeminiAction.reminderMinutes(15)),
      ));

      await sendAnyMessage(tester);
      await tester.tap(find.text('実行する'));
      await tester.pump();

      final doc = await db.collection('users').doc(meUid).get();
      expect(doc.data()!['reminderMinutesBefore'], 15);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('買い物リストへの追加指示は複数件まとめて追加される', (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(wrapAction(
        db: db,
        reply: GeminiReply.action(GeminiAction.shoppingItems(['牛乳', '卵'])),
      ));

      await sendAnyMessage(tester);

      expect(find.textContaining('牛乳・卵'), findsOneWidget);

      await tester.tap(find.text('実行する'));
      await tester.pump();

      final snap = await db
          .collection('couples')
          .doc(coupleId)
          .collection('shoppingItems')
          .get();
      expect(snap.docs.map((d) => d.data()['title']), containsAll(['牛乳', '卵']));

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('キャンセルすると何も実行されない', (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(wrapAction(
        db: db,
        reply: GeminiReply.action(GeminiAction.toggle(GeminiActionType.notifyOnNewEvent, false)),
      ));

      await sendAnyMessage(tester);
      await tester.tap(find.text('キャンセル'));
      await tester.pump();

      final doc = await db.collection('users').doc(meUid).get();
      expect(doc.exists, isFalse);
      expect(find.text('キャンセルしました。何か変更はありますか？'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
