import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/widgets/load_error_view.dart';

void main() {
  testWidgets('失敗の案内と「再読み込み」を出し、押すとonRetryが呼ばれる', (tester) async {
    var retried = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LoadErrorView(onRetry: () => retried++)),
    ));

    expect(find.textContaining('読み込みに失敗しました'), findsOneWidget);
    await tester.tap(find.text('再読み込み'));
    expect(retried, 1);
  });
}
