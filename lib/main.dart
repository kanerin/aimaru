import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'utils/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/memories_screen.dart';
import 'screens/todos_screen.dart';
import 'services/couple_service.dart';
import 'services/deep_link_service.dart';
import 'services/firebase_bootstrap.dart';
import 'services/notification_service.dart';
import 'services/theme_controller.dart';

import 'firebase_options.dart';

final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // 結合テスト時のみローカルエミュレータへ繋ぎ替える（通常ビルドでは何もしない）
  await connectFirebaseEmulators();

  await initializeDateFormatting('ja');
  await ThemeController.instance.load();

  // ── 起動をブロックしない初期化 ────────────────────────────
  // FCMの初期化はrequestPermissionでOSの通知許可ダイアログを出し、利用者が
  // 応答するまで完了しない。これをawaitするとrunAppに到達できず、Android 13以降の
  // 初回起動で「許可を選ぶまで画面が真っ白」という状態になる。
  // ディープリンクもOS側の状態に依存するため、どちらも起動とは切り離す。
  // （結合テストでも権限ダイアログに応答できる人がいないため、awaitしていると
  // アプリが起動せず起動テストがタイムアウトする）
  //
  // 併せて例外も握りつぶす。Google Play開発者サービスが無い端末でFCMの
  // トークン取得に失敗しても、アプリ自体は起動できなければならない。
  unawaited(_initInBackground('FCM', () async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await NotificationService().init(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      router: _router,
    );
  }));
  unawaited(_initInBackground('DeepLink', () => DeepLinkService().init()));

  runApp(const ProviderScope(child: AimaruApp()));
}

// 起動と並行して進める初期化のラッパー。
// 失敗しても起動は続行し、握りつぶしたことが分かるようdebugPrintにだけ残す。
Future<void> _initInBackground(String label, Future<void> Function() body) async {
  try {
    await body();
  } catch (e, st) {
    debugPrint('[起動時初期化に失敗: $label] $e\n$st');
  }
}

// ── ルーター ──────────────────────────────────────
final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final user     = FirebaseAuth.instance.currentUser;
    final onLogin  = state.matchedLocation == '/login';

    // 未ログイン → ログイン画面
    if (user == null) return onLogin ? null : '/login';

    // ログイン済み → ペアリング確認
    if (onLogin) {
      final couple = await CoupleService().getMyCouple();
      return couple != null ? '/home' : '/pairing';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/login',   builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/pairing', builder: (_, __) => const PairingScreen()),
    GoRoute(
      path: '/home',
      builder: (_, __) => const _HomeShell(),
    ),
  ],
);

// ── アプリ本体 ────────────────────────────────────
class AimaruApp extends StatelessWidget {
  const AimaruApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => MaterialApp.router(
        title: 'AIMARU',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(ThemeController.instance.accent),
        scaffoldMessengerKey: _scaffoldMessengerKey,
        routerConfig: _router,
      ),
    );
  }
}

// ── ホームシェル（BottomNav）──────────────────────
class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;
  String? _coupleId;

  @override
  void initState() {
    super.initState();
    _loadCouple();
  }

  Future<void> _loadCouple() async {
    final couple = await CoupleService().getMyCouple();
    if (!mounted) return;
    if (couple == null) {
      // ペアがまだ無い状態でここに来た場合は迷子にならないようペアリング画面へ
      context.go('/pairing');
      return;
    }
    setState(() => _coupleId = couple.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_coupleId == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: appAccent(context))),
      );
    }

    final pages = [
      // ① カレンダー
      CalendarScreen(coupleId: _coupleId!),
      // ② AI チャット
      AiChatScreen(coupleId: _coupleId!),
      // ③ カップルチャット
      ChatScreen(coupleId: _coupleId!),
      // ④ 思い出
      MemoriesScreen(coupleId: _coupleId!),
      // ⑤ やりたいことリスト
      TodosScreen(coupleId: _coupleId!),
    ];

    return Scaffold(
      // IndexedStackで4画面すべてをマウントしたまま保持する。
      // pages[_index]のように切り替えるとタブを離れた画面は破棄され、
      // AIチャットの会話などがタブ切り替えのたびに消えてしまう。
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.navyCard,
        indicatorColor: appAccent(context).withValues(alpha: 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Text('🗓', style: TextStyle(fontSize: 20)), label: 'カレンダー'),
          NavigationDestination(icon: Text('✨', style: TextStyle(fontSize: 20)), label: 'AI'),
          NavigationDestination(icon: Text('💬', style: TextStyle(fontSize: 20)), label: 'チャット'),
          NavigationDestination(icon: Text('📸', style: TextStyle(fontSize: 20)), label: '思い出'),
          NavigationDestination(icon: Text('📝', style: TextStyle(fontSize: 20)), label: 'やりたい'),
        ],
      ),
    );
  }
}
