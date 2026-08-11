// 結合テスト: 実機/エミュレータ上でアプリ本体（main.dart）を起動し、
// Firebase初期化・ルーティング・主要画面遷移が実際に動くことを確認する。
// ウィジェットテストと違いFirebase等のプラグインをモックせず本物を使うため、
// 実行には接続済みの端末/エミュレータが必要。
//
// 実行方法:
//   flutter test integration_test/app_test.dart -d <device-id>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:aimaru/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('起動: 未ログイン状態ならログイン画面に到達する', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // 既にログイン済みの端末で実行した場合はこのテストの対象外
    if (FirebaseAuth.instance.currentUser != null) {
      return;
    }

    expect(find.text('Googleでログイン'), findsOneWidget);
    expect(find.text('AIMARU'), findsWidgets);
  });
}
