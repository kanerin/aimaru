import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/widgets/circular_action_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('タップするとonTapが呼ばれる', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(wrap(CircularActionButton(
      icon: const Icon(Icons.add),
      semanticLabel: '追加',
      onTap: () => tapped++,
      decoration: const BoxDecoration(color: Colors.pink, shape: BoxShape.circle),
    )));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(tapped, 1);
  });

  testWidgets('スクリーンリーダー向けにボタンとラベルを読み上げる', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(CircularActionButton(
      icon: const Icon(Icons.send),
      semanticLabel: '送信',
      onTap: () {},
      decoration: const BoxDecoration(color: Colors.pink, shape: BoxShape.circle),
    )));

    expect(
      tester.getSemantics(find.byIcon(Icons.send)),
      matchesSemantics(label: '送信', isButton: true, hasEnabledState: true, isEnabled: true),
    );

    handle.dispose();
  });

  testWidgets('onTapが未指定のときは無効なボタンとして扱われる', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(const CircularActionButton(
      icon: Icon(Icons.add),
      semanticLabel: '追加',
      onTap: null,
      decoration: BoxDecoration(color: Colors.pink, shape: BoxShape.circle),
    )));

    expect(
      tester.getSemantics(find.byIcon(Icons.add)),
      matchesSemantics(label: '追加', isButton: true, hasEnabledState: true, isEnabled: false),
    );

    handle.dispose();
  });

  testWidgets('tooltipを指定すると長押しで文言を表示する', (tester) async {
    await tester.pumpWidget(wrap(CircularActionButton(
      icon: const Icon(Icons.add_photo_alternate_outlined),
      semanticLabel: '画像から予定を読み取る',
      tooltip: '画像から予定を読み取る',
      onTap: () {},
      decoration: const BoxDecoration(color: Colors.pink, shape: BoxShape.circle),
    )));

    expect(find.byType(Tooltip), findsOneWidget);
  });
}
