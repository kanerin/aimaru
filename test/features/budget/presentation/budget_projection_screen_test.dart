import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/presentation/budget_projection_chart.dart';
import 'package:aimaru/features/budget/presentation/budget_projection_screen.dart';

import '../../../helpers/budget_fixtures.dart';

// 貯金推移グラフ。確定プランとシミュレーションを重ね、どれを重ねるか切り替えられる。
void main() {
  final plans = [
    realCouplePlan(id: 'plan-1'),
    realCouplePlan(id: 'sim-1', name: '貯金多め', isActive: false, savingsB: 150000),
  ];

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: BudgetProjectionScreen(plans: plans)));
  }

  List<String> shownSeries(WidgetTester tester) => tester
      .widget<BudgetProjectionChart>(find.byType(BudgetProjectionChart))
      .series
      .map((s) => s.label)
      .toList();

  testWidgets('確定プランとシミュレーションを重ねて描き、それぞれの期限時点の見込みを出す', (tester) async {
    await pumpScreen(tester);

    expect(shownSeries(tester), ['確定プラン', '貯金多め']);
    expect(find.text('期限時点 6,240,000円・目標到達 2030年8月'), findsOneWidget);
    // Bの貯金 +60,000/月 × 36ヶ月 = +2,160,000
    expect(find.textContaining('期限時点 8,400,000円'), findsOneWidget);
    // 目標ラインは目標額（8,000,000）で引く
    final chart = tester.widget<BudgetProjectionChart>(find.byType(BudgetProjectionChart));
    expect(chart.series.first.targetAmount, 8000000);
    expect(chart.series.first.points, hasLength(36));
  });

  testWidgets('チェックを外したプランはグラフから外れる', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('貯金多め'));
    await tester.pump();

    expect(shownSeries(tester), ['確定プラン']);
  });
}
