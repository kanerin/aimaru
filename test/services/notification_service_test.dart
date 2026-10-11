import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:aimaru/services/notification_service.dart';

// FCMの代わりに、テストから通知の受信・タップ・通知からの起動を流し込む。
class _FakeMessages implements NotificationMessages {
  final foreground = StreamController<RemoteMessage>.broadcast();
  final opened = StreamController<RemoteMessage>.broadcast();
  Future<RemoteMessage?> Function() initial = () async => null;

  @override
  Stream<RemoteMessage> get onMessage => foreground.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => opened.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() => initial();
}

const _questionMessage = RemoteMessage(
  data: {'type': 'question', 'coupleId': 'couple-1'},
  notification: RemoteNotification(
    title: '今日の質問が届いています',
    body: '「ふたりの質問」にまだ答えていません。',
  ),
);

// 通知タップ時の遷移先の振り分け。ふたりの質問の通知だけ質問画面へ飛び、
// それ以外（予定・チャット・リマインダーなど）は従来どおりホームへ飛ぶ。
void main() {
  group('routeForNotificationData', () {
    test('ふたりの質問の通知は質問画面へ', () {
      expect(
        routeForNotificationData({'type': 'question', 'coupleId': 'couple-1'}),
        '/home/questions',
      );
    });

    test('予定・チャット・リマインダー・記念日の通知はホームへ', () {
      for (final type in ['new_event', 'new_chat_message', 'reminder', 'anniversary']) {
        expect(routeForNotificationData({'type': type}), '/home', reason: type);
      }
    });

    test('typeが無い・未知の通知もホームへ', () {
      expect(routeForNotificationData({}), '/home');
      expect(routeForNotificationData({'type': 'unknown'}), '/home');
    });
  });

  // アプリ表示中に届いた通知のSnackBar。ふたりの質問の通知だけ、
  // 押すと質問画面へ飛ぶ「回答する」ボタンが付く。
  group('buildForegroundNotificationSnackBar', () {
    test('ふたりの質問の通知には質問画面へ飛ぶ「回答する」ボタンが付く', () {
      String? opened;
      final snackBar = buildForegroundNotificationSnackBar(
        _questionMessage,
        onOpen: (route) => opened = route,
      )!;

      final action = snackBar.action!;
      expect(action.label, '回答する');
      // actionがあっても自動で閉じる（下のタブを覆い続けない）
      expect(snackBar.persist, isFalse);

      action.onPressed();
      expect(opened, '/home/questions');
    });

    test('質問以外の通知は文言だけでボタンは付かない', () {
      final snackBar = buildForegroundNotificationSnackBar(
        const RemoteMessage(
          data: {'type': 'new_event'},
          notification: RemoteNotification(title: '予定が追加されました', body: '映画'),
        ),
        onOpen: (_) => fail('呼ばれない'),
      )!;

      expect(snackBar.action, isNull);
      expect((snackBar.content as Text).data, '予定が追加されました - 映画');
    });

    test('タイトルも本文も無ければ何も出さない', () {
      expect(
        buildForegroundNotificationSnackBar(
          const RemoteMessage(data: {'type': 'question'}),
          onOpen: (_) {},
        ),
        isNull,
      );
    });
  });

  // 通知タップの受け口は、通知許可の要求・トークン保存（registerDevice）より
  // 先に用意される。以前はその後ろで登録していたため、トークン保存が失敗すると
  // タップしても何も起きず、終わるまでは通知から起動しても遷移しなかった。
  group('NotificationService.init', () {
    late _FakeMessages messages;
    late GoRouter router;
    late GlobalKey<ScaffoldMessengerState> messengerKey;

    setUp(() {
      messages = _FakeMessages();
      messengerKey = GlobalKey<ScaffoldMessengerState>();
      router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('ホーム')),
            routes: [
              GoRoute(
                path: 'questions',
                builder: (_, __) => const Scaffold(body: Text('質問画面')),
              ),
            ],
          ),
        ],
      );
    });

    tearDown(() {
      messages.foreground.close();
      messages.opened.close();
      router.dispose();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        scaffoldMessengerKey: messengerKey,
      ));
      await tester.pumpAndSettle();
      expect(find.text('ホーム'), findsOneWidget);
    }

    testWidgets('トークン保存が終わらなくても、通知から起動したら質問画面へ遷移する', (tester) async {
      await pumpApp(tester);
      messages.initial = () async => _questionMessage;

      // 通信待ちなどでトークン保存がいつまでも終わらない状況
      unawaited(NotificationService.forTest(
        messages: messages,
        registerDevice: () => Completer<void>().future,
      ).init(scaffoldMessengerKey: messengerKey, router: router));
      await tester.pumpAndSettle();

      expect(find.text('質問画面'), findsOneWidget);
    });

    testWidgets('トークン保存が失敗しても、通知をタップしたら質問画面へ遷移する', (tester) async {
      await pumpApp(tester);

      await expectLater(
        NotificationService.forTest(
          messages: messages,
          registerDevice: () async => throw Exception('SERVICE_NOT_AVAILABLE'),
        ).init(scaffoldMessengerKey: messengerKey, router: router),
        throwsException,
      );

      messages.opened.add(_questionMessage);
      await tester.pumpAndSettle();

      expect(find.text('質問画面'), findsOneWidget);
    });

    testWidgets('通知からの起動の取得に失敗しても、以降のタップは質問画面へ遷移する', (tester) async {
      await pumpApp(tester);
      messages.initial = () async => throw Exception('getInitialMessage');

      await NotificationService.forTest(
        messages: messages,
        registerDevice: () async {},
      ).init(scaffoldMessengerKey: messengerKey, router: router);
      await tester.pumpAndSettle();
      expect(find.text('ホーム'), findsOneWidget);

      messages.opened.add(_questionMessage);
      await tester.pumpAndSettle();

      expect(find.text('質問画面'), findsOneWidget);
    });

    testWidgets('アプリ表示中に届いた質問の通知は「回答する」から質問画面へ遷移する', (tester) async {
      await pumpApp(tester);
      await NotificationService.forTest(
        messages: messages,
        registerDevice: () async {},
      ).init(scaffoldMessengerKey: messengerKey, router: router);

      messages.foreground.add(_questionMessage);
      await tester.pumpAndSettle();

      expect(find.textContaining('今日の質問が届いています'), findsOneWidget);
      expect(find.text('ホーム'), findsOneWidget);

      await tester.tap(find.text('回答する'));
      await tester.pumpAndSettle();

      expect(find.text('質問画面'), findsOneWidget);
    });
  });

  // iOSはAPNsトークンが届くまでgetTokenが例外になることがある。以前はその例外で
  // 登録処理ごと中断し、onTokenRefreshもログイン検知も購読されなかった。
  group('NotificationService.registerDeviceWith', () {
    late StreamController<String> refresh;
    late StreamController<bool> loggedIn;
    late List<String> saved;
    late NotificationService service;

    setUp(() {
      refresh = StreamController<String>.broadcast();
      loggedIn = StreamController<bool>.broadcast();
      saved = [];
      service = NotificationService.forTest(
        messages: _FakeMessages(),
        registerDevice: () async {},
      );
    });

    tearDown(() {
      refresh.close();
      loggedIn.close();
    });

    Future<void> register({
      Future<void> Function()? requestPermission,
      required Future<String?> Function() getToken,
      Future<void> Function(String)? saveToken,
    }) =>
        service.registerDeviceWith(
          requestPermission: requestPermission ?? () async {},
          getToken: getToken,
          onTokenRefresh: refresh.stream,
          loggedIn: loggedIn.stream,
          saveToken: saveToken ?? (t) async => saved.add(t),
        );

    test('ログインしたらトークンを保存し、ログアウト状態では保存しない', () async {
      await register(getToken: () async => 'token-1');

      loggedIn.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(saved, isEmpty);

      loggedIn.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(saved, ['token-1']);
    });

    test('getTokenが失敗しても例外は漏れず、後のonTokenRefreshでトークンが保存される', () async {
      await register(getToken: () async => throw Exception('apns-token-not-set'));

      loggedIn.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(saved, isEmpty);

      refresh.add('token-from-refresh');
      await Future<void>.delayed(Duration.zero);
      expect(saved, ['token-from-refresh']);
    });

    test('通知許可の要求が失敗しても、ログイン検知とトークン更新は購読される', () async {
      await register(
        requestPermission: () async => throw Exception('denied'),
        getToken: () async => 'token-2',
      );

      loggedIn.add(true);
      refresh.add('token-3');
      await Future<void>.delayed(Duration.zero);
      expect(saved, containsAll(['token-2', 'token-3']));
    });

    test('保存（Firestore書き込み）が失敗しても例外は漏れず、次のトークン更新は保存される', () async {
      var fail = true;
      await register(
        getToken: () async => 'token-4',
        saveToken: (t) async {
          if (fail) throw Exception('PERMISSION_DENIED');
          saved.add(t);
        },
      );

      loggedIn.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(saved, isEmpty);

      fail = false;
      refresh.add('token-5');
      await Future<void>.delayed(Duration.zero);
      expect(saved, ['token-5']);
    });
  });
}
