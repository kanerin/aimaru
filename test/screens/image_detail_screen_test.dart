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
}
