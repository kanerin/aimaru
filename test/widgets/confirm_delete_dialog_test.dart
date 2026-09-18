import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/widgets/confirm_delete_dialog.dart';

void main() {
  Widget wrap(void Function(bool result) onResult) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await confirmDelete(
                  context,
                  title: 'テスト項目を削除',
                  message: '「サンプル」を削除します。元に戻せません。',
                );
                onResult(result);
              },
              child: const Text('開く'),
            ),
          ),
        ),
      );

  testWidgets('タイトル・本文を表示し、削除を押すとtrueを返す', (tester) async {
    bool? result;
    await tester.pumpWidget(wrap((r) => result = r));

    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();

    expect(find.text('テスト項目を削除'), findsOneWidget);
    expect(find.text('「サンプル」を削除します。元に戻せません。'), findsOneWidget);

    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('キャンセルを押すとfalseを返す', (tester) async {
    bool? result;
    await tester.pumpWidget(wrap((r) => result = r));

    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
