import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/domain/budget_history_entry.dart';
import 'package:aimaru/features/budget/domain/budget_plan_diff.dart';
import 'package:aimaru/features/budget/presentation/budget_history_screen.dart';

// 家計の変更履歴。ローディング・エラー・空・データの4状態を確かめる。
void main() {
  Future<void> pumpScreen(WidgetTester tester, Stream<List<BudgetHistoryEntry>> stream) =>
      tester.pumpWidget(MaterialApp(
        home: BudgetHistoryScreen(
          coupleId: 'couple-1',
          memberNames: const {'user-a': 'あい', 'user-b': 'まる'},
          historyStreamOverride: stream,
        ),
      ));

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<BudgetHistoryEntry>>();
    await pumpScreen(tester, controller.stream);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<BudgetHistoryEntry>>();
    await pumpScreen(tester, controller.stream);

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('履歴が無ければその旨を出す', (tester) async {
    final controller = StreamController<List<BudgetHistoryEntry>>();
    await pumpScreen(tester, controller.stream);

    controller.add([]);
    await tester.pump();

    expect(find.text('まだ変更履歴はありません'), findsOneWidget);

    await controller.close();
  });

  testWidgets('誰が・いつ・何を変えたかを出す', (tester) async {
    final controller = StreamController<List<BudgetHistoryEntry>>();
    await pumpScreen(tester, controller.stream);

    controller.add([
      BudgetHistoryEntry(
        id: 'h2',
        planId: 'plan-1',
        planName: '確定プラン',
        action: BudgetHistoryAction.updated,
        changedBy: 'user-b',
        changedAt: DateTime(2026, 11, 2, 21, 5),
        changes: const [BudgetChange('家賃', before: '110,000円', after: '120,000円')],
      ),
      const BudgetHistoryEntry(
        id: 'h1',
        planId: 'plan-2',
        planName: '家賃上げた場合',
        action: BudgetHistoryAction.activated,
        changedBy: 'user-a',
      ),
    ]);
    await tester.pump();

    expect(find.text('まるが「確定プラン」を変更'), findsOneWidget);
    expect(find.text('2026/11/2 21:05'), findsOneWidget);
    expect(find.text('・家賃: 110,000円 → 120,000円'), findsOneWidget);
    expect(find.text('あいが「家賃上げた場合」を確定プランに設定'), findsOneWidget);
    // サーバー時刻がまだ確定していない（今まさに書いた）もの
    expect(find.text('保存中…'), findsOneWidget);

    await controller.close();
  });
}
