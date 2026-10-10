import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/widgets/thumb_remove_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 72, height: 72,
              child: Stack(children: [Positioned(top: 0, right: 0, child: child)]),
            ),
          ),
        ),
      );

  testWidgets('タップするとonTapが呼ばれる', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(wrap(ThumbRemoveButton(onTap: () => tapped++)));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(tapped, 1);
  });

  testWidgets('見た目の丸の外側でも48pxのタップ領域内なら反応する', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(wrap(ThumbRemoveButton(onTap: () => tapped++)));

    final rect = tester.getRect(find.byType(InkResponse));
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));

    // 丸（24px）の外だが48pxの領域内（左下寄り）をタップ
    await tester.tapAt(rect.bottomLeft + const Offset(3, -3));
    await tester.pump();

    expect(tapped, 1);
  });

  testWidgets('スクリーンリーダー向けにボタンとラベルを読み上げる', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(ThumbRemoveButton(onTap: () {}, label: '添付画像を外す')));

    expect(find.bySemanticsLabel('添付画像を外す'), findsOneWidget);
    final data = tester.getSemantics(find.bySemanticsLabel('添付画像を外す')).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });
}
