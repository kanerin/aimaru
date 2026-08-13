import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/todos_screen.dart';

// やりたいことリストがストリームエラーで無限ローディングのまま固まらないことを確かめる。
//
// 本番でfirestore.rulesがデプロイされておらず、todosコレクションの読み取りが
// 権限エラーになったまま画面が永久にスピナーで固まる不具合が実際に発生した
// （StreamBuilderがhasDataだけを見てhasErrorを見ていなかったため）。
void main() {
  Widget wrap(Stream<List<TodoItem>> stream) => MaterialApp(
        home: TodosScreen(coupleId: 'couple-1', todosStreamOverride: stream),
      );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが来たら一覧を表示する', (tester) async {
    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      TodoItem(
        id: 't1',
        coupleId: 'couple-1',
        text: '温泉に行く',
        createdBy: 'u1',
        createdAt: DateTime(2026, 1, 1),
      ),
    ]);
    await tester.pump();

    expect(find.text('温泉に行く'), findsOneWidget);

    await controller.close();
  });
}
