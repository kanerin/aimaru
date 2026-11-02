import 'package:flutter/material.dart';

import '../../../utils/app_theme.dart';
import '../data/budget_plan_repository.dart';
import '../domain/budget_calculator.dart';
import '../domain/budget_plan.dart';
import '../domain/budget_plan_diff.dart';
import '../domain/budget_result.dart';
import '../domain/money.dart';
import 'budget_items_edit_screen.dart';
import 'budget_summary_cards.dart';
import 'budget_widgets.dart';

enum BudgetEditorMode {
  // 確定プランそのものを編集する（保存すると相手に通知される）
  editActive,
  // 確定プランを複製した仮案を編集する（確定プランには影響しない）
  simulation,
}

// ── 家計プランの編集・シミュレーション ─────────────────────────
// 各金額はスライダー + 数値入力で変えられ、変えるたびに BudgetCalculator で
// 即座に再計算する。baseline（確定プラン）を渡すと、結果の各数字に
// 確定プランとの差分（+5,000円 など）を出す。
//
// 画面上の変更は「保存」するまでFirestoreに書かない（スライダーを動かすたびに
// 書き込むと、変更履歴と相手への通知が大量に発生するため）。
class BudgetPlanEditorScreen extends StatefulWidget {
  final String coupleId;
  // 編集するプラン。未保存の下書き（id空）なら、保存時に新規作成する。
  final BudgetPlan plan;
  // 差分の比較対象（確定プラン）。新しく作るときなど比較対象が無ければnull。
  final BudgetPlan? baseline;
  final BudgetEditorMode mode;
  // テスト用の注入ポイント
  final BudgetPlanRepository? repositoryOverride;
  final Future<DateTime?> Function(BuildContext context, DateTime initial)? pickDateOverride;

  const BudgetPlanEditorScreen({
    super.key,
    required this.coupleId,
    required this.plan,
    required this.mode,
    this.baseline,
    this.repositoryOverride,
    this.pickDateOverride,
  });

  @override
  State<BudgetPlanEditorScreen> createState() => _BudgetPlanEditorScreenState();
}

class _BudgetPlanEditorScreenState extends State<BudgetPlanEditorScreen> {
  BudgetPlanRepository? _repoInstance;
  BudgetPlanRepository get _repo =>
      _repoInstance ??= widget.repositoryOverride ?? BudgetPlanRepository();

  late BudgetPlan _draft = widget.plan;
  // 最後に保存した状態（変更履歴の差分の「変更前」に使う）
  late BudgetPlan _saved = widget.plan;
  bool _dirty = false;
  bool _busy = false;
  late final _nameController = TextEditingController(text: widget.plan.name);

  late final BudgetResult? _baselineResult =
      widget.baseline == null ? null : BudgetCalculator.calculate(widget.baseline!);

  bool get _isSimulation => widget.mode == BudgetEditorMode.simulation;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _update(BudgetPlan next) => setState(() {
    _draft = next;
    _dirty = true;
  });

  void _updateMember(String memberId, BudgetMember Function(BudgetMember) change) => _update(_draft.copyWith(
    members: [for (final m in _draft.members) m.memberId == memberId ? change(m) : m],
  ));

  void _updateLiving(LivingAccountRule Function(LivingAccountRule) change) =>
      _update(_draft.copyWith(livingAccount: change(_draft.livingAccount)));

  void _updateGoal(SavingsGoal Function(SavingsGoal) change) =>
      _update(_draft.copyWith(savingsGoal: change(_draft.savingsGoal)));

  void _showSnack(String message, {ScaffoldMessengerState? messenger}) {
    final m = messenger ?? (mounted ? ScaffoldMessenger.of(context) : null);
    m?.showSnackBar(SnackBar(content: Text(message)));
  }

  // 下書きを保存する（未保存なら作成、保存済みなら差分を記録して更新）。
  Future<void> _persist({required bool activateIfNew}) async {
    if (!_draft.isSaved) {
      _draft = await _repo.createPlan(widget.coupleId, _draft, activate: activateIfNew);
    } else {
      _draft = await _repo.updatePlan(widget.coupleId, before: _saved, after: _draft);
    }
    _saved = _draft;
    _dirty = false;
  }

  Future<void> _save() async {
    if (_draft.name.trim().isEmpty) {
      _showSnack('プラン名を入力してください');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // 確定プランの編集で、まだ保存していないもの（最初のプラン）は確定として作る
      await _persist(activateIfNew: !_isSimulation);
      if (!mounted) return;
      if (_isSimulation) {
        setState(() {});
        _showSnack('シミュレーションを保存しました', messenger: messenger);
      } else {
        Navigator.of(context).pop();
        _showSnack('確定プランを保存しました', messenger: messenger);
      }
    } catch (e) {
      debugPrint('[家計] 保存に失敗: $e');
      _showSnack('保存に失敗しました。もう一度お試しください', messenger: messenger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate() async {
    if (_draft.name.trim().isEmpty) {
      _showSnack('プラン名を入力してください');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('確定プランにする'),
        content: Text(
          '「${_draft.name}」を2人の確定プランにします。'
          '今の確定プランはシミュレーションとして残ります。パートナーにも通知されます。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確定にする')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (!_draft.isSaved) {
        await _persist(activateIfNew: true);
      } else {
        if (_dirty) await _persist(activateIfNew: false);
        await _repo.activatePlan(widget.coupleId, _draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack('「${_draft.name}」を確定プランにしました', messenger: messenger);
    } catch (e) {
      debugPrint('[家計] 確定に失敗: $e');
      _showSnack('確定プランにできませんでした。もう一度お試しください', messenger: messenger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openItemsEditor() async {
    final edited = await Navigator.of(context).push<BudgetPlan>(MaterialPageRoute(
      builder: (_) => BudgetItemsEditScreen(plan: _draft),
    ));
    if (edited != null && mounted) _update(edited);
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('変更を破棄しますか？'),
        content: const Text('保存していない変更があります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('編集を続ける')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('破棄する', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate(DateTime initial, ValueChanged<DateTime> onPicked) async {
    final picked = widget.pickDateOverride != null
        ? await widget.pickDateOverride!(context, initial)
        : await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
    if (picked != null) onPicked(picked);
  }

  String get _title {
    if (_isSimulation) return 'シミュレーション';
    return _draft.isSaved ? '確定プランを編集' : '家計プランを作る';
  }

  @override
  Widget build(BuildContext context) {
    final result = BudgetCalculator.calculate(_draft);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: AppColors.navy,
        appBar: AppBar(
          title: Text(_title),
          actions: [
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: '項目の追加・削除・並び替え',
              onPressed: _busy ? null : _openItemsEditor,
            ),
          ],
        ),
        body: Column(
          children: [
            _ResultPanel(plan: _draft, result: result, baseline: _baselineResult),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  _buildNameField(),
                  const SizedBox(height: 14),
                  _buildIncomeSection(),
                  _buildExpenseSection(),
                  _buildOffsetSection(),
                  _buildLivingSection(result),
                  _buildSavingsSection(),
                  BudgetWarningsCard(plan: _draft, result: result),
                  MonthlyFlowCard(plan: _draft, result: result, baseline: _baselineResult),
                  SavingsGoalCard(plan: _draft, result: result, baseline: _baselineResult),
                  LivingAccountCard(plan: _draft, result: result, baseline: _baselineResult),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(
              color: AppColors.navyCard,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: _isSimulation
                ? Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _save,
                        child: Text(_draft.isSaved && !_dirty ? '保存済み' : '保存'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _activate,
                        child: const Text('このプランを確定にする'),
                      ),
                    ),
                  ])
                : ElevatedButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_draft.isSaved ? '保存する' : 'この内容で作る'),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameField() => TextField(
    controller: _nameController,
    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
    decoration: const InputDecoration(
      labelText: 'プラン名',
      hintText: '例: 家賃上げた場合',
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    onChanged: (v) => _update(_draft.copyWith(name: v.trim())),
  );

  Widget _editItemsButton() => TextButton(
    onPressed: _busy ? null : _openItemsEditor,
    child: const Text('項目を編集', style: TextStyle(fontSize: 12)),
  );

  Widget _buildIncomeSection() {
    final base = widget.baseline;
    return BudgetSectionCard(
      title: '手取り（月）',
      child: Column(children: [
        for (final m in _draft.members)
          AmountSliderField(
            key: ValueKey('takehome-${m.memberId}'),
            label: m.displayName,
            value: m.monthlyTakeHome,
            max: 1000000,
            baselineValue: base?.memberById(m.memberId)?.monthlyTakeHome,
            onChanged: (v) => _updateMember(m.memberId, (x) => x.copyWith(monthlyTakeHome: v)),
          ),
      ]),
    );
  }

  Widget _buildExpenseSection() {
    final baseExpenses = {for (final e in widget.baseline?.sharedExpenses ?? const <SharedExpense>[]) e.id: e};
    return BudgetSectionCard(
      title: '共通の支出（月）',
      trailing: _editItemsButton(),
      child: Column(children: [
        if (_draft.sharedExpenses.isEmpty)
          const Text('項目がありません。「項目を編集」から追加できます',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        for (final e in _draft.sharedExpenses)
          AmountSliderField(
            key: ValueKey('expense-${e.id}'),
            label: '${e.category.emoji} ${e.label}',
            value: e.monthlyAmount,
            baselineValue: baseExpenses[e.id]?.monthlyAmount,
            higherIsBetter: false,
            onChanged: (v) => _update(_draft.copyWith(sharedExpenses: [
              for (final x in _draft.sharedExpenses) x.id == e.id ? x.copyWith(monthlyAmount: v) : x,
            ])),
          ),
      ]),
    );
  }

  Widget _buildOffsetSection() {
    final baseOffsets = {for (final o in widget.baseline?.offsets ?? const <BudgetOffset>[]) o.id: o};
    return BudgetSectionCard(
      title: '補助（家賃補助など、月）',
      trailing: _editItemsButton(),
      child: Column(children: [
        if (_draft.offsets.isEmpty)
          const Text('家賃補助のように共通の支出を減らすお金があれば「項目を編集」から追加できます',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.5)),
        for (final o in _draft.offsets)
          AmountSliderField(
            key: ValueKey('offset-${o.id}'),
            label: '${o.label}${o.receivedBy != null ? '（${_draft.memberName(o.receivedBy)}）' : ''}',
            value: o.monthlyAmount,
            max: 100000,
            baselineValue: baseOffsets[o.id]?.monthlyAmount,
            onChanged: (v) => _update(_draft.copyWith(offsets: [
              for (final x in _draft.offsets) x.id == o.id ? x.copyWith(monthlyAmount: v) : x,
            ])),
          ),
      ]),
    );
  }

  Widget _buildLivingSection(BudgetResult result) {
    final rule = _draft.livingAccount;
    final baseRule = widget.baseline?.livingAccount;
    final sameModeAsBase = baseRule?.mode == rule.mode;
    final explanation = switch (rule.mode) {
      LivingAccountMode.fixed => '各自が決まった額を生活費口座に入れます。余りや不足は結果として決まります。',
      LivingAccountMode.ratio => '必要額（＋バッファ）を決めた比率で分けます。比率の合計は100でなくても構いません。',
      LivingAccountMode.incomeProportional => '必要額（＋バッファ）を2人の手取りの比で分けます。',
    };
    return BudgetSectionCard(
      title: '生活費口座への入金',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<LivingAccountMode>(
            segments: [
              for (final mode in LivingAccountMode.values)
                ButtonSegment(value: mode, label: Text(mode.label, style: const TextStyle(fontSize: 12))),
            ],
            selected: {rule.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _updateLiving((r) => r.copyWith(mode: s.first)),
          ),
          const SizedBox(height: 8),
          Text(explanation, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.5)),
          const SizedBox(height: 10),
          if (rule.mode == LivingAccountMode.fixed)
            for (final m in _draft.members)
              AmountSliderField(
                key: ValueKey('living-fixed-${m.memberId}'),
                label: '${m.displayName}の入金',
                value: rule.contributions[m.memberId] ?? 0,
                baselineValue: sameModeAsBase ? baseRule?.contributions[m.memberId] : null,
                higherIsBetter: false,
                onChanged: (v) => _updateLiving((r) => r.copyWith(
                  contributions: {...r.contributions, m.memberId: v},
                )),
              ),
          if (rule.mode == LivingAccountMode.ratio)
            for (final m in _draft.members)
              AmountSliderField(
                key: ValueKey('living-ratio-${m.memberId}'),
                label: '${m.displayName}の比率（→ ${formatYen(result.livingContributions[m.memberId] ?? 0)}）',
                value: rule.contributions[m.memberId] ?? 0,
                unit: '',
                max: 100,
                step: 1,
                baselineValue: sameModeAsBase ? baseRule?.contributions[m.memberId] : null,
                onChanged: (v) => _updateLiving((r) => r.copyWith(
                  contributions: {...r.contributions, m.memberId: v},
                )),
              ),
          if (rule.mode == LivingAccountMode.incomeProportional)
            for (final m in _draft.members)
              AmountRow(
                label: '${m.displayName}の入金（手取りの比）',
                value: formatYen(result.livingContributions[m.memberId] ?? 0),
              ),
          if (rule.mode != LivingAccountMode.fixed)
            AmountSliderField(
              key: const ValueKey('living-buffer'),
              label: 'バッファ（予備費）',
              value: rule.bufferAmount,
              max: 100000,
              baselineValue: baseRule?.bufferAmount,
              onChanged: (v) => _updateLiving((r) => r.copyWith(bufferAmount: v)),
            ),
          const SizedBox(height: 8),
          const Text('余ったお金', style: TextStyle(fontSize: 12, color: AppColors.textSecond)),
          const SizedBox(height: 6),
          SegmentedButton<SurplusHandling>(
            segments: [
              for (final s in SurplusHandling.values)
                ButtonSegment(value: s, label: Text(s.label, style: const TextStyle(fontSize: 12))),
            ],
            selected: {rule.surplusHandling},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _updateLiving((r) => r.copyWith(surplusHandling: s.first)),
          ),
        ],
      ),
    );
  }

  Widget _buildSavingsSection() {
    final goal = _draft.savingsGoal;
    final baseGoal = widget.baseline?.savingsGoal;
    return BudgetSectionCard(
      title: '貯金',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountSliderField(
            key: const ValueKey('goal-target'),
            label: '目標額',
            value: goal.targetAmount,
            max: 20000000,
            step: 100000,
            baselineValue: baseGoal?.targetAmount,
            higherIsBetter: false,
            onChanged: (v) => _updateGoal((g) => g.copyWith(targetAmount: v)),
          ),
          AmountSliderField(
            key: const ValueKey('goal-balance'),
            label: '今の貯金残高',
            value: goal.currentBalance,
            max: 10000000,
            step: 10000,
            baselineValue: baseGoal?.currentBalance,
            onChanged: (v) => _updateGoal((g) => g.copyWith(currentBalance: v)),
          ),
          for (final m in _draft.members)
            AmountSliderField(
              key: ValueKey('saving-${m.memberId}'),
              label: '${m.displayName}の毎月の貯金',
              value: goal.monthlyContributions[m.memberId] ?? 0,
              baselineValue: baseGoal?.monthlyContributions[m.memberId],
              onChanged: (v) => _updateGoal((g) => g.copyWith(
                monthlyContributions: {...g.monthlyContributions, m.memberId: v},
              )),
            ),
          for (final (i, b) in goal.bonusContributions.indexed)
            AmountSliderField(
              key: ValueKey('bonus-saving-$i'),
              label: '${_draft.memberName(b.memberId)}の${b.month}月ボーナスから',
              value: b.amount,
              max: 1000000,
              step: 10000,
              baselineValue: baseGoal != null && i < baseGoal.bonusContributions.length &&
                      baseGoal.bonusContributions[i].memberId == b.memberId &&
                      baseGoal.bonusContributions[i].month == b.month
                  ? baseGoal.bonusContributions[i].amount
                  : null,
              onChanged: (v) => _updateGoal((g) => g.copyWith(bonusContributions: [
                for (final (j, x) in g.bonusContributions.indexed) j == i ? x.copyWith(amount: v) : x,
              ])),
            ),
          const SizedBox(height: 4),
          _DateRow(
            label: '開始月',
            value: formatYearMonthJa(goal.startDate),
            onTap: () => _pickDate(goal.startDate, (d) => _updateGoal(
              (g) => g.copyWith(startDate: DateTime(d.year, d.month, 1)),
            )),
          ),
          _DateRow(
            label: '期限',
            value: formatDateJa(goal.deadline),
            onTap: () => _pickDate(goal.deadline, (d) => _updateGoal((g) => g.copyWith(deadline: d))),
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateRow({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
        Text(value, style: TextStyle(fontSize: 13, color: appAccent(context), fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        const Icon(Icons.calendar_month_outlined, size: 16, color: AppColors.textMuted),
      ]),
    ),
  );
}

// 画面上部に固定する計算結果（スライダーを動かしながら見えるように）
class _ResultPanel extends StatelessWidget {
  final BudgetPlan plan;
  final BudgetResult result;
  final BudgetResult? baseline;

  const _ResultPanel({required this.plan, required this.result, this.baseline});

  @override
  Widget build(BuildContext context) {
    final base = baseline;
    final cells = <Widget>[
      for (final m in plan.members)
        _cell(
          '${m.displayName}の自由',
          result.remainingAfterSavings[m.memberId] ?? 0,
          base?.remainingAfterSavings[m.memberId],
        ),
      _cell(result.livingSurplus >= 0 ? '生活費の余り' : '生活費の不足', result.livingSurplus, base?.livingSurplus,
          signed: true),
      _cell('期限時点の貯金', result.projectedAtDeadline, base?.projectedAtDeadline, compact: true),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: AppColors.navyCard,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, c) in cells.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: c),
            ],
          ]),
          if (result.warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB8862B)),
                const SizedBox(width: 4),
                Text('注意が${result.warnings.length}件あります（下に詳細）',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecond)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _cell(String label, int value, int? baseValue, {bool signed = false, bool compact = false}) {
    final text = compact && value.abs() >= 1000000
        ? '${formatManYen(value)}円'
        : (signed ? formatSignedYen(value) : formatYen(value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(text, style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: value < 0 ? Colors.redAccent : AppColors.textPrimary,
          )),
        ),
        if (baseValue != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: DiffText(value - baseValue, fontSize: 10.5),
          ),
      ],
    );
  }
}
