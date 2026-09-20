import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/screens/questions_route_screen.dart';
import 'package:aimaru/screens/questions_screen.dart';

// ふたりの質問の通知タップで開く入口画面が、ペア情報の読み込み中・失敗・
// ペア無し・成功の各状態で固まらずに表示されることを確かめる。
void main() {
  Widget wrap(Future<QuestionsRouteArgs?> Function() load) =>
      MaterialApp(home: QuestionsRouteScreen(loadOverride: load));

  testWidgets('読み込み中はインジケータを出す', (tester) async {
    final completer = Completer<QuestionsRouteArgs?>();
    await tester.pumpWidget(wrap(() => completer.future));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(QuestionsScreen), findsNothing);
  });

  testWidgets('読み込みに失敗したらエラーと再読み込みを出し、再試行できる', (tester) async {
    var calls = 0;
    await tester.pumpWidget(wrap(() async {
      calls++;
      if (calls == 1) throw Exception('network');
      return null;
    }));
    await tester.pumpAndSettle();

    expect(find.textContaining('読み込みに失敗しました'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('ペアが見つかりませんでした'), findsOneWidget);
  });

  testWidgets('ペアが無ければその旨を出す', (tester) async {
    await tester.pumpWidget(wrap(() async => null));
    await tester.pumpAndSettle();

    expect(find.text('ペアが見つかりませんでした'), findsOneWidget);
    expect(find.byType(QuestionsScreen), findsNothing);
  });
}
