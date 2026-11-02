import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aimaru/features/budget/data/budget_plan_repository.dart';
import 'package:aimaru/features/budget/domain/budget_plan.dart';
import 'package:aimaru/features/budget/presentation/budget_summary_screen.dart';
import 'package:aimaru/services/settings_service.dart';

import '../../../helpers/budget_fixtures.dart';

// 家計サマリー（確定プラン）の画面。ストリームのローディング・エラー・データの
// 3状態と、毎月の流れ・警告・シミュレーション一覧の表示を確かめる。
void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    Stream<List<BudgetPlan>> stream, {
    Future<List<BudgetMemberSeed>> Function()? loadMembers,
  }) async {
    // サマリーは縦に長いので、テストでは画面を縦長にして全部を描画させる
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: BudgetSummaryScreen(
        coupleId: 'couple-1',
        plansStreamOverride: stream,
        repositoryOverride: BudgetPlanRepository(firestore: db, uid: memberA),
        settingsServiceOverride: SettingsService(),
        loadMembersOverride: loadMembers,
        nowOverride: () => DateTime(2026, 11, 2),
      ),
    ));
  }

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<BudgetPlan>>();
    await pumpScreen(tester, controller.stream);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<BudgetPlan>>();
    await pumpScreen(tester, controller.stream);

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('プランがまだ無ければ作成を促し、ひな型を編集画面で開く', (tester) async {
    final controller = StreamController<List<BudgetPlan>>();
    await pumpScreen(
      tester,
      controller.stream,
      loadMembers: () async => [
        (memberId: memberA, displayName: 'あい'),
        (memberId: memberB, displayName: 'まる'),
      ],
    );

    controller.add([]);
    await tester.pump();
    expect(find.text('ふたりの家計プランを作りましょう'), findsOneWidget);

    await tester.tap(find.text('家計プランを作る'));
    await tester.pumpAndSettle();

    // まだ保存していないひな型を、確定プランとして作る編集画面で開く
    expect(find.text('この内容で作る'), findsOneWidget);
    expect(find.text('あい'), findsWidgets);
    expect(find.text('まる'), findsWidgets);
    expect(find.text('🏠 家賃'), findsWidgets);

    await controller.close();
  });

  testWidgets('確定プランの毎月の流れ・貯金の見込み・警告を表示する', (tester) async {
    final controller = StreamController<List<BudgetPlan>>();
    await pumpScreen(tester, controller.stream);

    controller.add([realCouplePlan(id: 'plan-1')]);
    await tester.pump();

    expect(find.text('確定プラン'), findsOneWidget);
    expect(find.text('毎月の流れ'), findsOneWidget);
    // 手取り → 生活費口座 → 貯金口座 → 自由に使えるお金
    expect(find.text('180,000円'), findsOneWidget);
    expect(find.text('-60,000円'), findsOneWidget);
    expect(find.text('-50,000円'), findsOneWidget);
    // 70,000円は食費/日用品の金額としても出る
    expect(find.text('70,000円'), findsWidgets);
    expect(find.text('160,000円'), findsOneWidget);
    // 生活費口座: 必要額と余り
    expect(find.text('175,000円'), findsOneWidget);
    expect(find.text('+35,000円'), findsOneWidget);
    // 貯金: 年間・期限時点の見込み
    expect(find.text('2,080,000円'), findsOneWidget);
    expect(find.text('6,240,000円'), findsOneWidget);
    // 警告: 期限までに未達・余りが大きい
    expect(find.textContaining('足りません'), findsOneWidget);
    expect(find.textContaining('余りが毎月35,000円'), findsOneWidget);

    await controller.close();
  });

  testWidgets('シミュレーションは確定プランとの差分つきで一覧に出る', (tester) async {
    final controller = StreamController<List<BudgetPlan>>();
    await pumpScreen(tester, controller.stream);

    controller.add([
      realCouplePlan(id: 'plan-1'),
      realCouplePlan(id: 'sim-1', name: '貯金を増やす案', isActive: false, savingsA: 55000),
    ]);
    await tester.pump();

    expect(find.text('貯金を増やす案'), findsOneWidget);
    // Aの自由に使えるお金が5,000円減る
    expect(find.text('-5,000円'), findsOneWidget);

    await controller.close();
  });

  testWidgets('「ボーナスをカレンダーに表示」は端末の設定に保存される', (tester) async {
    final controller = StreamController<List<BudgetPlan>>();
    await pumpScreen(tester, controller.stream);
    controller.add([realCouplePlan(id: 'plan-1')]);
    await tester.pump();

    await tester.tap(find.byTooltip('その他'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckedPopupMenuItem<String>));
    await tester.pumpAndSettle();

    expect(await SettingsService().getShowBudgetBonuses(), isTrue);

    await controller.close();
  });

  testWidgets('「シミュレーション」で名前を決めると、確定プランの複製を編集画面で開く', (tester) async {
    final controller = StreamController<List<BudgetPlan>>();
    await pumpScreen(tester, controller.stream);
    controller.add([realCouplePlan(id: 'plan-1')]);
    await tester.pump();

    await tester.tap(find.text('シミュレーション').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '家賃上げた場合');
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();

    expect(find.text('このプランを確定にする'), findsOneWidget);
    expect(find.text('家賃上げた場合'), findsOneWidget);

    await controller.close();
  });
}
