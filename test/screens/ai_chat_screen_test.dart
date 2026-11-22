import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/ai_chat_screen.dart';
import 'package:aimaru/services/event_service.dart';
import 'package:aimaru/services/gemini_service.dart';
import 'package:aimaru/services/notification_settings_service.dart';
import 'package:aimaru/services/shopping_list_service.dart';

// AIチャットで、応答待ち中に次のメッセージを送れてしまう不具合を防げていることを確かめる。
//
// 送信ボタン・Enterキー・画像送信のどれにも「応答待ち中は弾く」ガードが無いと、
// 2つの呼び出しが独立に完了してしまい、片方が先に届いたあとで
// もう片方（例えばエラー応答）が遅れて出てくる。ユーザーからは
// 「何も送っていないのにエラーが届いた」ように見える。
// 書き込みが権限・通信エラーで失敗する状況を再現するフェイク。
class _ThrowingEventService extends EventService {
  _ThrowingEventService({required super.firestore, required super.uid});

  @override
  Future<AimaruEvent> addFromGemini(String coupleId, GeminiParsedEvent parsed) async {
    throw Exception('firestore unavailable');
  }
}

class _ThrowingNotificationSettingsService extends NotificationSettingsService {
  _ThrowingNotificationSettingsService({required super.firestore, required super.uid});

  @override
  Future<void> setNotifyOnNewEvent(bool value) async {
    throw Exception('firestore unavailable');
  }
}

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

  testWidgets('サジェストチップはボタンとして扱われ、タップするとその文言が送信される', (tester) async {
    String? sent;

    await tester.pumpWidget(wrap(
      sendMessageOverride: (message, history, {required eventsContext}) async {
        sent = message;
        return const GeminiReply.text('了解しました');
      },
    ));

    final chip = find.widgetWithText(ActionChip, '今週末デートしたい');
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.pump();
    await tester.pump();

    expect(sent, '今週末デートしたい');

    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('メッセージの吹き出しはスクリーンリーダーから「コピー」を実行でき、クリップボードに入る', (tester) async {
    final handle = tester.ensureSemantics();
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(wrap(
      sendMessageOverride: (message, history, {required eventsContext}) async =>
          const GeminiReply.text('了解しました'),
    ));
    await tester.enterText(find.byType(TextField), 'コピーしたい文言');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump();

    final node = tester.getSemantics(find.text('コピーしたい文言'));
    expect(
        node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);

    node.owner!.performAction(node.id, SemanticsAction.longPress);
    await tester.pump();

    expect(clipboard, 'コピーしたい文言');
    expect(find.text('コピーしました'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    handle.dispose();
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
    firstReplyCompleter
        .complete(const GeminiReply.text('エラーが発生しました。もう一度試してください。'));
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
          sendMessageOverride:
              (message, history, {required eventsContext}) async => reply,
          notificationSettingsServiceOverride:
              NotificationSettingsService(firestore: firestore, uid: meUid),
          shoppingListServiceOverride:
              ShoppingListService(firestore: firestore, uid: meUid),
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
        reply: GeminiReply.action(
            GeminiAction.toggle(GeminiActionType.notifyOnNewEvent, false)),
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
        reply: GeminiReply.action(
            GeminiAction.toggle(GeminiActionType.notifyOnNewEvent, false)),
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

  group('確認カードの書き込みに失敗したとき', () {
    const coupleId = 'couple-1';
    const meUid = 'user-me';

    setUpAll(() => initializeDateFormatting('ja'));

    Future<void> sendAnyMessage(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), 'お願い');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();
      await tester.pump();
    }

    final event = GeminiParsedEvent(
      title: '水族館デート',
      date: DateTime(2030, 5, 3, 10),
      type: EventType.plan,
    );

    testWidgets('予定の追加に失敗したら「追加しました」とは表示せず、カードを残して押し直せる', (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(MaterialApp(
        home: AiChatScreen(
          coupleId: coupleId,
          eventServiceOverride: _ThrowingEventService(firestore: db, uid: meUid),
          buildEventsContextOverride: () async => 'なし',
          sendMessageOverride: (message, history, {required eventsContext}) async =>
              GeminiReply.events([event]),
        ),
      ));

      await sendAnyMessage(tester);
      await tester.tap(find.text('追加する'));
      await tester.pump();
      await tester.pump();

      expect(find.text('予定を追加できませんでした。もう一度お試しください'), findsOneWidget);
      expect(find.textContaining('追加しました'), findsNothing);
      expect(find.text('追加する'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('まとめて追加に失敗したらカードを残して知らせる', (tester) async {
      final db = FakeFirebaseFirestore();
      final second = GeminiParsedEvent(
        title: '映画', date: DateTime(2030, 5, 4, 10), type: EventType.plan);
      await tester.pumpWidget(MaterialApp(
        home: AiChatScreen(
          coupleId: coupleId,
          eventServiceOverride: _ThrowingEventService(firestore: db, uid: meUid),
          buildEventsContextOverride: () async => 'なし',
          sendMessageOverride: (message, history, {required eventsContext}) async =>
              GeminiReply.events([event, second]),
        ),
      ));

      await sendAnyMessage(tester);
      await tester.ensureVisible(find.textContaining('件まとめて追加する'));
      await tester.pump();
      await tester.tap(find.textContaining('件まとめて追加する'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('予定を追加できませんでした'), findsOneWidget);
      expect(find.textContaining('件まとめてカレンダーに追加しました'), findsNothing);
      expect(find.textContaining('件まとめて追加する'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('設定変更の反映に失敗したら「設定しました」とは表示せず、カードを残す', (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(MaterialApp(
        home: AiChatScreen(
          coupleId: coupleId,
          notificationSettingsServiceOverride:
              _ThrowingNotificationSettingsService(firestore: db, uid: meUid),
          buildEventsContextOverride: () async => 'なし',
          sendMessageOverride: (message, history, {required eventsContext}) async =>
              GeminiReply.action(
                  GeminiAction.toggle(GeminiActionType.notifyOnNewEvent, false)),
        ),
      ));

      await sendAnyMessage(tester);
      await tester.tap(find.text('実行する'));
      await tester.pump();
      await tester.pump();

      expect(find.text('設定を反映できませんでした。もう一度お試しください'), findsOneWidget);
      expect(find.text('設定しました ✅'), findsNothing);
      expect(find.text('実行する'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });
  });
}
