import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/couple_service.dart';
import '../../../services/settings_service.dart';
import '../../../utils/app_theme.dart';
import '../../../widgets/confirm_delete_dialog.dart';
import '../data/budget_plan_repository.dart';
import '../domain/budget_calculator.dart';
import '../domain/budget_plan.dart';
import '../domain/budget_result.dart';
import '../domain/money.dart';
import 'budget_history_screen.dart';
import 'budget_plan_editor_screen.dart';
import 'budget_projection_screen.dart';
import 'budget_summary_cards.dart';
import 'budget_widgets.dart';

typedef BudgetMemberSeed = ({String memberId, String displayName});

// ── ふたりの家計（確定プランのサマリー）─────────────────────
// 2人で話し合って決めた「生活費の分担」と「貯金目標」を1画面で見る。
// 確定プランの毎月の流れ（手取り → 生活費口座 → 貯金口座 → 自由に使えるお金）と
// 貯金の進捗を出し、ここから編集・シミュレーション・グラフ・変更履歴へ進む。
class BudgetSummaryScreen extends StatefulWidget {
  final String coupleId;
  // 以下はテストからFirebaseに触れずに検証するための注入ポイント。
  final Stream<List<BudgetPlan>>? plansStreamOverride;
  final BudgetPlanRepository? repositoryOverride;
  final Future<List<BudgetMemberSeed>> Function()? loadMembersOverride;
  final SettingsService? settingsServiceOverride;
  final DateTime Function()? nowOverride;

  const BudgetSummaryScreen({
    super.key,
    required this.coupleId,
    this.plansStreamOverride,
    this.repositoryOverride,
    this.loadMembersOverride,
    this.settingsServiceOverride,
    this.nowOverride,
  });

  @override
  State<BudgetSummaryScreen> createState() => _BudgetSummaryScreenState();
}

class _BudgetSummaryScreenState extends State<BudgetSummaryScreen> {
  // リポジトリは生成時にFirebaseFirestore.instanceへ触れるため、ストリームを
  // 差し込むテストでは使うときまで生成を遅らせる（todos_screen.dartと同じ設計）。
  BudgetPlanRepository? _repoInstance;
  BudgetPlanRepository get _repo =>
      _repoInstance ??= widget.repositoryOverride ?? BudgetPlanRepository();

  SettingsService? _settingsInstance;
  SettingsService get _settings =>
      widget.settingsServiceOverride ?? (_settingsInstance ??= SettingsService());

  late final Stream<List<BudgetPlan>> _plansStream =
      widget.plansStreamOverride ?? _repo.watchPlans(widget.coupleId);

  bool _showBonusesOnCalendar = false;
  bool _preparing = false;

  DateTime get _now => (widget.nowOverride ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _loadCalendarPref();
  }

  // 表示設定の読み込みは補助的なものなので、失敗しても画面は使えるようにする
  Future<void> _loadCalendarPref() async {
    try {
      final value = await _settings.getShowBudgetBonuses();
      if (mounted) setState(() => _showBonusesOnCalendar = value);
    } catch (e) {
      debugPrint('[家計] カレンダー表示設定の読み込みに失敗: $e');
    }
  }

  Future<void> _setShowBonusesOnCalendar(bool value) async {
    setState(() => _showBonusesOnCalendar = value);
    try {
      await _settings.setShowBudgetBonuses(value);
      _showSnack(value ? 'ボーナスの支給日をカレンダーに表示します' : 'カレンダーのボーナス表示をやめました');
    } catch (e) {
      if (mounted) setState(() => _showBonusesOnCalendar = !value);
      _showSnack('設定を保存できませんでした');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<BudgetMemberSeed>> _loadMembers() async {
    if (widget.loadMembersOverride != null) return widget.loadMembersOverride!();
    final coupleService = CoupleService();
    final couple = await coupleService.getMyCouple();
    if (couple == null) return const [];
    final profiles = await coupleService.getMemberProfiles(couple.memberIds);
    final me = FirebaseAuth.instance.currentUser?.uid;
    // 自分を左に並べる
    final ids = [...couple.memberIds]..sort((a, b) => a == me ? -1 : (b == me ? 1 : 0));
    return [
      for (final id in ids)
        (
          memberId: id,
          displayName: (profiles[id]?['displayName'] as String?)?.trim().isNotEmpty == true
              ? (profiles[id]!['displayName'] as String).trim()
              : (id == me ? '自分' : 'パートナー'),
        ),
    ];
  }

  // 最初の家計プラン。ひな型（金額0）をまだ保存せずに編集画面で開き、
  // 「保存」したときに確定プランとして作る（空のプランで相手に通知を飛ばさない）。
  Future<void> _startFirstPlan() async {
    setState(() => _preparing = true);
    try {
      final members = await _loadMembers();
      if (members.isEmpty) throw StateError('メンバーを取得できませんでした');
      final template = BudgetPlan.template(members: members, today: _now);
      if (!mounted) return;
      await _openEditor(template, mode: BudgetEditorMode.editActive);
    } catch (e) {
      debugPrint('[家計] ひな型の準備に失敗: $e');
      _showSnack('家計プランの準備に失敗しました。もう一度お試しください');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _openEditor(BudgetPlan plan, {BudgetPlan? baseline, required BudgetEditorMode mode}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BudgetPlanEditorScreen(
          coupleId: widget.coupleId,
          plan: plan,
          baseline: baseline,
          mode: mode,
          repositoryOverride: widget.repositoryOverride,
        ),
      ));

  Future<void> _startSimulation(BudgetPlan active, int existingCount) async {
    final name = await _promptName(initial: 'シミュレーション${existingCount + 1}');
    if (name == null || name.isEmpty || !mounted) return;
    await _openEditor(active.duplicateAsDraft(name: name), baseline: active, mode: BudgetEditorMode.simulation);
  }

  Future<String?> _promptName({required String initial}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('シミュレーションの名前'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: '例: 家賃上げた場合'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('はじめる')),
        ],
      ),
    );
  }

  Future<void> _deleteSimulation(BudgetPlan sim) async {
    final confirmed = await confirmDelete(
      context,
      title: 'シミュレーションを削除',
      message: '「${sim.name}」を削除します。元に戻せません（削除したことは変更履歴に残ります）。',
    );
    if (!confirmed) return;
    try {
      await _repo.deletePlan(widget.coupleId, sim);
    } catch (e) {
      _showSnack('削除に失敗しました。もう一度お試しください');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BudgetPlan>>(
      stream: _plansStream,
      builder: (context, snap) {
        final plans = snap.data;
        return Scaffold(
          backgroundColor: AppColors.navy,
          appBar: AppBar(
            title: const Text('ふたりの家計'),
            actions: plans == null || plans.isEmpty ? null : _buildActions(plans),
          ),
          body: _buildBody(snap),
        );
      },
    );
  }

  List<Widget> _buildActions(List<BudgetPlan> plans) => [
    IconButton(
      icon: const Icon(Icons.show_chart),
      tooltip: '貯金推移グラフ',
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BudgetProjectionScreen(plans: plans),
      )),
    ),
    IconButton(
      icon: const Icon(Icons.history),
      tooltip: '変更履歴',
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BudgetHistoryScreen(
          coupleId: widget.coupleId,
          memberNames: {
            for (final p in plans)
              for (final m in p.members) m.memberId: m.displayName,
          },
          repositoryOverride: widget.repositoryOverride,
        ),
      )),
    ),
    PopupMenuButton<String>(
      tooltip: 'その他',
      color: AppColors.navyCard,
      onSelected: (value) {
        if (value == 'calendar') _setShowBonusesOnCalendar(!_showBonusesOnCalendar);
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'calendar',
          checked: _showBonusesOnCalendar,
          child: const Text('ボーナスをカレンダーに表示'),
        ),
      ],
    ),
  ];

  Widget _buildBody(AsyncSnapshot<List<BudgetPlan>> snap) {
    // hasDataだけを見ていると、権限エラー（ルール未反映など）で無限ローディングになる
    if (snap.hasError) {
      return const Center(
        child: Text('読み込みに失敗しました\nしばらくしてから開き直してください',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
      );
    }
    if (!snap.hasData) {
      return Center(child: CircularProgressIndicator(color: appAccent(context)));
    }
    final plans = snap.data!;
    final active = plans.where((p) => p.isActive).firstOrNull;
    final simulations = plans.where((p) => !p.isActive).toList();

    if (active == null) return _buildEmpty(simulations);

    final result = BudgetCalculator.calculate(active);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _ActivePlanHeader(plan: active),
        const SizedBox(height: 12),
        BudgetWarningsCard(plan: active, result: result),
        MonthlyFlowCard(plan: active, result: result),
        SavingsGoalCard(plan: active, result: result),
        LivingAccountCard(plan: active, result: result),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _openEditor(active, baseline: active, mode: BudgetEditorMode.editActive),
              icon: const Icon(Icons.edit_outlined, size: 18),
              // 幅の狭い端末で2行に折り返さないよう短くする（何を編集するかは見出しで分かる）
              label: const Text('編集する'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _startSimulation(active, simulations.length),
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text('シミュレーション'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        _buildSimulations(active, result, simulations),
      ],
    );
  }

  Widget _buildEmpty(List<BudgetPlan> simulations) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
      children: [
        const Text('💰', textAlign: TextAlign.center, style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        const Text('ふたりの家計プランを作りましょう',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        const Text(
          '2人の手取り・共通の支出・生活費の分担・貯金目標を登録すると、'
          '毎月の自由に使えるお金や貯金の見込みを計算します。'
          '金額を変えながらシミュレーションもできます。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecond, height: 1.7),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _preparing ? null : _startFirstPlan,
          child: Text(_preparing ? '準備中…' : '家計プランを作る'),
        ),
        // 確定プランが無いのにシミュレーションだけ残っている場合（確定プランを
        // 別の端末で操作した直後など）は、そこから確定にできるよう並べておく
        if (simulations.isNotEmpty) ...[
          const SizedBox(height: 32),
          const Text('保存してあるシミュレーション',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final sim in simulations)
            _SimulationTile(
              plan: sim,
              result: BudgetCalculator.calculate(sim),
              baseline: null,
              onTap: () => _openEditor(sim, mode: BudgetEditorMode.simulation),
              onDelete: () => _deleteSimulation(sim),
            ),
        ],
      ],
    );
  }

  Widget _buildSimulations(BudgetPlan active, BudgetResult activeResult, List<BudgetPlan> simulations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('シミュレーション',
            style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (simulations.isEmpty)
          const Text(
            '確定プランを複製して、家賃や貯金額を変えたらどうなるかを試せます。確定プランには影響しません。',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.6),
          ),
        for (final sim in simulations)
          _SimulationTile(
            plan: sim,
            result: BudgetCalculator.calculate(sim),
            baseline: activeResult,
            onTap: () => _openEditor(sim, baseline: active, mode: BudgetEditorMode.simulation),
            onDelete: () => _deleteSimulation(sim),
          ),
      ],
    );
  }
}

class _ActivePlanHeader extends StatelessWidget {
  final BudgetPlan plan;
  const _ActivePlanHeader({required this.plan});

  @override
  Widget build(BuildContext context) {
    final updatedAt = plan.updatedAt;
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: appAccent(context).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('確定', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: appAccent(context))),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(plan.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      if (updatedAt != null)
        Text('${formatDateTimeShort(updatedAt)} ${plan.memberName(plan.updatedBy, fallback: '')}',
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
    ]);
  }
}

class _SimulationTile extends StatelessWidget {
  final BudgetPlan plan;
  final BudgetResult result;
  final BudgetResult? baseline;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SimulationTile({
    required this.plan,
    required this.result,
    required this.baseline,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final base = baseline;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.navySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(plan.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        ),
                        if (result.warnings.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: '注意 ${result.warnings.length}件',
                            child: const Icon(Icons.warning_amber_rounded, size: 15, color: Color(0xFFB8862B)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, runSpacing: 4, children: [
                        for (final m in plan.members)
                          _metric(
                            '${m.displayName}の自由',
                            result.remainingAfterSavings[m.memberId] ?? 0,
                            base?.remainingAfterSavings[m.memberId],
                          ),
                        _metric('期限時点', result.projectedAtDeadline, base?.projectedAtDeadline),
                      ]),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.textMuted),
                  tooltip: '削除',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, int value, int? baseValue) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label ', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      Text(formatManYenOrYen(value), style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary)),
      if (baseValue != null && baseValue != value) ...[
        const SizedBox(width: 3),
        DiffText(value - baseValue, fontSize: 10.5),
      ],
    ],
  );
}

// 一覧では桁が大きい額（貯金残高など）は万円で短く、それ以外は円で出す
String formatManYenOrYen(int amount) =>
    amount.abs() >= 1000000 ? '${formatManYen(amount)}円' : formatYen(amount);
