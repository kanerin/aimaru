// ── 結合テスト共通の下ごしらえ ──────────────────────────────────────
//
// 本物のFirestore/認証を使うが、接続先はローカルのFirebaseエミュレータ。
// 本番アプリはGoogleログインを使うがCIでは自動化できないため、テストでは
// 匿名ログインでユーザーを作り、そのuidでカップルをseedする。
// アプリ側から見ると「ログイン済み・ペアリング済み」の状態と区別がつかない。
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aimaru/firebase_options.dart';
import 'package:aimaru/services/firebase_bootstrap.dart';
import 'package:aimaru/utils/app_theme.dart';

/// テスト中に使うカップルID。setUpのたびに新しく作られる。
late String testCoupleId;

/// 匿名ログインした自分のuid。
String get testUid => FirebaseAuth.instance.currentUser!.uid;

/// アプリと同じ手順でFirebaseを初期化し、エミュレータへ繋ぐ。
/// setUpAllから1回だけ呼ぶこと。
Future<void> initE2E() async {
  if (!useFirebaseEmulator) {
    // 誤って本番のFirebaseに向けたまま結合テストを流すと実データを壊すため、
    // 明示的に止める。--dart-define=USE_FIREBASE_EMULATOR=true が必須。
    throw StateError(
      '結合テストは --dart-define=USE_FIREBASE_EMULATOR=true 付きで実行してください。'
      '本番のFirebaseへ接続した状態では実行できません。',
    );
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await connectFirebaseEmulators();
  await initializeDateFormatting('ja');
}

/// 匿名ユーザーでログインし、そのユーザーが所属するカップルをseedする。
///
/// 各テストのsetUpから呼ぶ。テストごとに新しいユーザー・カップルになるので、
/// テスト同士がデータを踏み合うことがない。
Future<void> signInAndSeedCouple({bool withPartner = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final cred = await FirebaseAuth.instance.signInAnonymously();
  final uid = cred.user!.uid;
  final db = FirebaseFirestore.instance;

  await db.collection('users').doc(uid).set(<String, dynamic>{
    'uid': uid,
    'displayName': 'テスト太郎',
    'email': 'test@example.com',
    'photoUrl': null,
    'createdAt': FieldValue.serverTimestamp(),
    'notifyOnNewEvent': true,
    'remindersEnabled': true,
    'reminderMinutesBefore': 60,
  });

  const partnerUid = 'partner-uid-for-e2e';
  if (withPartner) {
    await db.collection('users').doc(partnerUid).set(<String, dynamic>{
      'uid': partnerUid,
      'displayName': 'テスト花子',
      'email': 'partner@example.com',
    });
  }

  final coupleRef = db.collection('couples').doc();
  await coupleRef.set(<String, dynamic>{
    'memberIds': <String>[uid, if (withPartner) partnerUid],
    'inviteCode': 'TEST01',
    'createdAt': FieldValue.serverTimestamp(),
    'anniversary': null,
  });
  testCoupleId = coupleRef.id;
}

/// テストで作ったユーザーからログアウトする。各テストのtearDownから呼ぶ。
Future<void> signOutTestUser() async {
  await FirebaseAuth.instance.signOut();
}

/// 画面単体を、アプリ本体と同じテーマで実機上に描画する。
///
/// main.dart経由でアプリ全体を起動すると、GoRouterがトップレベルの
/// グローバル変数のためテスト間で画面遷移の状態が持ち越されてしまう。
/// 個々の機能テストは対象画面を直接描画したほうが安定し、かつFirestoreは
/// 本物（エミュレータ）なので結合テストとしての価値は変わらない。
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size? surfaceSize,
  double textScale = 1.0,
}) async {
  if (surfaceSize != null) {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  await tester.pumpWidget(
    MaterialApp(
      title: 'AIMARU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(AppColors.lavender),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: screen,
    ),
  );

  await settle(tester);
}

/// 画面が落ち着くまで待つ。
///
/// pumpAndSettleは「動き続けるアニメーション」があるとタイムアウトで例外を投げる。
/// このアプリはローディング中にCircularProgressIndicatorを回し続けるため、
/// 素のpumpAndSettleを使うとテストが不安定になる。
/// タイムアウトは失敗扱いにせず、一定回数pumpして先へ進める。
Future<void> settle(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      timeout,
    );
  } on FlutterError {
    // 回り続けるインジケータ等でsettleできないケース。
    // 実際の待ち合わせはpumpUntil側で行うのでここでは進めるだけ。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

/// 条件を満たすまで繰り返しpumpする。
/// Firestoreへの書き込み→ストリーム反映のように、完了までの時間が読めない
/// 待ち合わせに使う。
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('待ち時間${timeout.inSeconds}秒以内に条件を満たしませんでした'
      '${reason != null ? ': $reason' : ''}');
}

/// pumpUntilの非同期版。Firestoreへ問い合わせて確認したい場合に使う。
Future<void> pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('待ち時間${timeout.inSeconds}秒以内に条件を満たしませんでした'
      '${reason != null ? ': $reason' : ''}');
}

/// hintTextで入力欄を特定する。
///
/// このリポジトリの画面はテスト用のKeyを持たない方針なので、
/// 「n番目のTextField」のような並び順依存の指定を避けるために使う。
Finder textFieldWithHint(String hintPrefix) => find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').startsWith(hintPrefix),
      description: 'hintTextが「$hintPrefix」で始まるTextField',
    );

/// レイアウトのはみ出し（RenderFlex overflowなど）が起きていないことを確認する。
///
/// Flutterははみ出しをFlutterErrorとして報告するので、それを拾って落とす。
/// 「時刻ピッカーが重なる」「FABがボタンに被る」といった見た目の不具合は
/// この検査で自動的に検出できる。
void expectNoLayoutOverflow(WidgetTester tester, {String? context}) {
  final exception = tester.takeException();
  if (exception == null) return;
  fail('レイアウトのはみ出し/描画エラーが発生しました'
      '${context != null ? '（$context）' : ''}: $exception');
}
