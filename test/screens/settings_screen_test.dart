import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aimaru/screens/settings_screen.dart';
import 'package:aimaru/services/theme_controller.dart';
import 'package:aimaru/utils/app_theme.dart';

// テーマ色ピッカーのアクセシビリティ（読み上げラベルとタップ領域）を確かめる。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap() => const MaterialApp(home: Scaffold(body: AccentColorPicker()));

  testWidgets('各テーマ色が色名付きのボタンとして読み上げられる', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap());

    for (final name in AppColors.accentPresets.keys) {
      expect(find.bySemanticsLabel('テーマ色 $name'), findsOneWidget);
    }
    handle.dispose();
  });

  testWidgets('タップ領域が48px以上あり、タップでテーマ色が切り替わる', (tester) async {
    await tester.pumpWidget(wrap());

    final size = tester.getSize(find.ancestor(
      of: find.text('ピンク'),
      matching: find.byType(ConstrainedBox),
    ).first);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    await tester.tap(find.text('ピンク'));
    await tester.pump();
    expect(ThemeController.instance.accentName, 'ピンク');
  });
}
