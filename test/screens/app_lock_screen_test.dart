import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/screens/app_lock_screen.dart';

void main() {
  // 生体認証はテストで明示的に有効化しない限り「使えない」状態にしておく
  // （既定のfalseなら端末への問い合わせ自体が起きず、PIN入力の検証に集中できる）。
  Widget wrap(
    Future<bool> Function(String pin) unlock, {
    Future<bool> Function()? canUseBiometrics,
    Future<bool> Function()? biometricUnlock,
  }) =>
      MaterialApp(
        home: AppLockScreen(
          unlockOverride: unlock,
          canUseBiometricsOverride: canUseBiometrics ?? () async => false,
          biometricUnlockOverride: biometricUnlock,
        ),
      );

  Future<void> enterPin(WidgetTester tester, String pin) async {
    await tester.enterText(find.byType(TextField), pin);
    await tester.pump();
  }

  testWidgets('4桁未満では解除ボタンが無効', (tester) async {
    await tester.pumpWidget(wrap((_) async => true));

    await enterPin(tester, '12');

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('正しいPINを入力すると解除処理が呼ばれる', (tester) async {
    String? submittedPin;
    await tester.pumpWidget(wrap((pin) async {
      submittedPin = pin;
      return true;
    }));

    await enterPin(tester, '1234');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(submittedPin, '1234');
    expect(find.text('パスコードが違います'), findsNothing);
  });

  testWidgets('間違ったPINを入力するとエラーメッセージが出て入力欄がクリアされる', (tester) async {
    await tester.pumpWidget(wrap((_) async => false));

    await enterPin(tester, '9999');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.text('パスコードが違います'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  group('生体認証での解除', () {
    testWidgets('生体認証が使えない端末・設定では専用ボタンを出さない', (tester) async {
      await tester.pumpWidget(wrap((_) async => true));
      await tester.pump();

      expect(find.text('指紋・顔認証で解除'), findsNothing);
    });

    testWidgets('生体認証が使えるなら開いた直後に一度だけ自動で認証を求める', (tester) async {
      var calls = 0;
      await tester.pumpWidget(wrap(
        (_) async => true,
        canUseBiometrics: () async => true,
        biometricUnlock: () async {
          calls++;
          return true;
        },
      ));
      await tester.pumpAndSettle();

      expect(calls, 1);
    });

    testWidgets('自動認証をキャンセルしてもPIN入力とやり直しボタンが残る', (tester) async {
      var calls = 0;
      await tester.pumpWidget(wrap(
        (_) async => true,
        canUseBiometrics: () async => true,
        biometricUnlock: () async {
          calls++;
          return false;
        },
      ));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('パスコードが違います'), findsNothing);

      await tester.tap(find.text('指紋・顔認証で解除'));
      await tester.pumpAndSettle();

      expect(calls, 2);
    });
  });
}
