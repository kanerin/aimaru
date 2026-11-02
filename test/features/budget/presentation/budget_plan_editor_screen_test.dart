import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/data/budget_plan_repository.dart';
import 'package:aimaru/features/budget/domain/budget_plan.dart';
import 'package:aimaru/features/budget/presentation/budget_plan_editor_screen.dart';
import 'package:aimaru/features/budget/presentation/budget_widgets.dart';

import '../../../helpers/budget_fixtures.dart';

// シミュレーション・確定プラン編集画面。金額を変えると即座に再計算され、
// 確定プランとの差分（+5,000円 など）が出ること、保存・確定の経路を確かめる。
void main() {
  late FakeFirebaseFirestore db;
  late BudgetPlanRepository repo;
  const coupleId = 'couple-1';

  CollectionReference<Map<String, dynamic>> plansRef() =>
      db.collection('couples').doc(coupleId).collection('budgetPlans');

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = BudgetPlanRepository(firestore: db, uid: memberA);
  });

  // 確定・保存で画面を閉じる（pop）ため、ホームから積んだ状態で開く
  Future<void> openEditor(
    WidgetTester tester, {
    required BudgetPlan plan,
    BudgetPlan? baseline,
    BudgetEditorMode mode = BudgetEditorMode.simulation,
  }) async {
    tester.view.physicalSize = const Size(900, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => BudgetPlanEditorScreen(
                coupleId: coupleId,
                plan: plan,
                baseline: baseline,
                mode: mode,
                repositoryOverride: repo,
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder amountInput(String label) => find.descendant(
    of: find.widgetWithText(AmountSliderField, label),
    matching: find.byType(TextField),
  );

  testWidgets('金額を入力すると即座に再計算し、確定プランとの差分を出す', (tester) async {
    final active = realCouplePlan(id: 'plan-1');
    await openEditor(tester, plan: active.duplicateAsDraft(name: '案'), baseline: active);

    // 変える前はAの自由に使えるお金 70,000円、差分なし
    expect(find.text('+5,000円'), findsNothing);

    await tester.enterText(amountInput('A'), '185000');
    await tester.pump();

    expect(find.text('75,000円'), findsWidgets);
    expect(find.text('+5,000円'), findsWidgets);
  });

  testWidgets('共通支出を増やすと生活費口座の余りが減り、差分がマイナスで出る', (tester) async {
    final active = realCouplePlan(id: 'plan-1');
    await openEditor(tester, plan: active.duplicateAsDraft(name: '案'), baseline: active);

    await tester.enterText(amountInput('🏠 家賃'), '120000');
    await tester.pump();

    // 余り 35,000 → 25,000
    expect(find.text('+25,000円'), findsWidgets);
    expect(find.text('-10,000円'), findsWidgets);
  });

  testWidgets('入金を減らして不足が出ると警告を出す', (tester) async {
    final active = realCouplePlan(id: 'plan-1');
    await openEditor(tester, plan: active.duplicateAsDraft(name: '案'), baseline: active);

    await tester.enterText(amountInput('Bの入金'), '100000');
    await tester.pump();

    expect(find.textContaining('生活費口座が毎月15,000円不足しています'), findsOneWidget);
    expect(find.text('生活費の不足'), findsOneWidget);
  });

  testWidgets('入金ルールを収入比に切り替えると、手取りの比で分けた額を出す', (tester) async {
    final active = realCouplePlan(id: 'plan-1');
    await openEditor(tester, plan: active.duplicateAsDraft(name: '案'), baseline: active);

    await tester.tap(find.text('収入比'));
    await tester.pump();

    expect(find.text('54,310円'), findsWidgets);
    expect(find.text('120,690円'), findsWidgets);
  });

  testWidgets('未保存のシミュレーションを「確定にする」と、確定プランとして保存され元の確定プランは外れる',
      (tester) async {
    final active = await repo.createPlan(coupleId, realCouplePlan(), activate: true);
    await openEditor(tester, plan: active.duplicateAsDraft(name: '家賃上げた場合'), baseline: active);

    await tester.enterText(amountInput('🏠 家賃'), '120000');
    await tester.pump();
    await tester.tap(find.text('このプランを確定にする'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定にする'));
    await tester.pumpAndSettle();

    final actives = await plansRef().where('isActive', isEqualTo: true).get();
    expect(actives.docs, hasLength(1));
    expect(actives.docs.single.data()['name'], '家賃上げた場合');
    expect((actives.docs.single.data()['sharedExpenses'] as List).first['monthlyAmount'], 120000);
    expect((await plansRef().doc(active.id).get()).data()!['isActive'], isFalse);
    // 確定したら画面を閉じてサマリーへ戻る
    expect(find.byType(BudgetPlanEditorScreen), findsNothing);
    expect(find.textContaining('確定プランにしました'), findsOneWidget);
  });

  testWidgets('シミュレーションを保存すると、確定プランには影響せず仮案として残る', (tester) async {
    final active = await repo.createPlan(coupleId, realCouplePlan(), activate: true);
    await openEditor(tester, plan: active.duplicateAsDraft(name: '貯金多め'), baseline: active);

    await tester.enterText(amountInput('Bの毎月の貯金'), '100000');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final docs = (await plansRef().get()).docs;
    expect(docs, hasLength(2));
    final sim = docs.firstWhere((d) => d.data()['name'] == '貯金多め').data();
    expect(sim['isActive'], isFalse);
    expect((sim['savingsGoal'] as Map)['monthlyContributions'][memberB], 100000);
    expect((await plansRef().doc(active.id).get()).data()!['isActive'], isTrue);
    // 保存後も続けて試せるよう画面は開いたまま
    expect(find.text('保存済み'), findsOneWidget);
  });

  testWidgets('確定プランを編集して保存すると、変更内容が履歴に残る', (tester) async {
    final active = await repo.createPlan(coupleId, realCouplePlan(), activate: true);
    await openEditor(tester, plan: active, baseline: active, mode: BudgetEditorMode.editActive);

    await tester.enterText(amountInput('B'), '410000');
    await tester.pump();
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();

    final history = await db.collection('couples').doc(coupleId).collection('budgetHistory')
        .where('action', isEqualTo: 'updated').get();
    expect(history.docs.single.data()['changes'], [
      {'label': 'Bの手取り', 'before': '400,000円', 'after': '410,000円'},
    ]);
    expect(find.byType(BudgetPlanEditorScreen), findsNothing);
  });

  testWidgets('保存せずに戻ろうとすると、破棄の確認を出す', (tester) async {
    final active = realCouplePlan(id: 'plan-1');
    await openEditor(tester, plan: active.duplicateAsDraft(name: '案'), baseline: active);

    await tester.enterText(amountInput('A'), '190000');
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('変更を破棄しますか？'), findsOneWidget);
    await tester.tap(find.text('破棄する'));
    await tester.pumpAndSettle();
    expect(find.byType(BudgetPlanEditorScreen), findsNothing);
    expect(await plansRef().get().then((s) => s.docs), isEmpty);
  });
}
