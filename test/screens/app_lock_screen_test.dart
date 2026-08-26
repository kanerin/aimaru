import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/screens/app_lock_screen.dart';

void main() {
  Widget wrap(Future<bool> Function(String pin) unlock) => MaterialApp(
        home: AppLockScreen(unlockOverride: unlock),
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
}
