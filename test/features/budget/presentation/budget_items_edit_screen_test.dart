import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/domain/budget_plan.dart';
import 'package:aimaru/features/budget/presentation/budget_items_edit_screen.dart';

import '../../../helpers/budget_fixtures.dart';

// 項目の編集（共通支出・補助・ボーナスの追加/削除/並び替え）。
// この画面はFirestoreに書かず、編集後のプランを呼び出し元へ返す。
void main() {
  // 「完了」で返ってきたプランを受け取れるよう、ホームから積んで開く
  Future<BudgetPlan? Function()> openItems(WidgetTester tester, BudgetPlan plan) async {
    BudgetPlan? returned;
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              returned = await Navigator.of(context).push<BudgetPlan>(MaterialPageRoute(
                builder: (_) => BudgetItemsEditScreen(plan: plan),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => returned;
  }

  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();
  }

  testWidgets('共通支出を追加すると、名前・金額・カテゴリつきで末尾に加わる', (tester) async {
    final result = await openItems(tester, realCouplePlan());

    await tester.tap(find.text('共通支出を追加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '項目名'), '通信費');
    await tester.enterText(find.widgetWithText(TextField, '毎月の金額'), '8,000');
    await tester.tap(find.byType(DropdownButtonFormField<ExpenseCategory>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('📱 通信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await done(tester);

    final added = result()!.sharedExpenses.last;
    expect(added.label, '通信費');
    expect(added.monthlyAmount, 8000);
    expect(added.category, ExpenseCategory.communication);
    expect(added.id, isNotEmpty);
    expect(result()!.sharedExpenses, hasLength(5));
  });

  testWidgets('共通支出を削除できる', (tester) async {
    final result = await openItems(tester, realCouplePlan());

    await tester.tap(find.byTooltip('光熱費を削除'));
    await tester.pumpAndSettle();
    await done(tester);

    expect(result()!.sharedExpenses.map((e) => e.label), ['家賃', '水道', '食費/日用品（お酒以外）']);
  });

  testWidgets('既存の共通支出をタップして名前と金額を変えられる（idは変わらない）', (tester) async {
    final result = await openItems(tester, realCouplePlan());

    await tester.tap(find.text('水道'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '項目名'), '水道代');
    await tester.enterText(find.widgetWithText(TextField, '毎月の金額'), '12000');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await done(tester);

    final water = result()!.sharedExpenses[1];
    expect(water.id, 'water');
    expect(water.label, '水道代');
    expect(water.monthlyAmount, 12000);
  });

  testWidgets('つまみをドラッグして共通支出を並び替えられる', (tester) async {
    final result = await openItems(tester, realCouplePlan());

    // 先頭（家賃）のつまみを下へドラッグして2つ目以降へ
    final handle = find.byIcon(Icons.drag_handle).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    await done(tester);

    final labels = result()!.sharedExpenses.map((e) => e.label).toList();
    expect(labels.first, isNot('家賃'));
    expect(labels, containsAll(['家賃', '水道', '光熱費', '食費/日用品（お酒以外）']));
  });

  testWidgets('補助を追加すると受け取る人を選べる', (tester) async {
    final result = await openItems(tester, realCouplePlan());

    await tester.tap(find.text('補助'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('補助を追加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '項目名'), '扶養手当');
    await tester.enterText(find.widgetWithText(TextField, '毎月の金額'), '5000');
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await done(tester);

    final added = result()!.offsets.last;
    expect(added.label, '扶養手当');
    expect(added.monthlyAmount, 5000);
    expect(added.receivedBy, memberA);
  });

  testWidgets('ボーナス（収入）とボーナスからの貯金を追加・削除できる', (tester) async {
    final result = await openItems(tester, realCouplePlan());

    await tester.tap(find.text('ボーナス'));
    await tester.pumpAndSettle();

    // Aのボーナスを追加（既定は6月）
    await tester.tap(find.text('追加').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '支給額（手取り）'), '300000');
    await tester.enterText(find.widgetWithText(TextField, '支給日（任意）'), '25');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // ボーナスからの貯金（Bの12月 200,000）を1件削除
    await tester.tap(find.byTooltip('B・12月を削除'));
    await tester.pumpAndSettle();
    await done(tester);

    final plan = result()!;
    expect(plan.members.first.bonuses, [const Bonus(month: 6, amount: 300000, payDay: 25)]);
    expect(plan.savingsGoal.bonusContributions.map((b) => b.month), [6]);
  });

  testWidgets('戻るボタンでも編集内容を返す（保存は呼び出し元で行う）', (tester) async {
    final result = await openItems(tester, realCouplePlan());

    await tester.tap(find.byTooltip('水道を削除'));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();

    expect(result()!.sharedExpenses.map((e) => e.label), isNot(contains('水道')));
  });
}
