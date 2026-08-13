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
import 'services/notification_service.dart';
import 'services/theme_controller.dart';

import 'firebase_options.dart';

final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await initializeDateFormatting('ja');
  await DeepLinkService().init();
  await ThemeController.instance.load();
  await NotificationService().init(
    scaffoldMessengerKey: _scaffoldMessengerKey,
    router: _router,
  );
  runApp(const ProviderScope(child: AimaruApp()));
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
