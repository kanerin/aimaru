import 'budget_plan.dart';
import 'money.dart';

// ── 家計プランの変更履歴（何を変えたか）──────────────────────
// 「誰がいつ何を変えたか」を残すため、保存前後のプランを比べて
// 人が読める差分の一覧を作る。誰が・いつ はリポジトリ側で付ける。
// 2人で家計を話し合うときに「家賃を変えたのはいつ？」を辿れるよう、
// 金額は変更前→変更後の両方を残す。

class BudgetChange {
  final String label;
  // before だけ → 削除、after だけ → 追加、両方 → 変更、どちらも無し → ラベルだけの出来事
  final String? before;
  final String? after;

  const BudgetChange(this.label, {this.before, this.after});

  String describe() {
    if (before == null && after == null) return label;
    if (before == null) return '$labelを追加（$after）';
    if (after == null) return '$labelを削除（$before）';
    return '$label: $before → $after';
  }

  Map<String, dynamic> toMap() => {
    'label':  label,
    'before': before,
    'after':  after,
  };

  factory BudgetChange.fromMap(Map<String, dynamic> map) => BudgetChange(
    map['label'] as String? ?? '',
    before: map['before'] as String?,
    after:  map['after'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is BudgetChange && other.label == label && other.before == before && other.after == after;

  @override
  int get hashCode => Object.hash(label, before, after);

  @override
  String toString() => describe();
}

String formatYearMonthJa(DateTime d) => '${d.year}年${d.month}月';
String formatDateJa(DateTime d) => '${d.year}年${d.month}月${d.day}日';

String _describeBonus(Bonus b) =>
    '${b.month}月 ${formatYen(b.amount)}${b.payDay != null ? '（${b.payDay}日支給）' : ''}';

List<BudgetChange> diffBudgetPlans(BudgetPlan before, BudgetPlan after) {
  final changes = <BudgetChange>[];
  void compare(String label, String a, String b) {
    if (a != b) changes.add(BudgetChange(label, before: a, after: b));
  }

  String nameOf(String? memberId) => after.memberById(memberId ?? '')?.displayName ??
      before.memberName(memberId);

  compare('プラン名', before.name, after.name);

  // ── メンバー（手取り・ボーナス）──
  for (final m in after.members) {
    final old = before.memberById(m.memberId);
    if (old == null) {
      changes.add(BudgetChange('メンバー「${m.displayName}」', after: formatYen(m.monthlyTakeHome)));
      continue;
    }
    compare('${old.displayName}の表示名', old.displayName, m.displayName);
    compare('${m.displayName}の手取り', formatYen(old.monthlyTakeHome), formatYen(m.monthlyTakeHome));
    final oldBonuses = old.bonuses.map(_describeBonus).join('、');
    final newBonuses = m.bonuses.map(_describeBonus).join('、');
    compare('${m.displayName}のボーナス',
        oldBonuses.isEmpty ? 'なし' : oldBonuses, newBonuses.isEmpty ? 'なし' : newBonuses);
  }
  for (final m in before.members) {
    if (after.memberById(m.memberId) == null) {
      changes.add(BudgetChange('メンバー「${m.displayName}」', before: formatYen(m.monthlyTakeHome)));
    }
  }

  // ── 共通支出（idで突き合わせる）──
  final beforeExpenses = {for (final e in before.sharedExpenses) e.id: e};
  final afterExpenseIds = {for (final e in after.sharedExpenses) e.id};
  for (final e in after.sharedExpenses) {
    final old = beforeExpenses[e.id];
    if (old == null) {
      changes.add(BudgetChange('共通支出「${e.label}」', after: formatYen(e.monthlyAmount)));
      continue;
    }
    compare('共通支出の名前', old.label, e.label);
    compare(e.label, formatYen(old.monthlyAmount), formatYen(e.monthlyAmount));
    compare('${e.label}のカテゴリ', old.category.label, e.category.label);
  }
  for (final e in before.sharedExpenses) {
    if (!afterExpenseIds.contains(e.id)) {
      changes.add(BudgetChange('共通支出「${e.label}」', before: formatYen(e.monthlyAmount)));
    }
  }
  if (_orderChanged(before.sharedExpenses.map((e) => e.id), after.sharedExpenses.map((e) => e.id))) {
    changes.add(const BudgetChange('共通支出の並び順を変更'));
  }

  // ── 補助 ──
  final beforeOffsets = {for (final o in before.offsets) o.id: o};
  final afterOffsetIds = {for (final o in after.offsets) o.id};
  for (final o in after.offsets) {
    final old = beforeOffsets[o.id];
    if (old == null) {
      changes.add(BudgetChange('補助「${o.label}」', after: formatYen(o.monthlyAmount)));
      continue;
    }
    compare('補助の名前', old.label, o.label);
    compare(o.label, formatYen(old.monthlyAmount), formatYen(o.monthlyAmount));
    compare('${o.label}の受け取り', nameOf(old.receivedBy), nameOf(o.receivedBy));
  }
  for (final o in before.offsets) {
    if (!afterOffsetIds.contains(o.id)) {
      changes.add(BudgetChange('補助「${o.label}」', before: formatYen(o.monthlyAmount)));
    }
  }
  if (_orderChanged(before.offsets.map((o) => o.id), after.offsets.map((o) => o.id))) {
    changes.add(const BudgetChange('補助の並び順を変更'));
  }

  // ── 生活費口座 ──
  final oldRule = before.livingAccount;
  final newRule = after.livingAccount;
  compare('生活費口座の入金ルール', oldRule.mode.label, newRule.mode.label);
  if (newRule.mode != LivingAccountMode.incomeProportional) {
    for (final m in after.members) {
      final a = oldRule.contributions[m.memberId] ?? 0;
      final b = newRule.contributions[m.memberId] ?? 0;
      if (newRule.mode == LivingAccountMode.fixed) {
        // 比率→固定額に切り替えたときは、変更前の値が金額ではないので比べない
        if (oldRule.mode == LivingAccountMode.fixed) {
          compare('${m.displayName}の生活費入金', formatYen(a), formatYen(b));
        } else {
          changes.add(BudgetChange('${m.displayName}の生活費入金', after: formatYen(b)));
        }
      } else {
        if (oldRule.mode == LivingAccountMode.ratio) {
          compare('${m.displayName}の生活費の比率', '$a', '$b');
        } else {
          changes.add(BudgetChange('${m.displayName}の生活費の比率', after: '$b'));
        }
      }
    }
  }
  compare('バッファ', formatYen(oldRule.bufferAmount), formatYen(newRule.bufferAmount));
  compare('生活費口座の余剰', oldRule.surplusHandling.label, newRule.surplusHandling.label);

  // ── 貯金 ──
  final oldGoal = before.savingsGoal;
  final newGoal = after.savingsGoal;
  compare('貯金の目標額', formatYen(oldGoal.targetAmount), formatYen(newGoal.targetAmount));
  compare('貯金の開始月', formatYearMonthJa(oldGoal.startDate), formatYearMonthJa(newGoal.startDate));
  compare('貯金の期限', formatDateJa(oldGoal.deadline), formatDateJa(newGoal.deadline));
  compare('現在の貯金残高', formatYen(oldGoal.currentBalance), formatYen(newGoal.currentBalance));
  compare('毎月の貯金の決め方', oldGoal.contributionMode.label, newGoal.contributionMode.label);
  // 決め方ごとに意味のある入力だけを記録する（比率指定・収入比の各自の額は
  // 目標から自動で決まる結果なので、入力の変更としては残さない）
  switch (newGoal.contributionMode) {
    case SavingsContributionMode.custom:
      for (final m in after.members) {
        compare('${m.displayName}の毎月の貯金',
            formatYen(oldGoal.monthlyContributions[m.memberId] ?? 0),
            formatYen(newGoal.monthlyContributions[m.memberId] ?? 0));
      }
    case SavingsContributionMode.ratio:
      for (final m in after.members) {
        compare('${m.displayName}の貯金の比率',
            '${oldGoal.contributionWeights[m.memberId] ?? 0}',
            '${newGoal.contributionWeights[m.memberId] ?? 0}');
      }
    case SavingsContributionMode.fixed:
      String fixedDesc(SavingsGoal g, String id) => g.fixedMemberIds.contains(id)
          ? '固定 ${formatYen(g.monthlyContributions[id] ?? 0)}'
          : '残りを負担';
      for (final m in after.members) {
        compare('${m.displayName}の毎月の貯金', fixedDesc(oldGoal, m.memberId), fixedDesc(newGoal, m.memberId));
      }
    case SavingsContributionMode.incomeProportional:
      break;
  }
  String describeBonusContributions(List<BonusContribution> list) => list.isEmpty
      ? 'なし'
      : list.map((b) => '${nameOf(b.memberId)} ${b.month}月 ${formatYen(b.amount)}').join('、');
  compare('ボーナスからの貯金',
      describeBonusContributions(oldGoal.bonusContributions),
      describeBonusContributions(newGoal.bonusContributions));

  return changes;
}

// 両方に残っている項目だけで比べた並び順が変わったか（追加・削除は別に記録するので除く）
bool _orderChanged(Iterable<String> beforeIds, Iterable<String> afterIds) {
  final afterSet = afterIds.toSet();
  final beforeSet = beforeIds.toSet();
  final a = beforeIds.where(afterSet.contains).toList();
  final b = afterIds.where(beforeSet.contains).toList();
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}
