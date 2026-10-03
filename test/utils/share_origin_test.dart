import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aimaru/utils/share_origin.dart';

void main() {
  testWidgets('描画済みのウィジェットからは位置とサイズを持つ矩形を返す', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 10, top: 20),
          child: SizedBox(
            width: 100,
            height: 50,
            child: Builder(builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            }),
          ),
        ),
      ),
    ));
    final rect = shareOriginOf(ctx);
    expect(rect, isNotNull);
    expect(rect!.size, const Size(100, 50));
    expect(rect.topLeft, const Offset(10, 20));
  });

  testWidgets('サイズが0のときはnullを返す（iPadで例外になる矩形を渡さない）', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox.shrink(
          child: Builder(builder: (c) {
            ctx = c;
            return const SizedBox.shrink();
          }),
        ),
      ),
    ));
    expect(shareOriginOf(ctx), isNull);
  });
}
