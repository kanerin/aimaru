import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'home_tab_requests.dart';

// バックグラウンド/終了時にFCMメッセージを受信したときのトップレベルハンドラ。
// 通知ペイロード付きメッセージはOSが自動でシステムトレイに表示するため、
// ここでは特別な処理は不要（アプリのisolateが別なのでトップレベル関数が必須）。
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

// 通知タップ時に開くホームのタブ。ペイロードの`type`が"question"（ふたりの質問の
// 未回答リマインダー、functions/src/index.tsのsendDailyQuestionReminder）なら
// 「質問」タブ、それ以外は開いていたタブのまま（null）。予定・チャットなどは
// 従来どおりホームへ飛ばすだけ。
// 以前は`/home/questions`という別画面をホームの上に積んでいたが、下部ナビに
// 「質問」タブができてからは同じ画面が二重にある状態になっていた。
// 通知から起動したときはログイン確認（`/login`→`/home`のリダイレクト）や
// ペア情報の読み込みと重なるため、タブの切り替えはHomeTabRequestsに保留し、
// ホームが表示された時点で反映させる。
HomeTab? homeTabForNotificationData(Map<String, dynamic> data) {
  switch (data['type']) {
    case 'question':
      return HomeTab.questions;
    default:
      return null;
  }
}

// アプリを開いている最中に届いた通知の表示。フォアグラウンドではFCMが
// システムの通知を出さないため、このSnackBarが利用者にとっての「通知」になる。
// ふたりの質問の通知には「回答する」ボタンを付け、通知をタップしたときと
// 同じ質問タブへ飛べるようにする。タイトルも本文も無ければ何も出さない（null）。
SnackBar? buildForegroundNotificationSnackBar(
  RemoteMessage message, {
  required VoidCallback onOpen,
}) {
  final title = message.notification?.title;
  final body  = message.notification?.body;
  final text  = [title, body].where((s) => s != null && s.isNotEmpty).join(' - ');
  if (text.isEmpty) return null;

  final action = homeTabForNotificationData(message.data) == HomeTab.questions
      ? SnackBarAction(label: '回答する', onPressed: onOpen)
      : null;

  return SnackBar(
    content: Text(text),
    action: action,
    behavior: SnackBarBehavior.floating,
    // actionがあるとSnackBarは既定で閉じなくなり、下のタブを覆い続けるため、
    // 押す時間だけ少し長めに残して自動で閉じる。
    persist: false,
    duration: Duration(seconds: action == null ? 4 : 6),
  );
}

// FCMのうち、通知の受信とタップの受け取りに使う部分。firebase_messagingは
// プラットフォームチャネル越しの呼び出しで単体テストから実行できないため、
// テストからは差し替えられるようにしてある。
abstract class NotificationMessages {
  Stream<RemoteMessage> get onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp;
  Future<RemoteMessage?> getInitialMessage();
}

class _FirebaseNotificationMessages implements NotificationMessages {
  const _FirebaseNotificationMessages();

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() => FirebaseMessaging.instance.getInitialMessage();
}

// ── FCMのトークン保存・フォアグラウンド通知表示・タップ遷移を担当 ──
class NotificationService {
  static final NotificationService _instance =
      NotificationService._(const _FirebaseNotificationMessages(), null, HomeTabRequests.instance);
  factory NotificationService() => _instance;
  NotificationService._(this._messages, this._registerDeviceOverride, this._homeTabs);

  // テストからFCM・Firestoreに触れずに初期化を検証するための生成口。
  // registerDeviceは通知許可の要求とFCMトークンの保存（本番は_registerDevice）の代わり。
  @visibleForTesting
  NotificationService.forTest({
    required NotificationMessages messages,
    required Future<void> Function() registerDevice,
    required HomeTabRequests homeTabs,
  }) : this._(messages, registerDevice, homeTabs);

  final NotificationMessages _messages;
  final Future<void> Function()? _registerDeviceOverride;
  final HomeTabRequests _homeTabs;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  FirebaseFirestore get _db        => FirebaseFirestore.instance;
  FirebaseAuth get _auth           => FirebaseAuth.instance;

  GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;
  GoRouter? _router;

  Future<void> init({
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
    required GoRouter router,
  }) async {
    _scaffoldMessengerKey = scaffoldMessengerKey;
    _router = router;

    // 通知タップの受け口は、通知許可の要求やトークン保存より先に用意する。
    // 以前はそれらの後ろで登録していたため、トークン取得やFirestoreへの
    // 書き込みが失敗するとinitごと中断して、通知をタップしても何も起きなく
    // なっていた。成功する場合も書き込みが終わるまでタップが拾われず
    // （onMessageOpenedAppはbroadcastなので、購読前のタップは捨てられる）、
    // 通知から起動したときの質問画面への遷移も遅れていた。
    _messages.onMessage.listen(_onForegroundMessage);
    _messages.onMessageOpenedApp.listen(_onMessageTap);
    try {
      final initialMessage = await _messages.getInitialMessage();
      if (initialMessage != null) _onMessageTap(initialMessage);
    } catch (e, st) {
      debugPrint('[通知からの起動の取得に失敗] $e\n$st');
    }

    await (_registerDeviceOverride ?? _registerDevice)();
  }

  // 通知許可の要求とFCMトークンの保存。失敗してもタップの遷移には影響しない。
  Future<void> _registerDevice() => registerDeviceWith(
        requestPermission: () =>
            _messaging.requestPermission(alert: true, badge: true, sound: true),
        getToken: _messaging.getToken,
        onTokenRefresh: _messaging.onTokenRefresh,
        loggedIn: _auth.authStateChanges().map((user) => user != null),
        saveToken: _saveToken,
      );

  // トークン保存の購読（トークン更新・ログイン検知）を、getTokenの失敗に巻き込まれずに張る。
  // iOSはAPNsトークンが届くまでgetTokenが例外になることがあり、以前は
  // その例外でこの関数ごと中断して購読が一つも張られず、後からAPNsトークンが
  // 届いて`onTokenRefresh`が発火しても、ログインしても、トークンが保存されなかった。
  // 各経路の失敗はdebugPrintに残し、他の経路は止めない。
  // loggedIn（authStateChanges）は購読した時点の状態もすぐ流すため、ログイン済みの初回保存も兼ねる。
  @visibleForTesting
  Future<void> registerDeviceWith({
    required Future<void> Function() requestPermission,
    required Future<String?> Function() getToken,
    required Stream<String> onTokenRefresh,
    required Stream<bool> loggedIn,
    required Future<void> Function(String token) saveToken,
  }) async {
    onTokenRefresh.listen((token) async {
      try {
        await saveToken(token);
      } catch (e, st) {
        debugPrint('[FCMトークン更新の保存に失敗] $e\n$st');
      }
    });

    try {
      await requestPermission();
    } catch (e, st) {
      debugPrint('[通知許可の要求に失敗] $e\n$st');
    }

    loggedIn.listen((isLoggedIn) async {
      if (!isLoggedIn) return;
      try {
        final token = await getToken();
        if (token != null) await saveToken(token);
      } catch (e, st) {
        debugPrint('[FCMトークンの保存に失敗] $e\n$st');
      }
    });
  }

  Future<void> _saveToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  }

  void _onForegroundMessage(RemoteMessage message) {
    final snackBar = buildForegroundNotificationSnackBar(
      message,
      onOpen: () => _openFromNotification(message),
    );
    if (snackBar == null) return;
    _scaffoldMessengerKey?.currentState?.showSnackBar(snackBar);
  }

  void _onMessageTap(RemoteMessage message) => _openFromNotification(message);

  // 予定詳細への直接遷移は今後の拡張。質問の通知は「質問」タブ、それ以外は
  // ホーム（開いていたタブ）へ。タブの依頼は先に出しておき、ホームが
  // まだ表示されていなくても表示された時点で反映されるようにする。
  void _openFromNotification(RemoteMessage message) {
    final tab = homeTabForNotificationData(message.data);
    if (tab != null) _homeTabs.request(tab);
    _router?.go('/home');
  }
}
