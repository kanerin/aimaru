import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:aimaru/services/home_tab_requests.dart';
import 'package:aimaru/services/notification_service.dart';
import 'package:aimaru/widgets/home_tab_request_listener.dart';

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

// 本物のホーム（main.dartの_HomeShell）と同じく、HomeTabRequestListenerで
// 頼まれたタブを開き、開いているタブを文字で出す。
class _FakeHomeShell extends StatefulWidget {
  final HomeTabRequests requests;
  const _FakeHomeShell(this.requests);

  @override
  State<_FakeHomeShell> createState() => _FakeHomeShellState();
}

class _FakeHomeShellState extends State<_FakeHomeShell> {
  HomeTab _tab = HomeTab.calendar;

  @override
  Widget build(BuildContext context) => HomeTabRequestListener(
        requests: widget.requests,
        onTab: (tab) => setState(() => _tab = tab),
        child: Scaffold(body: Text('タブ: ${_tab.name}')),
      );
}

const _questionMessage = RemoteMessage(
  data: {'type': 'question', 'coupleId': 'couple-1'},
  notification: RemoteNotification(
    title: '今日の質問が届いています',
    body: '「ふたりの質問」にまだ答えていません。',
  ),
);

// 通知タップ時に開くホームのタブの振り分け。ふたりの質問の通知だけ「質問」タブを
// 開き、それ以外（予定・チャット・リマインダーなど）は従来どおりホームへ飛ぶだけ。
void main() {
  group('homeTabForNotificationData', () {
    test('ふたりの質問の通知は「質問」タブ', () {
      expect(
        homeTabForNotificationData({'type': 'question', 'coupleId': 'couple-1'}),
        HomeTab.questions,
      );
    });

    test('予定・チャット・リマインダー・記念日の通知はタブを指定しない', () {
      for (final type in ['new_event', 'new_chat_message', 'reminder', 'anniversary']) {
        expect(homeTabForNotificationData({'type': type}), isNull, reason: type);
      }
    });

    test('typeが無い・未知の通知もタブを指定しない', () {
      expect(homeTabForNotificationData({}), isNull);
      expect(homeTabForNotificationData({'type': 'unknown'}), isNull);
    });
  });

  // アプリ表示中に届いた通知のSnackBar。ふたりの質問の通知だけ、
  // 押すと質問タブへ飛ぶ「回答する」ボタンが付く。
  group('buildForegroundNotificationSnackBar', () {
    test('ふたりの質問の通知には質問タブへ飛ぶ「回答する」ボタンが付く', () {
      var opened = false;
      final snackBar = buildForegroundNotificationSnackBar(
        _questionMessage,
        onOpen: () => opened = true,
      )!;

      final action = snackBar.action!;
      expect(action.label, '回答する');
      // actionがあっても自動で閉じる（下のタブを覆い続けない）
      expect(snackBar.persist, isFalse);

      action.onPressed();
      expect(opened, isTrue);
    });

    test('質問以外の通知は文言だけでボタンは付かない', () {
      final snackBar = buildForegroundNotificationSnackBar(
        const RemoteMessage(
          data: {'type': 'new_event'},
          notification: RemoteNotification(title: '予定が追加されました', body: '映画'),
        ),
        onOpen: () => fail('呼ばれない'),
      )!;

      expect(snackBar.action, isNull);
      expect((snackBar.content as Text).data, '予定が追加されました - 映画');
    });

    test('タイトルも本文も無ければ何も出さない', () {
      expect(
        buildForegroundNotificationSnackBar(
          const RemoteMessage(data: {'type': 'question'}),
          onOpen: () {},
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
    late HomeTabRequests homeTabs;

    setUp(() {
      messages = _FakeMessages();
      messengerKey = GlobalKey<ScaffoldMessengerState>();
      homeTabs = HomeTabRequests();
      router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('ログイン'))),
          GoRoute(path: '/home', builder: (_, __) => _FakeHomeShell(homeTabs)),
          GoRoute(path: '/settings', builder: (_, __) => const Scaffold(body: Text('設定'))),
        ],
      );
    });

    tearDown(() {
      messages.foreground.close();
      messages.opened.close();
      router.dispose();
      homeTabs.dispose();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        scaffoldMessengerKey: messengerKey,
      ));
      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.text('タブ: calendar'), findsOneWidget);
    }

    testWidgets('トークン保存が終わらなくても、通知から起動したら質問タブを開く', (tester) async {
      await pumpApp(tester);
      messages.initial = () async => _questionMessage;

      // 通信待ちなどでトークン保存がいつまでも終わらない状況
      unawaited(NotificationService.forTest(
        messages: messages,
        registerDevice: () => Completer<void>().future,
        homeTabs: homeTabs,
      ).init(scaffoldMessengerKey: messengerKey, router: router));
      await tester.pumpAndSettle();

      expect(find.text('タブ: questions'), findsOneWidget);
    });

    testWidgets('トークン保存が失敗しても、通知をタップしたら質問タブを開く', (tester) async {
      await pumpApp(tester);

      await expectLater(
        NotificationService.forTest(
          messages: messages,
          registerDevice: () async => throw Exception('SERVICE_NOT_AVAILABLE'),
          homeTabs: homeTabs,
        ).init(scaffoldMessengerKey: messengerKey, router: router),
        throwsException,
      );

      messages.opened.add(_questionMessage);
      await tester.pumpAndSettle();

      expect(find.text('タブ: questions'), findsOneWidget);
    });

    testWidgets('通知からの起動の取得に失敗しても、以降のタップは質問タブを開く', (tester) async {
      await pumpApp(tester);
      messages.initial = () async => throw Exception('getInitialMessage');

      await NotificationService.forTest(
        messages: messages,
        registerDevice: () async {},
        homeTabs: homeTabs,
      ).init(scaffoldMessengerKey: messengerKey, router: router);
      await tester.pumpAndSettle();
      expect(find.text('タブ: calendar'), findsOneWidget);

      messages.opened.add(_questionMessage);
      await tester.pumpAndSettle();

      expect(find.text('タブ: questions'), findsOneWidget);
    });

    testWidgets('アプリ表示中に届いた質問の通知は「回答する」から質問タブを開く', (tester) async {
      await pumpApp(tester);
      await NotificationService.forTest(
        messages: messages,
        registerDevice: () async {},
        homeTabs: homeTabs,
      ).init(scaffoldMessengerKey: messengerKey, router: router);

      messages.foreground.add(_questionMessage);
      await tester.pumpAndSettle();

      expect(find.textContaining('今日の質問が届いています'), findsOneWidget);
      expect(find.text('タブ: calendar'), findsOneWidget);

      await tester.tap(find.text('回答する'));
      await tester.pumpAndSettle();

      expect(find.text('タブ: questions'), findsOneWidget);
    });

    testWidgets('ログイン確認中（ホーム表示前）に通知から起動しても、ホームが出たら質問タブを開く', (tester) async {
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        scaffoldMessengerKey: messengerKey,
      ));
      await tester.pumpAndSettle();
      expect(find.text('ログイン'), findsOneWidget);

      messages.initial = () async => _questionMessage;
      await NotificationService.forTest(
        messages: messages,
        registerDevice: () async {},
        homeTabs: homeTabs,
      ).init(scaffoldMessengerKey: messengerKey, router: router);
      await tester.pumpAndSettle();

      expect(find.text('タブ: questions'), findsOneWidget);
    });

    testWidgets('ホームの上に別の画面を開いていても、質問の通知をタップしたら質問タブまで戻る', (tester) async {
      await pumpApp(tester);
      await NotificationService.forTest(
        messages: messages,
        registerDevice: () async {},
        homeTabs: homeTabs,
      ).init(scaffoldMessengerKey: messengerKey, router: router);

      router.push('/settings');
      await tester.pumpAndSettle();
      expect(find.text('設定'), findsOneWidget);

      messages.opened.add(_questionMessage);
      await tester.pumpAndSettle();

      expect(find.text('設定'), findsNothing);
      expect(find.text('タブ: questions'), findsOneWidget);
    });

    testWidgets('質問以外の通知をタップしてもタブは変わらない', (tester) async {
      await pumpApp(tester);
      await NotificationService.forTest(
        messages: messages,
        registerDevice: () async {},
        homeTabs: homeTabs,
      ).init(scaffoldMessengerKey: messengerKey, router: router);

      messages.opened.add(const RemoteMessage(data: {'type': 'new_chat_message'}));
      await tester.pumpAndSettle();

      expect(find.text('タブ: calendar'), findsOneWidget);
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
        homeTabs: HomeTabRequests(),
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
