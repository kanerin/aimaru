import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/widgets/pairing_preview_cards.dart';

void main() {
  Widget wrap() => const MaterialApp(
        home: Scaffold(body: PairingPreviewCards()),
      );

  testWidgets('ペアになるとできる機能の一覧を横スクロールで表示する', (tester) async {
    await tester.pumpWidget(wrap());

    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('共有カレンダー'), findsOneWidget);
    expect(find.text('AIプランナー'), findsOneWidget);
    expect(find.text('カップルチャット'), findsOneWidget);
    expect(find.text('やりたいことリスト'), findsOneWidget);
  });

  testWidgets('最後のカードまでスクロールできる', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.drag(find.byType(ListView), const Offset(-2000, 0));
    await tester.pumpAndSettle();

    expect(find.text('やりたいことリスト'), findsOneWidget);
  });
}
