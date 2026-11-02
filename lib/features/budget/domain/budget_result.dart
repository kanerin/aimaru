import 'year_month.dart';

// ── 計算結果（出力側のモデル）────────────────────────────
// BudgetCalculator.calculate が BudgetPlan から作る。UIはこれを表示するだけで、
// 金額の計算を画面側に持たない（同じ数字が画面ごとに食い違うのを防ぐ）。

class ProjectionPoint {
  final YearMonth yearMonth;
  // その月の入金（毎月の貯金・ボーナス入金・余剰の移し替え）を反映した月末残高
  final int balance;

  const ProjectionPoint(this.yearMonth, this.balance);

  @override
  bool operator ==(Object other) =>
      other is ProjectionPoint && other.yearMonth == yearMonth && other.balance == balance;

  @override
  int get hashCode => Object.hash(yearMonth, balance);

  @override
  String toString() => 'ProjectionPoint($yearMonth, $balance)';
}

enum BudgetWarningType {
  // 生活費口座への入金合計が必要額に届かない
  livingShortfall,
  // 誰かの「自由に使えるお金」（手取り − 生活費 − 貯金）がマイナス
  negativeRemaining,
  // 期限時点の見込み残高が目標額に届かない
  goalNotReached,
  // 生活費口座の余剰が必要額に対して大きすぎる（口座に残す設定のときだけ）
  excessiveSurplus,
}

class BudgetWarning {
  final BudgetWarningType type;
  // negativeRemaining のときだけ、対象のメンバー
  final String? memberId;
  // 警告に対応する金額（いずれも正の値）:
  //   livingShortfall   … 不足額（月）
  //   negativeRemaining … マイナス分（月）
  //   goalNotReached    … 期限時点で目標に足りない額
  //   excessiveSurplus  … 余剰額（月）
  final int amount;

  const BudgetWarning({required this.type, this.memberId, required this.amount});

  @override
  bool operator ==(Object other) =>
      other is BudgetWarning && other.type == type && other.memberId == memberId && other.amount == amount;

  @override
  int get hashCode => Object.hash(type, memberId, amount);

  @override
  String toString() => 'BudgetWarning($type, memberId: $memberId, amount: $amount)';
}

class BudgetResult {
  // ── 生活費口座 ──
  final int totalSharedExpenses;         // 共通支出の合計
  final int totalOffsets;                // 補助の合計
  final int netRequired;                 // 共通支出 − 補助（生活費口座に必要な額）
  final Map<String, int> livingContributions; // memberId → 生活費口座への入金額
  final int totalLivingContributions;    // 入金の合計
  final int livingSurplus;               // 入金合計 − 必要額（マイナスなら不足）

  // ── 各自のお金 ──
  final Map<String, int> remainingAfterLiving;  // 手取り − 生活費入金
  final Map<String, int> savingsContributions;  // memberId → 毎月の貯金入金
  final Map<String, int> remainingAfterSavings; // さらに貯金を引いた「自由に使えるお金」

  // ── 貯金 ──
  // 生活費口座の余剰のうち、毎月貯金へ移す額（surplusHandling=toSavings かつ余剰があるとき）
  final int monthlySurplusToSavings;
  // 毎月貯金口座に入る額（各自の貯金入金 + 余剰の移し替え。ボーナス入金は含まない）
  final int monthlySavingsInflow;
  final int annualBonusContributions;    // 年間のボーナス入金の合計
  final int annualSavings;               // 月額×12 + ボーナス入金 + 余剰の移し替え×12

  final int startingBalance;             // 開始時点の貯金残高
  final List<ProjectionPoint> projection; // startDate〜deadline の月次推移
  final int projectedAtDeadline;         // 期限時点の見込み残高
  // 目標に到達する見込みの月（期限を過ぎてからの到達も含む）。目標未設定・到達しない場合はnull
  final YearMonth? goalAchievedDate;
  // 期限に間に合わせるために必要な「2人の毎月の貯金入金の合計」。
  // 現行のボーナス入金と余剰の移し替えは今のまま続く前提で差し引く。
  // 目標未設定、または期限が開始より前で間に合わせようがない場合はnull。
  final int? requiredMonthlyToHitGoal;

  final List<BudgetWarning> warnings;

  const BudgetResult({
    required this.totalSharedExpenses,
    required this.totalOffsets,
    required this.netRequired,
    required this.livingContributions,
    required this.totalLivingContributions,
    required this.livingSurplus,
    required this.remainingAfterLiving,
    required this.savingsContributions,
    required this.remainingAfterSavings,
    required this.monthlySurplusToSavings,
    required this.monthlySavingsInflow,
    required this.annualBonusContributions,
    required this.annualSavings,
    required this.startingBalance,
    required this.projection,
    required this.projectedAtDeadline,
    required this.goalAchievedDate,
    required this.requiredMonthlyToHitGoal,
    required this.warnings,
  });

  // 2人の毎月の貯金入金の合計（余剰の移し替えを含まない）
  int get totalMonthlySavingsContributions =>
      savingsContributions.values.fold(0, (sum, v) => sum + v);

  bool hasWarning(BudgetWarningType type) => warnings.any((w) => w.type == type);
}
