import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/widgets/image_load_error.dart';

void main() {
  testWidgets('壊れた画像アイコンと読み上げラベルを出す', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: ImageLoadError(width: 180))),
    ));

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('画像を読み込めませんでした'), findsOneWidget);
    expect(tester.getSize(find.byType(ImageLoadError)), const Size(180, 140));
    handle.dispose();
  });

  testWidgets('height: nullなら親の大きさいっぱいに広がる', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 200, height: 100, child: ImageLoadError(height: null)),
        ),
      ),
    ));

    expect(tester.getSize(find.byType(ImageLoadError)), const Size(200, 100));
  });
}
