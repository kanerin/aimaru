import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/utils/app_theme.dart';

void main() {
  testWidgets('AppTheme renders a MaterialApp without error', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(AppColors.lavender),
      home: const Scaffold(body: Center(child: Text('AIMARU'))),
    ));

    expect(find.text('AIMARU'), findsOneWidget);
  });

  testWidgets('AppTheme.light uses the given accent as the primary color', (WidgetTester tester) async {
    const accent = Color(0xFF63B79E); // ミント

    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(accent),
      home: Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
    ));

    expect(Theme.of(capturedContext).colorScheme.primary, accent);
  });

  testWidgets('appAccent/appAccentSoft read from the active theme', (WidgetTester tester) async {
    const accent = Color(0xFFE28AA5); // ピンク
    late BuildContext capturedContext;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(accent),
      home: Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
    ));

    expect(appAccent(capturedContext), accent);
    // ソフト版は白に寄せた色であり、素のアクセントとは異なる
    expect(appAccentSoft(capturedContext), isNot(accent));
  });
}
