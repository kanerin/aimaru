// 結合テスト: 実機/エミュレータ上でアプリ本体（main.dart）を起動し、
// Firebase初期化・ルーティングが実際に動くことを確認する。
// ウィジェットテストと違いFirebase等のプラグインをモックせず本物を使うため、
// 実行には接続済みの端末/エミュレータが必要。
//
// 接続先はローカルのFirebaseエミュレータなので、本番データには触れない。
//
// 実行方法（scripts/run_e2e.sh 経由が楽）:
//   flutter test integration_test/app_test.dart \
//     --dart-define=USE_FIREBASE_EMULATOR=true -d <device-id>
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:aimaru/main.dart' as app;

import 'helpers/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initE2E();
    // 別のテストファイルの実行でログイン状態が端末に残っている可能性があるため、
    // 「未ログイン」を確実な前提にしてから始める
    await FirebaseAuth.instance.signOut();
  });

  testWidgets('起動: 未ログイン状態ならログイン画面に到達する', (tester) async {
    app.main();
    await settle(tester);

    await pumpUntil(
      tester,
      () => find.text('Googleでログイン').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 40),
      reason: 'ログイン画面に到達しない（main()の初期化で止まっている可能性）',
    );

    expect(find.text('AIMARU'), findsWidgets);
    expectNoLayoutOverflow(tester, context: 'ログイン画面');
  });
}
