import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/utils/app_theme.dart';

void main() {
  testWidgets('AppTheme renders a MaterialApp without error', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: Center(child: Text('AIMARU'))),
    ));

    expect(find.text('AIMARU'), findsOneWidget);
  });
}
