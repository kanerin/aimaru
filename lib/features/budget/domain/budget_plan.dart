// ── 2人の家計プラン（入力側のモデル）──────────────────────
// UI・Firebaseのどちらにも依存しない純粋なDartのクラス。Firestoreとの
// 変換は data/budget_plan_mapper.dart が担う（Timestampを扱うため）。
//
// 金額はすべて整数（円）で持つ。小数を許すと比率配分の端数や
// 月次の積み上げで誤差が出て、2人で「1円合わない」が起きるため。
//
// 特定のカップルの金額を前提にしない汎用の枠組みにしてあり、
// 共通支出・補助・ボーナスは件数も内容も自由に増減できる。

// 生活費口座への入金ルール
enum LivingAccountMode {
  // 各自が決まった額を入れる（contributions = 金額）
  fixed,
  // 決めた比率で必要額（+バッファ）を分ける（contributions = 比率の重み）
  ratio,
  // 手取りの比で必要額（+バッファ）を分ける（contributionsは使わない）
  incomeProportional,
}

extension LivingAccountModeLabel on LivingAccountMode {
  String get label => switch (this) {
    LivingAccountMode.fixed              => '固定額',
    LivingAccountMode.ratio              => '比率指定',
    LivingAccountMode.incomeProportional => '収入比',
  };
}

// 生活費口座に残った余剰の扱い
enum SurplusHandling {
  keep,      // 口座に残す（予備費として積み上がる）
  toSavings, // 毎月貯金口座へ移す
}

extension SurplusHandlingLabel on SurplusHandling {
  String get label => switch (this) {
    SurplusHandling.keep      => '口座に残す',
    SurplusHandling.toSavings => '毎月貯金へ移す',
  };
}

// 共通支出のカテゴリ。Firestoreには name を文字列で保存し、
// 知らない値（将来の追加など）は other として読む。
enum ExpenseCategory {
  housing,
  utilities,
  food,
  communication,
  insurance,
  transport,
  leisure,
  other,
}

extension ExpenseCategoryLabel on ExpenseCategory {
  String get label => switch (this) {
    ExpenseCategory.housing       => '住居',
    ExpenseCategory.utilities     => '水道・光熱',
    ExpenseCategory.food          => '食費・日用品',
    ExpenseCategory.communication => '通信',
    ExpenseCategory.insurance     => '保険',
    ExpenseCategory.transport     => '車・交通',
    ExpenseCategory.leisure       => 'レジャー・交際',
    ExpenseCategory.other         => 'その他',
  };

  String get emoji => switch (this) {
    ExpenseCategory.housing       => '🏠',
    ExpenseCategory.utilities     => '💡',
    ExpenseCategory.food          => '🍚',
    ExpenseCategory.communication => '📱',
    ExpenseCategory.insurance     => '🛡',
    ExpenseCategory.transport     => '🚃',
    ExpenseCategory.leisure       => '🎡',
    ExpenseCategory.other         => '📦',
  };

  static ExpenseCategory parse(String? name) =>
      ExpenseCategory.values.firstWhere((c) => c.name == name, orElse: () => ExpenseCategory.other);
}

// ── メンバーの収入側 ─────────────────────────────────
class Bonus {
  final int month;   // 支給月（1〜12）
  final int amount;  // 手取りの支給額
  // 支給日（1〜31、任意）。カレンダーにボーナスを表示するときだけ使う。
  // 未設定ならその月の1日に「ボーナス月」として表示する。
  final int? payDay;

  const Bonus({required this.month, required this.amount, this.payDay});

  Bonus copyWith({int? month, int? amount, int? payDay, bool clearPayDay = false}) => Bonus(
    month:  month ?? this.month,
    amount: amount ?? this.amount,
    payDay: clearPayDay ? null : (payDay ?? this.payDay),
  );

  @override
  bool operator ==(Object other) =>
      other is Bonus && other.month == month && other.amount == amount && other.payDay == payDay;

  @override
  int get hashCode => Object.hash(month, amount, payDay);
}

class BudgetMember {
  // カップルのメンバーのuid。通知の宛先や「自分/パートナー」の判定に使う。
  final String memberId;
  final String displayName;
  final int monthlyTakeHome; // 手取り月収
  final List<Bonus> bonuses;

  const BudgetMember({
    required this.memberId,
    required this.displayName,
    required this.monthlyTakeHome,
    this.bonuses = const [],
  });

  BudgetMember copyWith({String? displayName, int? monthlyTakeHome, List<Bonus>? bonuses}) =>
      BudgetMember(
        memberId:        memberId,
        displayName:     displayName ?? this.displayName,
        monthlyTakeHome: monthlyTakeHome ?? this.monthlyTakeHome,
        bonuses:         bonuses ?? this.bonuses,
      );
}

// ── 支出側 ─────────────────────────────────────────
class SharedExpense {
  final String id; // 並び替え・削除・変更履歴で項目を同定するためのID
  final String label;
  final int monthlyAmount;
  final ExpenseCategory category;

  const SharedExpense({
    required this.id,
    required this.label,
    required this.monthlyAmount,
    this.category = ExpenseCategory.other,
  });

  SharedExpense copyWith({String? label, int? monthlyAmount, ExpenseCategory? category}) =>
      SharedExpense(
        id:            id,
        label:         label ?? this.label,
        monthlyAmount: monthlyAmount ?? this.monthlyAmount,
        category:      category ?? this.category,
      );
}

// 共通支出を減らす要素（家賃補助など）。
//
// 補助は「各自の手取りとは別に、生活費口座の必要額を直接減らすお金」として
// 扱う。手取り（monthlyTakeHome）には含めない前提なので、受け取る人の
// 自由に使えるお金は増えない。receivedByは誰が受け取っているかの表示用。
class BudgetOffset {
  final String id;
  final String label;
  final int monthlyAmount;
  final String? receivedBy; // memberId（2人共通・不明ならnull）

  const BudgetOffset({
    required this.id,
    required this.label,
    required this.monthlyAmount,
    this.receivedBy,
  });

  BudgetOffset copyWith({
    String? label,
    int? monthlyAmount,
    String? receivedBy,
    bool clearReceivedBy = false,
  }) =>
      BudgetOffset(
        id:            id,
        label:         label ?? this.label,
        monthlyAmount: monthlyAmount ?? this.monthlyAmount,
        receivedBy:    clearReceivedBy ? null : (receivedBy ?? this.receivedBy),
      );
}

// ── 生活費口座の入金ルール ──────────────────────────────
class LivingAccountRule {
  final LivingAccountMode mode;
  // memberId → 金額（fixed）または比率の重み（ratio）。
  // 比率の重みは合計が100である必要はない（40/60でも2/3でもよい）。
  final Map<String, int> contributions;
  // 必要額に上乗せする予備費。fixed以外のモードでだけ使う
  // （fixedは入金額そのものを決めているので、余剰は結果として決まる）。
  final int bufferAmount;
  final SurplusHandling surplusHandling;

  const LivingAccountRule({
    this.mode = LivingAccountMode.fixed,
    this.contributions = const {},
    this.bufferAmount = 0,
    this.surplusHandling = SurplusHandling.keep,
  });

  LivingAccountRule copyWith({
    LivingAccountMode? mode,
    Map<String, int>? contributions,
    int? bufferAmount,
    SurplusHandling? surplusHandling,
  }) =>
      LivingAccountRule(
        mode:            mode ?? this.mode,
        contributions:   contributions ?? this.contributions,
        bufferAmount:    bufferAmount ?? this.bufferAmount,
        surplusHandling: surplusHandling ?? this.surplusHandling,
      );
}

// ── 貯金目標 ───────────────────────────────────────
class BonusContribution {
  final String memberId;
  final int month; // 入金する月（1〜12、毎年）
  final int amount;

  const BonusContribution({required this.memberId, required this.month, required this.amount});

  BonusContribution copyWith({String? memberId, int? month, int? amount}) => BonusContribution(
    memberId: memberId ?? this.memberId,
    month:    month ?? this.month,
    amount:   amount ?? this.amount,
  );
}

class SavingsGoal {
  // 目標額。0以下は「目標未設定」として扱い、達成判定・警告を出さない。
  final int targetAmount;
  // 計算は月単位。startDateの月〜deadlineの月の各月に入金があるものとして積み上げる。
  final DateTime startDate;
  final DateTime deadline;
  final Map<String, int> monthlyContributions; // memberId → 毎月の貯金額
  final List<BonusContribution> bonusContributions;
  // startDate時点（その月の入金前）の貯金残高
  final int currentBalance;

  const SavingsGoal({
    required this.targetAmount,
    required this.startDate,
    required this.deadline,
    this.monthlyContributions = const {},
    this.bonusContributions = const [],
    this.currentBalance = 0,
  });

  bool get hasTarget => targetAmount > 0;

  SavingsGoal copyWith({
    int? targetAmount,
    DateTime? startDate,
    DateTime? deadline,
    Map<String, int>? monthlyContributions,
    List<BonusContribution>? bonusContributions,
    int? currentBalance,
  }) =>
      SavingsGoal(
        targetAmount:         targetAmount ?? this.targetAmount,
        startDate:            startDate ?? this.startDate,
        deadline:             deadline ?? this.deadline,
        monthlyContributions: monthlyContributions ?? this.monthlyContributions,
        bonusContributions:   bonusContributions ?? this.bonusContributions,
        currentBalance:       currentBalance ?? this.currentBalance,
      );
}

// ── プラン本体 ─────────────────────────────────────
class BudgetPlan {
  // Firestoreのドキュメントid。まだ保存していない下書き（シミュレーションの
  // 複製直後など）は空文字。
  final String id;
  final String name;
  // 確定プランかどうか（1カップル1つ）。falseのものはシミュレーション（仮案）。
  final bool isActive;
  final List<BudgetMember> members;
  final List<SharedExpense> sharedExpenses;
  final List<BudgetOffset> offsets;
  final LivingAccountRule livingAccount;
  final SavingsGoal savingsGoal;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BudgetPlan({
    this.id = '',
    required this.name,
    this.isActive = false,
    required this.members,
    this.sharedExpenses = const [],
    this.offsets = const [],
    this.livingAccount = const LivingAccountRule(),
    required this.savingsGoal,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  bool get isSaved => id.isNotEmpty;

  BudgetMember? memberById(String memberId) {
    for (final m in members) {
      if (m.memberId == memberId) return m;
    }
    return null;
  }

  String memberName(String? memberId, {String fallback = '2人'}) =>
      memberId == null ? fallback : (memberById(memberId)?.displayName ?? fallback);

  BudgetPlan copyWith({
    String? id,
    String? name,
    bool? isActive,
    List<BudgetMember>? members,
    List<SharedExpense>? sharedExpenses,
    List<BudgetOffset>? offsets,
    LivingAccountRule? livingAccount,
    SavingsGoal? savingsGoal,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      BudgetPlan(
        id:             id ?? this.id,
        name:           name ?? this.name,
        isActive:       isActive ?? this.isActive,
        members:        members ?? this.members,
        sharedExpenses: sharedExpenses ?? this.sharedExpenses,
        offsets:        offsets ?? this.offsets,
        livingAccount:  livingAccount ?? this.livingAccount,
        savingsGoal:    savingsGoal ?? this.savingsGoal,
        createdBy:      createdBy ?? this.createdBy,
        updatedBy:      updatedBy ?? this.updatedBy,
        createdAt:      createdAt ?? this.createdAt,
        updatedAt:      updatedAt ?? this.updatedAt,
      );

  // シミュレーション用の複製。保存前の下書きとして id・確定フラグ・
  // 作成/更新者を外す（保存時にリポジトリが付け直す）。
  BudgetPlan duplicateAsDraft({required String name}) => BudgetPlan(
    name:           name,
    members:        members,
    sharedExpenses: sharedExpenses,
    offsets:        offsets,
    livingAccount:  livingAccount,
    savingsGoal:    savingsGoal,
  );

  // 新しく家計プランを作るときのひな型。金額は0にしておき、2人で埋めてもらう。
  // 共通支出はよくある4項目だけ並べておく（追加・削除は自由）。
  factory BudgetPlan.template({
    required List<({String memberId, String displayName})> members,
    required DateTime today,
    String name = '確定プラン',
  }) {
    final start = DateTime(today.year, today.month, 1);
    return BudgetPlan(
      name: name,
      members: [
        for (final m in members)
          BudgetMember(memberId: m.memberId, displayName: m.displayName, monthlyTakeHome: 0),
      ],
      sharedExpenses: const [
        SharedExpense(id: 'rent',      label: '家賃',         monthlyAmount: 0, category: ExpenseCategory.housing),
        SharedExpense(id: 'water',     label: '水道',         monthlyAmount: 0, category: ExpenseCategory.utilities),
        SharedExpense(id: 'energy',    label: '光熱費',       monthlyAmount: 0, category: ExpenseCategory.utilities),
        SharedExpense(id: 'groceries', label: '食費・日用品', monthlyAmount: 0, category: ExpenseCategory.food),
      ],
      livingAccount: LivingAccountRule(
        contributions: {for (final m in members) m.memberId: 0},
      ),
      savingsGoal: SavingsGoal(
        targetAmount: 0,
        startDate: start,
        // 目標期限の初期値は開始から2年後の月末。あとから自由に変えられる。
        deadline: DateTime(start.year + 2, start.month, 0),
        monthlyContributions: {for (final m in members) m.memberId: 0},
      ),
    );
  }
}
