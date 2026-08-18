import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/expenses_screen.dart';

// 割り勘・立て替え画面がストリームエラーで無限ローディングのまま固まらないこと、
// および精算額の表示が正しく出ることを確かめる。
void main() {
  const uidA = 'user-a';
  const uidB = 'user-b';

  Widget wrap(Stream<List<ExpenseItem>> stream) => MaterialApp(
        home: ExpensesScreen(
          coupleId: 'couple-1',
          memberIds: const [uidA, uidB],
          partnerName: 'パートナー',
          currentUidOverride: uidA,
          expensesStreamOverride: stream,
        ),
      );

  ExpenseItem buildExpense({required int amount, required String paidBy}) => ExpenseItem(
        id: 'exp-1',
        coupleId: 'couple-1',
        title: 'ディナー代',
        amount: amount,
        paidBy: paidBy,
        createdBy: paidBy,
        createdAt: DateTime(2026, 1, 1),
      );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<ExpenseItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<ExpenseItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが来たら一覧と精算額を表示する', (tester) async {
    final controller = StreamController<List<ExpenseItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([buildExpense(amount: 4000, paidBy: uidA)]);
    await tester.pump();

    expect(find.text('ディナー代'), findsOneWidget);
    // uidAが4000円払っており、視点はuidA（あなた）なので、
    // パートナーが半額(2000円)を渡すと精算される表示になるはず
    expect(find.textContaining('2000'), findsOneWidget);

    await controller.close();
  });

  testWidgets('記録が無ければ精算完了の表示になる', (tester) async {
    final controller = StreamController<List<ExpenseItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    expect(find.textContaining('精算は完了しています'), findsOneWidget);
    expect(find.textContaining('まだ記録がありません'), findsOneWidget);
    expect(find.text('精算する'), findsNothing);

    await controller.close();
  });

  testWidgets('未精算があれば「精算する」ボタンが出る', (tester) async {
    final controller = StreamController<List<ExpenseItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([buildExpense(amount: 4000, paidBy: uidA)]);
    await tester.pump();

    expect(find.text('精算する'), findsOneWidget);

    await controller.close();
  });

  testWidgets('精算記録は一覧で「精算」として区別して表示され、精算し終えるとボタンが消える', (tester) async {
    final controller = StreamController<List<ExpenseItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      buildExpense(amount: 4000, paidBy: uidA),
      ExpenseItem(
        id: 'settlement-1',
        coupleId: 'couple-1',
        title: '精算',
        amount: 2000,
        paidBy: uidB,
        createdBy: uidB,
        createdAt: DateTime(2026, 1, 2),
        isSettlement: true,
      ),
    ]);
    await tester.pump();

    expect(find.text('精算'), findsOneWidget);
    expect(find.textContaining('パートナーがあなたに精算'), findsOneWidget);
    expect(find.textContaining('精算は完了しています'), findsOneWidget);
    // 精算済みまで反映されてボタンは出ない
    expect(find.text('精算する'), findsNothing);

    await controller.close();
  });

  testWidgets('精算するボタンを押すと金額を含む確認ダイアログが出る', (tester) async {
    final controller = StreamController<List<ExpenseItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([buildExpense(amount: 4000, paidBy: uidA)]);
    await tester.pump();

    await tester.tap(find.text('精算する'));
    await tester.pump();

    expect(find.text('精算しますか？'), findsOneWidget);
    expect(find.textContaining('¥2000'), findsWidgets);

    await controller.close();
  });
}
