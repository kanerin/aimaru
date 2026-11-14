import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aimaru/screens/image_detail_screen.dart';

void main() {
  Widget wrap() => MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ImageDetailScreen(imageUrl: 'https://example.com/test.jpg'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('画像・閉じるボタン・保存ボタンが表示される', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ImageDetailScreen), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });

  testWidgets('閉じるボタンをタップすると画面が閉じる', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ImageDetailScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(ImageDetailScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('閉じるボタン・保存ボタンにツールチップが設定されている', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('閉じる'), findsOneWidget);
    expect(find.byTooltip('画像を保存'), findsOneWidget);
  });

  testWidgets('画像の読み込み失敗表示は理由と対処を文言で案内する', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(backgroundColor: Colors.black, body: Center(child: ImageDetailLoadError())),
    ));

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.textContaining('画像を読み込めませんでした'), findsOneWidget);
    expect(find.textContaining('もう一度開いてください'), findsOneWidget);
  });
}
