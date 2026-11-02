import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/budget_history_entry.dart';
import '../domain/budget_plan.dart';
import '../domain/budget_plan_diff.dart';

// ── BudgetPlan ⇔ Firestoreのドキュメント ──────────────────────
// ドメイン層をFirebaseから切り離しておくため、Timestampとの変換はここだけで行う。
//
// 読み込みは「壊れたドキュメントでも画面を落とさない」ことを優先する。
// 数値は int/double どちらで入っていても整数として読み、無いフィールドは
// 既定値にする（将来フィールドを足したときに古いドキュメントを読めるように）。
class BudgetPlanMapper {
  // ドキュメントの形を変えたときに古い形を見分けるための版数
  static const schemaVersion = 1;

  const BudgetPlanMapper._();

  // 内容のフィールドだけ（isActive・作成/更新者・日時はリポジトリが付ける）
  static Map<String, dynamic> contentToMap(BudgetPlan plan) => {
    'schemaVersion': schemaVersion,
    'name': plan.name,
    'members': [
      for (final m in plan.members)
        {
          'memberId':        m.memberId,
          'displayName':     m.displayName,
          'monthlyTakeHome': m.monthlyTakeHome,
          'bonuses': [
            for (final b in m.bonuses)
              {'month': b.month, 'amount': b.amount, 'payDay': b.payDay},
          ],
        },
    ],
    'sharedExpenses': [
      for (final e in plan.sharedExpenses)
        {
          'id':            e.id,
          'label':         e.label,
          'monthlyAmount': e.monthlyAmount,
          'category':      e.category.name,
        },
    ],
    'offsets': [
      for (final o in plan.offsets)
        {
          'id':            o.id,
          'label':         o.label,
          'monthlyAmount': o.monthlyAmount,
          'receivedBy':    o.receivedBy,
        },
    ],
    'livingAccount': {
      'mode':            plan.livingAccount.mode.name,
      'contributions':   plan.livingAccount.contributions,
      'bufferAmount':    plan.livingAccount.bufferAmount,
      'surplusHandling': plan.livingAccount.surplusHandling.name,
    },
    'savingsGoal': {
      'targetAmount':         plan.savingsGoal.targetAmount,
      'startDate':            Timestamp.fromDate(plan.savingsGoal.startDate),
      'deadline':             Timestamp.fromDate(plan.savingsGoal.deadline),
      'monthlyContributions': plan.savingsGoal.monthlyContributions,
      'bonusContributions': [
        for (final b in plan.savingsGoal.bonusContributions)
          {'memberId': b.memberId, 'month': b.month, 'amount': b.amount},
      ],
      'currentBalance':       plan.savingsGoal.currentBalance,
    },
  };

  static BudgetPlan fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      fromMap(doc.id, doc.data() ?? const {});

  static BudgetPlan fromMap(String id, Map<String, dynamic> d) {
    final living = _map(d['livingAccount']);
    final goal = _map(d['savingsGoal']);
    final now = DateTime.now();
    final startDate = _date(goal['startDate']) ?? DateTime(now.year, now.month, 1);
    return BudgetPlan(
      id:       id,
      name:     d['name'] as String? ?? '家計プラン',
      isActive: d['isActive'] == true,
      members: [
        for (final m in _list(d['members']))
          BudgetMember(
            memberId:        m['memberId'] as String? ?? '',
            displayName:     m['displayName'] as String? ?? '',
            monthlyTakeHome: _int(m['monthlyTakeHome']),
            bonuses: [
              for (final b in _list(m['bonuses']))
                Bonus(
                  month:  _month(b['month']),
                  amount: _int(b['amount']),
                  payDay: b['payDay'] == null ? null : _int(b['payDay']),
                ),
            ],
          ),
      ],
      sharedExpenses: [
        for (final (i, e) in _list(d['sharedExpenses']).indexed)
          SharedExpense(
            id:            e['id'] as String? ?? 'expense-$i',
            label:         e['label'] as String? ?? '',
            monthlyAmount: _int(e['monthlyAmount']),
            category:      ExpenseCategoryLabel.parse(e['category'] as String?),
          ),
      ],
      offsets: [
        for (final (i, o) in _list(d['offsets']).indexed)
          BudgetOffset(
            id:            o['id'] as String? ?? 'offset-$i',
            label:         o['label'] as String? ?? '',
            monthlyAmount: _int(o['monthlyAmount']),
            receivedBy:    o['receivedBy'] as String?,
          ),
      ],
      livingAccount: LivingAccountRule(
        mode: LivingAccountMode.values.firstWhere(
          (m) => m.name == living['mode'], orElse: () => LivingAccountMode.fixed),
        contributions: _intMap(living['contributions']),
        bufferAmount:  _int(living['bufferAmount']),
        surplusHandling: SurplusHandling.values.firstWhere(
          (s) => s.name == living['surplusHandling'], orElse: () => SurplusHandling.keep),
      ),
      savingsGoal: SavingsGoal(
        targetAmount: _int(goal['targetAmount']),
        startDate:    startDate,
        deadline:     _date(goal['deadline']) ?? DateTime(startDate.year + 2, startDate.month, 0),
        monthlyContributions: _intMap(goal['monthlyContributions']),
        bonusContributions: [
          for (final b in _list(goal['bonusContributions']))
            BonusContribution(
              memberId: b['memberId'] as String? ?? '',
              month:    _month(b['month']),
              amount:   _int(b['amount']),
            ),
        ],
        currentBalance: _int(goal['currentBalance']),
      ),
      createdBy: d['createdBy'] as String?,
      updatedBy: d['updatedBy'] as String?,
      createdAt: _date(d['createdAt']),
      updatedAt: _date(d['updatedAt']),
    );
  }

  static BudgetHistoryEntry historyFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return BudgetHistoryEntry(
      id:        doc.id,
      planId:    d['planId'] as String? ?? '',
      planName:  d['planName'] as String? ?? '',
      action:    BudgetHistoryActionLabel.parse(d['action'] as String?),
      changedBy: d['changedBy'] as String? ?? '',
      changedAt: _date(d['changedAt']),
      changes:   [for (final c in _list(d['changes'])) BudgetChange.fromMap(c)],
    );
  }

  // ── 型のゆるい読み取り ──
  static int _int(Object? v) => v is num ? v.round() : 0;

  static int _month(Object? v) {
    final m = _int(v);
    return m >= 1 && m <= 12 ? m : 1;
  }

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : const {};

  static List<Map<String, dynamic>> _list(Object? v) => v is List
      ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)]
      : const [];

  static Map<String, int> _intMap(Object? v) => v is Map
      ? {for (final e in v.entries) if (e.key is String) e.key as String: _int(e.value)}
      : const {};
}
