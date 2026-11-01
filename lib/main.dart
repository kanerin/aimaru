import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'utils/app_theme.dart';
import 'screens/app_lock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/questions_route_screen.dart';
import 'screens/anniversary_hub_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/chat_pager_screen.dart';
import 'services/app_lock_controller.dart';
import 'services/couple_service.dart';
import 'services/deep_link_service.dart';
import 'services/firebase_bootstrap.dart';
import 'services/home_tab_requests.dart';
import 'services/notification_service.dart';
import 'services/theme_controller.dart';
import 'widgets/couple_loader.dart';
import 'widgets/daily_refresh.dart';
import 'widgets/home_tab_request_listener.dart';

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
  await AppLockController.instance.load();

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
      try {
        final couple = await CoupleService().getMyCouple();
        return couple != null ? '/home' : '/pairing';
      } catch (e, st) {
        // 読み込み失敗でリダイレクトごと例外にしない。ログイン済みなので
        // /homeへ進め、そちら（CoupleLoader）が再読み込みを出す。
        debugPrint('[ペア確認に失敗: $e]\n$st');
        return '/home';
      }
    }
    return null;
  },
  routes: [
    GoRoute(path: '/login',   builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/pairing', builder: (_, __) => const PairingScreen()),
    // ふたりの質問の通知タップは`/home`へ飛び、HomeTabRequestsで「質問」タブを開く
    // （NotificationService）。
    GoRoute(path: '/home', builder: (_, __) => const _HomeShell()),
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
        // 日付・時刻ピッカーのようにFlutterが用意しているダイアログは、
        // ここでlocalizationsDelegatesを渡さないと英語（DefaultMaterialLocalizations）
        // のままになる。画面の文言だけ日本語で「Select date / Cancel / OK」が
        // 混ざって出ていたのはこれが原因。
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: _router,
        builder: (context, child) => _AppLockGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

// ── アプリロックのゲート ──────────────────────────
// バックグラウンドへ回るたびAppLockController.lock()でロックし、有効化されて
// いれば次に前面に戻ったときAppLockScreenでパスコードを要求する。ルーティング
// より外側（MaterialApp.routerのbuilder）で画面全体を差し替えるため、
// ログイン画面・カレンダーなどどの画面にいてもロック対象になる。
class _AppLockGate extends StatefulWidget {
  final Widget child;
  const _AppLockGate({required this.child});

  @override
  State<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<_AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      AppLockController.instance.lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLockController.instance,
      builder: (context, _) {
        return AppLockController.instance.locked ? const AppLockScreen() : widget.child;
      },
    );
  }
}

// ── ホームシェル（BottomNav）──────────────────────
class _HomeShell extends StatelessWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context) {
    // ペア情報の読み込み失敗は無限ローディングにせず、再読み込みを出す。
    // ペアがまだ無い状態でここに来た場合は迷子にならないようペアリング画面へ。
    return CoupleLoader(
      onNoCouple: () => context.go('/pairing'),
      builder: (_, coupleId) => _HomeContent(coupleId: coupleId),
    );
  }
}

class _HomeContent extends StatefulWidget {
  final String coupleId;
  const _HomeContent({required this.coupleId});

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  int _index = 0;
  // チャットタブで2人のトーク（1枚目）を開くよう頼んだ回数。増えるたびに
  // ChatPagerScreenが1枚目へ切り替える。
  int _showChatRequest = 0;

  @override
  Widget build(BuildContext context) {
    final coupleId = widget.coupleId;
    final pages = [
      // ① カレンダー
      CalendarScreen(coupleId: coupleId),
      // ② チャット（左右スワイプでカップルチャット ⇄ AIチャット）
      ChatPagerScreen(
        coupleId: coupleId,
        isActive: _index == 1,
        showChatRequest: _showChatRequest,
      ),
      // ③ 記念日
      AnniversaryHubScreen(coupleId: coupleId),
      // ④ ふたりの質問。IndexedStackで保持しているので、作り直さないと日付を
      // またいでも前日の質問のまま残る。アプリ復帰時・0時に作り直す。
      DailyRefresh(builder: (_) => const QuestionsRouteScreen()),
    ];

    // 通知タップなどで頼まれたタブ（ふたりの質問の通知なら「質問」、トークの
    // 通知なら「チャット」）を開く。チャットタブはAIチャット側を開いたままに
    // なっていることがあるので、2人のトークに戻すよう頼む。
    return HomeTabRequestListener(
      requests: HomeTabRequests.instance,
      onTab: (tab) => setState(() {
        _index = tab.index;
        if (tab == HomeTab.chat) _showChatRequest++;
      }),
      child: Scaffold(
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
            NavigationDestination(icon: Text('💬', style: TextStyle(fontSize: 20)), label: 'チャット'),
            NavigationDestination(icon: Text('💕', style: TextStyle(fontSize: 20)), label: '記念日'),
            NavigationDestination(icon: Text('💭', style: TextStyle(fontSize: 20)), label: '質問'),
          ],
        ),
      ),
    );
  }
}
