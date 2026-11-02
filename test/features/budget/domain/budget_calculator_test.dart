import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/domain/budget_calculator.dart';
import 'package:aimaru/features/budget/domain/budget_plan.dart';
import 'package:aimaru/features/budget/domain/budget_result.dart';
import 'package:aimaru/features/budget/domain/year_month.dart';

import '../../../helpers/budget_fixtures.dart';

// 家計の計算エンジン（BudgetPlan → BudgetResult）の単体テスト。
// UI・Firebaseに依存しない純粋関数なので、ここで金額の正しさを固める。
void main() {
  group('実際の2人のルール（期待値は2人で確認済みの数字）', () {
    final result = BudgetCalculator.calculate(realCouplePlan());

    test('共通支出の合計 = 205,000', () {
      expect(result.totalSharedExpenses, 205000);
    });

    test('必要額（合計 − 家賃補助）= 175,000', () {
      expect(result.totalOffsets, 30000);
      expect(result.netRequired, 175000);
    });

    test('生活費口座への入金は固定額のまま A 60,000 / B 150,000', () {
      expect(result.livingContributions, {memberA: 60000, memberB: 150000});
      expect(result.totalLivingContributions, 210000);
    });

    test('生活費口座の余剰 = +35,000', () {
      expect(result.livingSurplus, 35000);
    });

    test('生活費を入れた後の手取り残 A 120,000 / B 250,000', () {
      expect(result.remainingAfterLiving, {memberA: 120000, memberB: 250000});
    });

    test('貯金も入れた後の自由に使えるお金 A 70,000 / B 160,000', () {
      expect(result.savingsContributions, {memberA: 50000, memberB: 90000});
      expect(result.remainingAfterSavings, {memberA: 70000, memberB: 160000});
    });

    test('年間貯金額 = 2,080,000（月140,000×12 + ボーナス入金400,000）', () {
      expect(result.annualBonusContributions, 400000);
      expect(result.monthlySavingsInflow, 140000);
      expect(result.annualSavings, 2080000);
    });

    test('家賃補助はBの手取り（自由に使えるお金）には足さない', () {
      // 補助は生活費口座の必要額を直接減らすお金。受け取る人の手取りに
      // 足すと二重に数えることになる。
      expect(result.remainingAfterLiving[memberB], 400000 - 150000);
    });
  });

  group('余剰の扱い', () {
    test('毎月貯金へ移す（toSavings）と年間貯金額 = 2,500,000', () {
      final result = BudgetCalculator.calculate(
        realCouplePlan(surplusHandling: SurplusHandling.toSavings),
      );

      expect(result.monthlySurplusToSavings, 35000);
      expect(result.monthlySavingsInflow, 175000);
      expect(result.annualSavings, 2500000);
    });

    test('toSavingsでも各自の自由に使えるお金は変わらない（移すのは口座の余剰）', () {
      final result = BudgetCalculator.calculate(
        realCouplePlan(surplusHandling: SurplusHandling.toSavings),
      );

      expect(result.remainingAfterSavings, {memberA: 70000, memberB: 160000});
    });

    test('不足しているときは貯金へ何も移さない（貯金から逆流もさせない）', () {
      final result = BudgetCalculator.calculate(realCouplePlan(
        surplusHandling: SurplusHandling.toSavings,
        contributionB: 100000,
      ));

      expect(result.livingSurplus, -15000);
      expect(result.monthlySurplusToSavings, 0);
      expect(result.annualSavings, 2080000);
    });
  });

  group('警告', () {
    test('入金額を減らして不足が出ると、不足額つきで警告する', () {
      // B 150,000 → 100,000 にすると入金合計 160,000 < 必要額 175,000
      final result = BudgetCalculator.calculate(realCouplePlan(contributionB: 100000));

      expect(result.livingSurplus, -15000);
      expect(result.hasWarning(BudgetWarningType.livingShortfall), isTrue);
      expect(
        result.warnings,
        contains(const BudgetWarning(type: BudgetWarningType.livingShortfall, amount: 15000)),
      );
    });

    test('ちょうど足りているときは不足の警告を出さない', () {
      final result = BudgetCalculator.calculate(realCouplePlan(contributionB: 115000));

      expect(result.livingSurplus, 0);
      expect(result.hasWarning(BudgetWarningType.livingShortfall), isFalse);
    });

    test('誰かの自由に使えるお金がマイナスなら、その人とマイナス額つきで警告する', () {
      // A: 手取り100,000 − 生活費60,000 − 貯金50,000 = −10,000
      final result = BudgetCalculator.calculate(realCouplePlan(takeHomeA: 100000));

      expect(result.remainingAfterSavings[memberA], -10000);
      expect(
        result.warnings,
        contains(const BudgetWarning(
          type: BudgetWarningType.negativeRemaining,
          memberId: memberA,
          amount: 10000,
        )),
      );
      // Bは問題ないので警告の対象にしない
      expect(
        result.warnings.where((w) => w.type == BudgetWarningType.negativeRemaining && w.memberId == memberB),
        isEmpty,
      );
    });

    test('口座に残す設定で余剰が必要額の15%を超えると「バッファが大きすぎる」', () {
      // 35,000 / 175,000 = 20%
      final result = BudgetCalculator.calculate(realCouplePlan());

      expect(
        result.warnings,
        contains(const BudgetWarning(type: BudgetWarningType.excessiveSurplus, amount: 35000)),
      );
    });

    test('余剰がちょうど15%なら警告しない（超えたときだけ）', () {
      // 必要額175,000の15% = 26,250 → B 141,250 で入金合計 201,250
      final result = BudgetCalculator.calculate(realCouplePlan(contributionB: 141250));

      expect(result.livingSurplus, 26250);
      expect(result.hasWarning(BudgetWarningType.excessiveSurplus), isFalse);
    });

    test('毎月貯金へ移す設定なら余剰が大きくても警告しない（貯金に回っているため）', () {
      final result = BudgetCalculator.calculate(
        realCouplePlan(surplusHandling: SurplusHandling.toSavings),
      );

      expect(result.hasWarning(BudgetWarningType.excessiveSurplus), isFalse);
    });

    test('閾値は定数で15%', () {
      expect(BudgetCalculator.excessiveSurplusPercent, 15);
    });
  });

  group('貯金の推移と目標', () {
    test('開始月〜期限の月まで月ごとに1点ずつ、ボーナス月は入金を足して積み上げる', () {
      final result = BudgetCalculator.calculate(realCouplePlan(
        currentBalance: 1000000,
        startDate: DateTime(2026, 11, 1),
        deadline: DateTime(2028, 10, 31),
      ));

      expect(result.projection, hasLength(24));
      expect(result.projection.first, const ProjectionPoint(YearMonth(2026, 11), 1140000));
      // 12月はボーナス入金200,000が乗る
      expect(result.projection[1], const ProjectionPoint(YearMonth(2026, 12), 1480000));
      expect(result.projection[2], const ProjectionPoint(YearMonth(2027, 1), 1620000));
      expect(result.projection.last.yearMonth, const YearMonth(2028, 10));
      // 1,000,000 + 140,000×24 + 200,000×4（2026/12, 2027/6, 2027/12, 2028/6）
      expect(result.projectedAtDeadline, 5160000);
      expect(result.startingBalance, 1000000);
    });

    test('期限までに未達なら警告し、間に合わせるための月額を出す', () {
      final result = BudgetCalculator.calculate(realCouplePlan(
        currentBalance: 1000000,
        startDate: DateTime(2026, 11, 1),
        deadline: DateTime(2028, 10, 31),
      ));

      expect(
        result.warnings,
        contains(const BudgetWarning(type: BudgetWarningType.goalNotReached, amount: 8000000 - 5160000)),
      );
      // (8,000,000 − 1,000,000 − 期間中のボーナス入金800,000) / 24ヶ月 = 258,333.3… → 切り上げ
      expect(result.requiredMonthlyToHitGoal, 258334);
    });

    test('出てきた必要月額にすると期限ちょうどで目標に届き、1円少ないと届かない', () {
      const required = 258334;
      final enough = BudgetCalculator.calculate(realCouplePlan(
        currentBalance: 1000000,
        startDate: DateTime(2026, 11, 1),
        deadline: DateTime(2028, 10, 31),
        savingsA: 50000,
        savingsB: required - 50000,
      ));
      final short = BudgetCalculator.calculate(realCouplePlan(
        currentBalance: 1000000,
        startDate: DateTime(2026, 11, 1),
        deadline: DateTime(2028, 10, 31),
        savingsA: 50000,
        savingsB: required - 50000 - 1,
      ));

      expect(enough.projectedAtDeadline, greaterThanOrEqualTo(8000000));
      expect(enough.hasWarning(BudgetWarningType.goalNotReached), isFalse);
      expect(short.projectedAtDeadline, lessThan(8000000));
      expect(short.hasWarning(BudgetWarningType.goalNotReached), isTrue);
    });

    test('必要月額は毎月貯金へ移す余剰も今のまま続く前提で差し引く', () {
      final result = BudgetCalculator.calculate(realCouplePlan(
        surplusHandling: SurplusHandling.toSavings,
        currentBalance: 1000000,
        startDate: DateTime(2026, 11, 1),
        deadline: DateTime(2028, 10, 31),
      ));

      // (8,000,000 − 1,000,000 − 800,000 − 余剰35,000×24) / 24 = 223,333.3… → 切り上げ
      expect(result.requiredMonthlyToHitGoal, 223334);
    });

    test('今の入金で間に合うなら未達の警告は出ず、必要月額は今の月額以下になる', () {
      final result = BudgetCalculator.calculate(realCouplePlan(
        targetAmount: 3000000,
        currentBalance: 1000000,
        startDate: DateTime(2026, 11, 1),
        deadline: DateTime(2028, 10, 31),
      ));

      expect(result.hasWarning(BudgetWarningType.goalNotReached), isFalse);
      // 必要月額は「2人の毎月の貯金入金の合計としていくら要るか」。
      // (3,000,000 − 1,000,000 − 800,000) / 24 = 50,000（今は140,000入れている）
      expect(result.requiredMonthlyToHitGoal, 50000);
      expect(result.requiredMonthlyToHitGoal, lessThan(result.totalMonthlySavingsContributions));
    });

    test('ボーナス入金だけで目標に届くなら必要月額は0', () {
      final result = BudgetCalculator.calculate(realCouplePlan(
        targetAmount: 1500000,
        currentBalance: 1000000,
        startDate: DateTime(2026, 11, 1),
        deadline: DateTime(2028, 10, 31),
      ));

      expect(result.requiredMonthlyToHitGoal, 0);
    });

    test('目標到達月は期限を過ぎていても見込みを出す', () {
      // 期限2029/10時点で6,240,000。そこから2030/8に8,000,000を超える。
      final result = BudgetCalculator.calculate(realCouplePlan());

      expect(result.projectedAtDeadline, 6240000);
      expect(result.goalAchievedDate, const YearMonth(2030, 8));
      // (8,000,000 − 期間中のボーナス入金1,200,000) / 36ヶ月 = 188,888.8… → 切り上げ
      expect(result.requiredMonthlyToHitGoal, 188889);
    });

    test('期限内に到達するならその月を返す', () {
      final result = BudgetCalculator.calculate(realCouplePlan(
        targetAmount: 1000000,
        startDate: DateTime(2026, 11, 1),
        deadline: DateTime(2028, 10, 31),
      ));

      // 11月 140,000 → 12月 480,000 → 1月 620,000 → 2月 760,000 → 3月 900,000 → 4月 1,040,000
      expect(result.goalAchievedDate, const YearMonth(2027, 4));
    });

    test('開始時点で既に目標額に届いていれば開始月を到達月とする', () {
      final result = BudgetCalculator.calculate(realCouplePlan(currentBalance: 9000000));

      expect(result.goalAchievedDate, const YearMonth(2026, 11));
      expect(result.requiredMonthlyToHitGoal, 0);
    });

    test('入金がまったく無いプランでは到達月はnull（永久に探さない）', () {
      final plan = realCouplePlan(savingsA: 0, savingsB: 0);
      final noBonus = plan.copyWith(
        savingsGoal: plan.savingsGoal.copyWith(bonusContributions: const []),
      );

      final result = BudgetCalculator.calculate(noBonus);

      expect(result.goalAchievedDate, isNull);
      expect(result.projectedAtDeadline, 0);
    });

    test('目標額が未設定（0）なら到達月・必要月額はnullで、未達の警告も出さない', () {
      final result = BudgetCalculator.calculate(realCouplePlan(targetAmount: 0));

      expect(result.goalAchievedDate, isNull);
      expect(result.requiredMonthlyToHitGoal, isNull);
      expect(result.hasWarning(BudgetWarningType.goalNotReached), isFalse);
    });

    test('期限が開始より前なら推移は空で、期限時点の残高は現在の残高のまま', () {
      final result = BudgetCalculator.calculate(realCouplePlan(
        currentBalance: 500000,
        startDate: DateTime(2026, 11, 1),
        deadline: DateTime(2026, 10, 31),
      ));

      expect(result.projection, isEmpty);
      expect(result.projectedAtDeadline, 500000);
      // 入金する月が無いので、いくら積んでも間に合わない
      expect(result.requiredMonthlyToHitGoal, isNull);
      expect(result.hasWarning(BudgetWarningType.goalNotReached), isTrue);
    });

    test('開始月と期限が同じ月なら1点だけ', () {
      final result = BudgetCalculator.calculate(realCouplePlan(
        startDate: DateTime(2026, 12, 1),
        deadline: DateTime(2026, 12, 25),
      ));

      expect(result.projection, [const ProjectionPoint(YearMonth(2026, 12), 340000)]);
    });
  });

  group('生活費口座の入金ルール', () {
    BudgetPlan withRule(LivingAccountRule rule, {List<BudgetOffset>? offsets}) {
      final plan = realCouplePlan();
      return plan.copyWith(livingAccount: rule, offsets: offsets);
    }

    test('比率指定: 必要額 + バッファを重みで分ける（40:60、バッファ10,000）', () {
      final result = BudgetCalculator.calculate(withRule(const LivingAccountRule(
        mode: LivingAccountMode.ratio,
        contributions: {memberA: 40, memberB: 60},
        bufferAmount: 10000,
      )));

      // (175,000 + 10,000) × 0.4 / 0.6
      expect(result.livingContributions, {memberA: 74000, memberB: 111000});
      expect(result.livingSurplus, 10000);
    });

    test('比率の重みは合計100でなくてもよい（1:2）', () {
      final result = BudgetCalculator.calculate(withRule(const LivingAccountRule(
        mode: LivingAccountMode.ratio,
        contributions: {memberA: 1, memberB: 2},
      )));

      // 175,000 / 3 = 58,333.3… → 端数1円は剰余の大きいBへ
      expect(result.livingContributions, {memberA: 58333, memberB: 116667});
      expect(result.totalLivingContributions, 175000);
      expect(result.livingSurplus, 0);
    });

    test('収入比: 手取りの比で分け、端数を配っても合計は必要額ちょうど', () {
      final result = BudgetCalculator.calculate(withRule(const LivingAccountRule(
        mode: LivingAccountMode.incomeProportional,
      )));

      // 175,000 × 180,000/580,000 = 54,310.3… / 175,000 × 400,000/580,000 = 120,689.6…
      expect(result.livingContributions, {memberA: 54310, memberB: 120690});
      expect(result.totalLivingContributions, 175000);
      expect(result.livingSurplus, 0);
      expect(result.hasWarning(BudgetWarningType.livingShortfall), isFalse);
    });

    test('収入比 + バッファ: 余剰はバッファと一致する', () {
      final result = BudgetCalculator.calculate(withRule(const LivingAccountRule(
        mode: LivingAccountMode.incomeProportional,
        bufferAmount: 20000,
      )));

      expect(result.totalLivingContributions, 195000);
      expect(result.livingSurplus, 20000);
    });

    test('固定額ではバッファを上乗せしない（入金額そのものを決めているため）', () {
      final result = BudgetCalculator.calculate(withRule(const LivingAccountRule(
        mode: LivingAccountMode.fixed,
        contributions: {memberA: 60000, memberB: 150000},
        bufferAmount: 50000,
      )));

      expect(result.totalLivingContributions, 210000);
      expect(result.livingSurplus, 35000);
    });

    test('補助が支出を上回っても比率配分の入金はマイナスにしない', () {
      final result = BudgetCalculator.calculate(withRule(
        const LivingAccountRule(mode: LivingAccountMode.incomeProportional),
        offsets: const [BudgetOffset(id: 'big', label: '大きな補助', monthlyAmount: 300000)],
      ));

      expect(result.netRequired, -95000);
      expect(result.livingContributions, {memberA: 0, memberB: 0});
      expect(result.livingSurplus, 95000);
    });

    test('固定額で金額が未設定のメンバーは0円として扱う', () {
      final result = BudgetCalculator.calculate(withRule(const LivingAccountRule(
        mode: LivingAccountMode.fixed,
        contributions: {memberB: 150000},
      )));

      expect(result.livingContributions, {memberA: 0, memberB: 150000});
    });
  });

  group('毎月の貯金を目標から自動で決める', () {
    // 期限に間に合う毎月の貯金（2人の合計）が258,334円になるプラン
    //   (8,000,000 − 1,000,000 − ボーナス入金800,000) / 24ヶ月 = 258,333.3… → 切り上げ
    BudgetPlan planWith(SavingsGoal Function(SavingsGoal) change,
        {SurplusHandling surplusHandling = SurplusHandling.keep}) {
      final plan = realCouplePlan(
        surplusHandling: surplusHandling,
        currentBalance: 1000000,
        startDate: DateTime(2026, 11, 1),
        deadline: DateTime(2028, 10, 31),
      );
      return plan.copyWith(savingsGoal: change(plan.savingsGoal));
    }

    void expectReachesGoal(BudgetResult result) {
      expect(result.projectedAtDeadline, greaterThanOrEqualTo(8000000));
      expect(result.hasWarning(BudgetWarningType.goalNotReached), isFalse);
    }

    test('比率指定: 必要額を比率（40:60）で分け、合計は必要額ちょうど', () {
      final result = BudgetCalculator.calculate(planWith((g) => g.copyWith(
        contributionMode: SavingsContributionMode.ratio,
        contributionWeights: {memberA: 40, memberB: 60},
      )));

      expect(result.requiredMonthlyToHitGoal, 258334);
      // 258,334 × 0.4 = 103,333.6 / × 0.6 = 155,000.4 → 端数1円は剰余の大きいAへ
      expect(result.savingsContributions, {memberA: 103334, memberB: 155000});
      expect(result.totalMonthlySavingsContributions, 258334);
      expectReachesGoal(result);
      // 自由に使えるお金も自動で決まった額で計算する
      expect(result.remainingAfterSavings, {memberA: 120000 - 103334, memberB: 250000 - 155000});
    });

    test('収入比: 必要額を手取りの比（18万:40万）で分ける', () {
      final result = BudgetCalculator.calculate(planWith((g) => g.copyWith(
        contributionMode: SavingsContributionMode.incomeProportional,
      )));

      // 258,334 × 180/580 = 80,172.6… / × 400/580 = 178,161.3… → 端数1円はAへ
      expect(result.savingsContributions, {memberA: 80173, memberB: 178161});
      expectReachesGoal(result);
    });

    test('固定＋残り: Aを5万円で固定すると、残りをBが負担する', () {
      final result = BudgetCalculator.calculate(planWith((g) => g.copyWith(
        contributionMode: SavingsContributionMode.fixed,
        fixedMemberIds: [memberA],
        monthlyContributions: {memberA: 50000, memberB: 999999},
      )));

      // Bの手入力値（999,999）は使わない
      expect(result.savingsContributions, {memberA: 50000, memberB: 208334});
      expectReachesGoal(result);
    });

    test('固定＋残り: 固定した額だけで必要額を超えるなら、残りの人は0（マイナスにしない）', () {
      final result = BudgetCalculator.calculate(planWith((g) => g.copyWith(
        contributionMode: SavingsContributionMode.fixed,
        fixedMemberIds: [memberA],
        monthlyContributions: {memberA: 300000},
      )));

      expect(result.savingsContributions, {memberA: 300000, memberB: 0});
    });

    test('固定＋残り: 誰も固定しなければ必要額を等分する', () {
      final result = BudgetCalculator.calculate(planWith((g) => g.copyWith(
        contributionMode: SavingsContributionMode.fixed,
        fixedMemberIds: const [],
      )));

      expect(result.savingsContributions, {memberA: 129167, memberB: 129167});
    });

    test('目標額や期限を変えると、自動で決まる額も変わる', () {
      SavingsGoal ratio(SavingsGoal g) => g.copyWith(
        contributionMode: SavingsContributionMode.ratio,
        contributionWeights: {memberA: 1, memberB: 1},
      );
      final base = BudgetCalculator.calculate(planWith(ratio));
      final higherTarget = BudgetCalculator.calculate(planWith((g) => ratio(g).copyWith(targetAmount: 9200000)));
      final laterDeadline = BudgetCalculator.calculate(
        planWith((g) => ratio(g).copyWith(deadline: DateTime(2029, 10, 31))),
      );

      // (9,200,000 − 1,000,000 − 800,000) / 24 = 308,333.3… → 308,334
      expect(higherTarget.totalMonthlySavingsContributions, 308334);
      expect(higherTarget.totalMonthlySavingsContributions, greaterThan(base.totalMonthlySavingsContributions));
      expect(laterDeadline.totalMonthlySavingsContributions, lessThan(base.totalMonthlySavingsContributions));
      expectReachesGoal(higherTarget);
      expectReachesGoal(laterDeadline);
    });

    test('余りを毎月貯金へ移す設定なら、その分を差し引いた額を割り振る', () {
      final result = BudgetCalculator.calculate(planWith(
        (g) => g.copyWith(
          contributionMode: SavingsContributionMode.ratio,
          contributionWeights: {memberA: 1, memberB: 1},
        ),
        surplusHandling: SurplusHandling.toSavings,
      ));

      // (8,000,000 − 1,000,000 − 800,000 − 余り35,000×24) / 24 = 223,333.3… → 223,334
      expect(result.savingsContributions, {memberA: 111667, memberB: 111667});
      expectReachesGoal(result);
    });

    test('ボーナス入金だけで届くなら、毎月の貯金は0になる', () {
      final result = BudgetCalculator.calculate(planWith((g) => g.copyWith(
        targetAmount: 1500000,
        contributionMode: SavingsContributionMode.incomeProportional,
      )));

      expect(result.savingsContributions, {memberA: 0, memberB: 0});
      expect(result.projectedAtDeadline, greaterThanOrEqualTo(1500000));
      expect(result.hasWarning(BudgetWarningType.goalNotReached), isFalse);
    });

    test('目標額が未設定なら自動では決められないので0（手入力の値は使わない）', () {
      final result = BudgetCalculator.calculate(planWith((g) => g.copyWith(
        targetAmount: 0,
        contributionMode: SavingsContributionMode.ratio,
        contributionWeights: {memberA: 1, memberB: 1},
      )));

      expect(result.savingsContributions, {memberA: 0, memberB: 0});
      expect(result.hasWarning(BudgetWarningType.goalNotReached), isFalse);
    });

    test('カスタムは従来どおり手入力の額を使う', () {
      final result = BudgetCalculator.calculate(planWith((g) => g));

      expect(result.savingsContributions, {memberA: 50000, memberB: 90000});
    });
  });

  group('allocateByWeights（端数の配り方）', () {
    test('合計は必ずtotalに一致する', () {
      for (final total in [0, 1, 99, 100000, 175001]) {
        final shares = BudgetCalculator.allocateByWeights(total, [3, 7, 11]);
        expect(shares.fold<int>(0, (a, b) => a + b), total, reason: 'total=$total');
      }
    });

    test('重みが全員0なら均等に分け、端数は並び順の早い人へ', () {
      expect(BudgetCalculator.allocateByWeights(10001, [0, 0]), [5001, 5000]);
    });

    test('同じ剰余なら並び順の早い人へ配る（結果が毎回同じになる）', () {
      expect(BudgetCalculator.allocateByWeights(3, [1, 1]), [2, 1]);
    });

    test('メンバーがいなければ空', () {
      expect(BudgetCalculator.allocateByWeights(1000, []), isEmpty);
    });
  });
}
