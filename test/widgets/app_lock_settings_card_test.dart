import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aimaru/services/app_lock_controller.dart';
import 'package:aimaru/widgets/app_lock_settings_card.dart';

// AppLockControllerはThemeControllerと同じシングルトンのため、テストごとに
// SharedPreferencesを初期化した上でloadを呼び直し、前のテストの状態を引きずらないようにする。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLockController.instance.load();
  });

  Widget wrap() => const MaterialApp(
        home: Scaffold(body: AppLockSettingsCard()),
      );

  Future<void> fillPinDialog(WidgetTester tester, String pin, String confirm) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), pin);
    await tester.enterText(fields.at(1), confirm);
    await tester.pump();
    await tester.tap(find.text('設定する'));
    await tester.pumpAndSettle();
  }

  testWidgets('初期状態ではオフで、PIN変更ボタンは出ない', (tester) async {
    await tester.pumpWidget(wrap());

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('パスコードを変更'), findsNothing);
  });

  testWidgets('スイッチをオンにするとPIN設定ダイアログが出て、一致するPINで有効化される', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('パスコードを設定'), findsOneWidget);

    await fillPinDialog(tester, '1234', '1234');

    expect(find.text('パスコードを設定'), findsNothing);
    expect(AppLockController.instance.enabled, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('パスコードを変更'), findsOneWidget);
  });

  testWidgets('PINが一致しない場合はエラーが出て有効化されない', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await fillPinDialog(tester, '1234', '5678');

    expect(find.text('入力が一致しません'), findsOneWidget);
    expect(AppLockController.instance.enabled, isFalse);
  });

  testWidgets('ダイアログをキャンセルすると有効化されない', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(AppLockController.instance.enabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('有効な状態でスイッチをオフにすると確認ダイアログを経て無効化される', (tester) async {
    await AppLockController.instance.setEnabled(true, pin: '1234');
    await tester.pumpWidget(wrap());

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('アプリロックを解除しますか？'), findsOneWidget);
    await tester.tap(find.text('解除する'));
    await tester.pumpAndSettle();

    expect(AppLockController.instance.enabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('「パスコードを変更」から新しいPINへ変更できる', (tester) async {
    await AppLockController.instance.setEnabled(true, pin: '1234');
    await tester.pumpWidget(wrap());

    await tester.tap(find.text('パスコードを変更'));
    await tester.pumpAndSettle();

    await fillPinDialog(tester, '5678', '5678');

    expect(AppLockController.instance.enabled, isTrue);
  });
}
