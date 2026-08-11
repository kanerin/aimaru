import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// バックグラウンド/終了時にFCMメッセージを受信したときのトップレベルハンドラ。
// 通知ペイロード付きメッセージはOSが自動でシステムトレイに表示するため、
// ここでは特別な処理は不要（アプリのisolateが別なのでトップレベル関数が必須）。
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

// ── FCMのトークン保存・フォアグラウンド通知表示・タップ遷移を担当 ──
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _db        = FirebaseFirestore.instance;
  final _auth      = FirebaseAuth.instance;

  GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;
  GoRouter? _router;

  Future<void> init({
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
    required GoRouter router,
  }) async {
    _scaffoldMessengerKey = scaffoldMessengerKey;
    _router = router;

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // ログイン済みならすぐに、未ログインなら認証状態が変わるたびにトークンを保存
    await _saveTokenIfLoggedIn();
    _auth.authStateChanges().listen((user) {
      if (user != null) _saveTokenIfLoggedIn();
    });
    _messaging.onTokenRefresh.listen(_saveToken);

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTap);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _onMessageTap(initialMessage);
  }

  Future<void> _saveTokenIfLoggedIn() async {
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(token);
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
    final title = message.notification?.title;
    final body  = message.notification?.body;
    final text  = [title, body].where((s) => s != null && s.isNotEmpty).join(' - ');
    if (text.isEmpty) return;

    _scaffoldMessengerKey?.currentState?.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _onMessageTap(RemoteMessage message) {
    // 予定詳細への直接遷移は今後の拡張。まずはカレンダー画面へ。
    _router?.go('/home');
  }
}
