import 'package:flutter/material.dart';

import '../../../utils/app_theme.dart';
import '../data/budget_plan_repository.dart';
import '../domain/bonus_savings.dart';
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
                  _buildSavingsSection(result),
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

  // 毎月の貯金の決め方を切り替える。自動→カスタムに切り替えたときは、
  // それまで自動で決まっていた額を手入力の出発点にする（「自動で入れてから
  // 手で微調整する」ができるように）。
  void _setSavingsMode(SavingsContributionMode mode, BudgetResult result) {
    final members = _draft.members;
    _updateGoal((g) {
      var next = g.copyWith(contributionMode: mode);
      switch (mode) {
        case SavingsContributionMode.custom:
          next = next.copyWith(monthlyContributions: {...g.monthlyContributions, ...result.savingsContributions});
        case SavingsContributionMode.ratio:
          if (g.contributionWeights.values.every((w) => w <= 0)) {
            next = next.copyWith(contributionWeights: {for (final m in members) m.memberId: 50});
          }
        case SavingsContributionMode.fixed:
          if (g.fixedMemberIds.isEmpty && members.isNotEmpty) {
            final first = members.first.memberId;
            next = next.copyWith(
              fixedMemberIds: [first],
              monthlyContributions: {...g.monthlyContributions, first: result.savingsContributions[first] ?? 0},
            );
          }
        case SavingsContributionMode.incomeProportional:
          break;
      }
      return next;
    });
  }

  Widget _buildSavingsSection(BudgetResult result) {
    final goal = _draft.savingsGoal;
    final baseGoal = widget.baseline?.savingsGoal;
    final mode = goal.contributionMode;
    final sameModeAsBase = baseGoal?.contributionMode == mode;
    final required = result.requiredMonthlyToHitGoal;
    final explanation = switch (mode) {
      SavingsContributionMode.custom => '各自の毎月の貯金額を手で決めます。',
      SavingsContributionMode.ratio => '期限に間に合う毎月の貯金を、決めた比率で2人に分けます。',
      SavingsContributionMode.fixed => '固定した人はその額のまま、期限に間に合うために足りない分を残りの人で分けます。',
      SavingsContributionMode.incomeProportional => '期限に間に合う毎月の貯金を、2人の手取りの比で分けます。',
    };

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

          // ── ボーナスからの貯金（年に何回・1回いくら）──
          const SizedBox(height: 12),
          const _SubHeading('ボーナスからの貯金'),
          for (final m in _draft.members) _buildBonusSavingsRow(m),

          // ── 毎月の貯金の決め方 ──
          const SizedBox(height: 12),
          const _SubHeading('毎月の貯金の決め方'),
          SegmentedButton<SavingsContributionMode>(
            segments: const [
              ButtonSegment(value: SavingsContributionMode.custom, label: Text('カスタム', style: TextStyle(fontSize: 11.5))),
              ButtonSegment(value: SavingsContributionMode.ratio, label: Text('比率', style: TextStyle(fontSize: 11.5))),
              ButtonSegment(value: SavingsContributionMode.fixed, label: Text('固定', style: TextStyle(fontSize: 11.5))),
              ButtonSegment(value: SavingsContributionMode.incomeProportional, label: Text('収入比', style: TextStyle(fontSize: 11.5))),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _setSavingsMode(s.first, result),
          ),
          const SizedBox(height: 8),
          Text(explanation, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.5)),
          const SizedBox(height: 6),
          if (!goal.hasTarget)
            Text(
              mode.isAutomatic
                  ? '目標額を決めると、期限に間に合う毎月の貯金を自動で計算して入れます'
                  : '目標額を決めると、期限に間に合う毎月の貯金の目安を出します',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecond, height: 1.5),
            )
          else if (required != null)
            AmountRow(
              // 幅の狭い端末で折り返さない長さにする
              label: '必要な毎月の貯金（2人の合計）',
              value: formatYen(required),
              emphasized: mode.isAutomatic,
            ),
          if (mode == SavingsContributionMode.custom && goal.hasTarget && required != null)
            AmountRow(
              label: '今の毎月の貯金（2人の合計）',
              value: formatYen(result.totalMonthlySavingsContributions),
              valueColor: result.totalMonthlySavingsContributions >= required ? AppColors.success : Colors.redAccent,
            ),
          const SizedBox(height: 6),
          for (final m in _draft.members) ..._buildMemberSaving(m, mode, result, baseGoal, sameModeAsBase),
        ],
      ),
    );
  }

  List<Widget> _buildMemberSaving(
    BudgetMember m,
    SavingsContributionMode mode,
    BudgetResult result,
    SavingsGoal? baseGoal,
    bool sameModeAsBase,
  ) {
    final goal = _draft.savingsGoal;
    final computed = result.savingsContributions[m.memberId] ?? 0;
    switch (mode) {
      case SavingsContributionMode.custom:
        return [
          AmountSliderField(
            key: ValueKey('saving-${m.memberId}'),
            label: '${m.displayName}の毎月の貯金',
            value: goal.monthlyContributions[m.memberId] ?? 0,
            baselineValue: baseGoal?.monthlyContributions[m.memberId],
            onChanged: (v) => _updateGoal((g) => g.copyWith(
              monthlyContributions: {...g.monthlyContributions, m.memberId: v},
            )),
          ),
        ];
      case SavingsContributionMode.ratio:
        return [
          AmountSliderField(
            key: ValueKey('saving-ratio-${m.memberId}'),
            label: '${m.displayName}の貯金の比率（→ ${formatYen(computed)}）',
            value: goal.contributionWeights[m.memberId] ?? 0,
            unit: '',
            max: 100,
            step: 1,
            baselineValue: sameModeAsBase ? baseGoal?.contributionWeights[m.memberId] : null,
            onChanged: (v) => _updateGoal((g) => g.copyWith(
              contributionWeights: {...g.contributionWeights, m.memberId: v},
            )),
          ),
        ];
      case SavingsContributionMode.fixed:
        final isFixed = goal.fixedMemberIds.contains(m.memberId);
        return [
          Row(children: [
            Expanded(
              child: Text(m.displayName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            const Text('額を固定', style: TextStyle(fontSize: 12, color: AppColors.textSecond)),
            Switch(
              value: isFixed,
              onChanged: (v) => _updateGoal((g) {
                final ids = [...g.fixedMemberIds]..remove(m.memberId);
                if (v) ids.add(m.memberId);
                return g.copyWith(
                  fixedMemberIds: ids,
                  // 固定に切り替えた瞬間は、今自動で決まっている額から始める
                  monthlyContributions: v ? {...g.monthlyContributions, m.memberId: computed} : null,
                );
              }),
            ),
          ]),
          if (isFixed)
            AmountSliderField(
              key: ValueKey('saving-fixed-${m.memberId}'),
              label: '${m.displayName}の毎月の貯金（固定）',
              value: goal.monthlyContributions[m.memberId] ?? 0,
              onChanged: (v) => _updateGoal((g) => g.copyWith(
                monthlyContributions: {...g.monthlyContributions, m.memberId: v},
              )),
            )
          else
            AmountRow(label: '${m.displayName}の毎月の貯金（残りを自動）', value: formatYen(computed)),
          const SizedBox(height: 4),
        ];
      case SavingsContributionMode.incomeProportional:
        return [AmountRow(label: '${m.displayName}の毎月の貯金（手取りの比）', value: formatYen(computed))];
    }
  }

  Widget _buildBonusSavingsRow(BudgetMember m) {
    final setting = bonusSavingsOf(_draft.savingsGoal, m.memberId);
    final baseSetting = widget.baseline == null ? null : bonusSavingsOf(widget.baseline!.savingsGoal, m.memberId);
    void set({int? times, int? amount}) => _updateGoal((g) => g.copyWith(
      bonusContributions: withBonusSavings(
        _draft,
        m.memberId,
        timesPerYear: times ?? setting.timesPerYear,
        // 回数だけ変えたときは今の1回あたりの額を引き継ぐ（0回からなら0円から）
        amountPerTime: amount ?? setting.amountPerTime,
      ),
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text('${m.displayName}のボーナスから',
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 22),
            tooltip: '${m.displayName}のボーナス入金の回数を減らす',
            onPressed: setting.timesPerYear <= 0 ? null : () => set(times: setting.timesPerYear - 1),
          ),
          SizedBox(
            width: 52,
            child: Text('年${setting.timesPerYear}回',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            tooltip: '${m.displayName}のボーナス入金の回数を増やす',
            onPressed: setting.timesPerYear >= maxBonusSavingsTimesPerYear
                ? null
                : () => set(times: setting.timesPerYear + 1),
          ),
        ]),
        if (setting.timesPerYear > 0) ...[
          AmountSliderField(
            key: ValueKey('bonus-saving-${m.memberId}'),
            label: '1回あたり',
            value: setting.amountPerTime,
            max: 1000000,
            step: 10000,
            baselineValue: baseSetting != null && baseSetting.timesPerYear > 0 ? baseSetting.amountPerTime : null,
            onChanged: (v) => set(amount: v),
          ),
          Text(
            '${setting.months.map((mo) => '$mo月').join('・')}に入金（年${formatYen(setting.annualAmount)}）'
            '${setting.uniformAmount ? '' : '。月ごとに額が違うため、ここで変えると全部の月が同じ額になります'}'
            '。入金する月は「項目を編集」で変えられます',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SubHeading extends StatelessWidget {
  final String text;
  const _SubHeading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecond)),
  );
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
