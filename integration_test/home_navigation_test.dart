// 結合テスト: ログイン済み・ペアリング済みの状態でアプリ本体を起動し、
// ホーム（5タブ）まで到達することと、タブを切り替えても各タブの状態が
// 失われないことを確認する。
//
// 「タブを移動するとAIチャットの会話が消える」不具合の回帰テストを兼ねる。
// main.dartのIndexedStackをpages[_index]に戻すとこのテストが落ちる。
//
// ウィジェットテストでは main() の初期化・GoRouterのredirect・
// CoupleServiceの実クエリを通らないため、この経路は結合テストでしか守れない。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:aimaru/main.dart' as app;

import 'helpers/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initE2E();
    await signInAndSeedCouple();
  });

  tearDownAll(() async {
    await signOutTestUser();
  });

  testWidgets('ログイン済みならホームに到達し、タブを往復しても入力内容が保持される',
      (tester) async {
    app.main();
    await settle(tester);

    // ── ホーム（BottomNav）まで到達する ──
    await pumpUntil(
      tester,
      () => find.text('やりたい').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 40),
      reason: 'ホーム画面（下部ナビ）に到達しない',
    );

    for (final label in <String>['カレンダー', 'AI', 'チャット', '思い出', 'やりたい']) {
      expect(find.text(label), findsWidgets, reason: '$label タブが無い');
    }

    // ── AIタブへ移動して入力する ──
    await tester.tap(find.text('AI'));
    await settle(tester);

    const draft = 'タブを移動しても消えないこと';
    final aiInput = textFieldWithHint('予定を追加');
    expect(aiInput, findsOneWidget, reason: 'AIチャットの入力欄が見つからない');
    await tester.enterText(aiInput, draft);
    await settle(tester);

    // ── 別タブへ移動して戻る ──
    await tester.tap(find.text('チャット'));
    await settle(tester);
    await tester.tap(find.text('AI'));
    await settle(tester);

    // IndexedStackで全画面をマウントしたまま保持しているので入力は残るはず。
    // pages[_index]のような実装だと画面が破棄され、ここで落ちる。
    final input = tester.widget<TextField>(textFieldWithHint('予定を追加'));
    expect(
      input.controller?.text,
      draft,
      reason: 'タブを往復するとAIチャットの入力内容が失われている',
    );

    expectNoLayoutOverflow(tester, context: 'ホーム/タブ切り替え');
  });
}
