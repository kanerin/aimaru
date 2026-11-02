import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../utils/app_theme.dart';
import '../domain/budget_plan.dart';
import '../domain/money.dart';

// ── 項目の編集（共通支出・補助・ボーナス・メンバー名）──────────────
// 項目の追加・削除・並び替えと、名前・カテゴリなどの金額以外の編集を行う。
// ここで変えた内容はFirestoreに直接書かず、呼び出し元（編集・シミュレーション
// 画面）へ編集後のプランとして返す。保存は呼び出し元の「保存」で行う。
class BudgetItemsEditScreen extends StatefulWidget {
  final BudgetPlan plan;

  const BudgetItemsEditScreen({super.key, required this.plan});

  @override
  State<BudgetItemsEditScreen> createState() => _BudgetItemsEditScreenState();
}

class _BudgetItemsEditScreenState extends State<BudgetItemsEditScreen> {
  late BudgetPlan _plan = widget.plan;
  static const _uuid = Uuid();

  void _set(BudgetPlan next) => setState(() => _plan = next);

  // 戻るボタンでも「完了」と同じく編集後のプランを返す（呼び出し元の
  // 「保存」までは確定しないので、ここで捨てる理由が無い）。
  void _done() => Navigator.of(context).pop(_plan);

  // ── 共通支出 ──
  Future<void> _editExpense([SharedExpense? existing]) async {
    final result = await showDialog<SharedExpense>(
      context: context,
      builder: (_) => _ExpenseDialog(
        initial: existing ??
            SharedExpense(id: _uuid.v4(), label: '', monthlyAmount: 0, category: ExpenseCategory.other),
        isNew: existing == null,
      ),
    );
    if (result == null) return;
    _set(_plan.copyWith(
      sharedExpenses: existing == null
          ? [..._plan.sharedExpenses, result]
          : [for (final e in _plan.sharedExpenses) e.id == result.id ? result : e],
    ));
  }

  void _removeExpense(SharedExpense e) => _set(_plan.copyWith(
    sharedExpenses: _plan.sharedExpenses.where((x) => x.id != e.id).toList(),
  ));

  // ── 補助 ──
  Future<void> _editOffset([BudgetOffset? existing]) async {
    final result = await showDialog<BudgetOffset>(
      context: context,
      builder: (_) => _OffsetDialog(
        initial: existing ?? BudgetOffset(id: _uuid.v4(), label: '', monthlyAmount: 0),
        members: _plan.members,
        isNew: existing == null,
      ),
    );
    if (result == null) return;
    _set(_plan.copyWith(
      offsets: existing == null
          ? [..._plan.offsets, result]
          : [for (final o in _plan.offsets) o.id == result.id ? result : o],
    ));
  }

  void _removeOffset(BudgetOffset o) => _set(_plan.copyWith(
    offsets: _plan.offsets.where((x) => x.id != o.id).toList(),
  ));

  // onReorderItemのnewIndexは、取り除いた後のリストでの位置（調整済み）
  List<T> _reordered<T>(List<T> list, int oldIndex, int newIndex) {
    final copy = [...list];
    copy.insert(newIndex, copy.removeAt(oldIndex));
    return copy;
  }

  // ── ボーナス（収入）──
  Future<void> _addBonus(BudgetMember member) async {
    final result = await showDialog<Bonus>(
      context: context,
      builder: (_) => const _BonusDialog(),
    );
    if (result == null) return;
    _setMemberBonuses(member, [...member.bonuses, result]);
  }

  void _setMemberBonuses(BudgetMember member, List<Bonus> bonuses) {
    // 支給月の順に並べる（ボーナスは時系列で見るのが自然なため）
    final sorted = [...bonuses]..sort((a, b) => a.month.compareTo(b.month));
    _set(_plan.copyWith(members: [
      for (final m in _plan.members) m.memberId == member.memberId ? m.copyWith(bonuses: sorted) : m,
    ]));
  }

  // ── ボーナスからの貯金 ──
  Future<void> _addBonusContribution() async {
    final result = await showDialog<BonusContribution>(
      context: context,
      builder: (_) => _BonusContributionDialog(members: _plan.members),
    );
    if (result == null) return;
    final list = [..._plan.savingsGoal.bonusContributions, result]
      ..sort((a, b) => a.month.compareTo(b.month));
    _set(_plan.copyWith(savingsGoal: _plan.savingsGoal.copyWith(bonusContributions: list)));
  }

  void _removeBonusContribution(int index) {
    final list = [..._plan.savingsGoal.bonusContributions]..removeAt(index);
    _set(_plan.copyWith(savingsGoal: _plan.savingsGoal.copyWith(bonusContributions: list)));
  }

  // ── メンバー名 ──
  Future<void> _renameMember(BudgetMember member) async {
    final controller = TextEditingController(text: member.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('表示名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: '例: あい'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    _set(_plan.copyWith(members: [
      for (final m in _plan.members) m.memberId == member.memberId ? m.copyWith(displayName: name) : m,
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          backgroundColor: AppColors.navy,
          appBar: AppBar(
            title: const Text('項目の編集'),
            actions: [TextButton(onPressed: _done, child: const Text('完了'))],
            bottom: TabBar(
              labelColor: appAccent(context),
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: appAccent(context),
              tabs: const [
                Tab(text: '共通支出'),
                Tab(text: '補助'),
                Tab(text: 'ボーナス'),
                Tab(text: 'メンバー'),
              ],
            ),
          ),
          body: TabBarView(children: [
            _buildExpenses(),
            _buildOffsets(),
            _buildBonuses(),
            _buildMembers(),
          ]),
        ),
      ),
    );
  }

  Widget _addButton(String label, VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 18),
      label: Text(label),
    ),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
    child: Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.5)),
  );

  Widget _itemTile({
    required Key key,
    required int index,
    required String title,
    required String subtitle,
    required String amount,
    required VoidCallback onTap,
    VoidCallback? onDelete,
    bool reorderable = true,
  }) =>
      Padding(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Material(
          color: AppColors.navySurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: onTap,
            title: Text(title, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(amount, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.textMuted),
                  tooltip: '$titleを削除',
                  onPressed: onDelete,
                ),
              if (reorderable)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.drag_handle, color: AppColors.textMuted),
                  ),
                ),
            ]),
          ),
        ),
      );

  Widget _buildExpenses() => Column(children: [
    _hint('タップで名前・金額・カテゴリを変更、右端のつまみで並び替えできます'),
    Expanded(
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: _plan.sharedExpenses.length,
        onReorderItem: (from, to) => _set(_plan.copyWith(
          sharedExpenses: _reordered(_plan.sharedExpenses, from, to),
        )),
        footer: _addButton('共通支出を追加', () => _editExpense()),
        itemBuilder: (_, i) {
          final e = _plan.sharedExpenses[i];
          return _itemTile(
            key: ValueKey('expense-${e.id}'),
            index: i,
            title: e.label,
            subtitle: '${e.category.emoji} ${e.category.label}',
            amount: formatYen(e.monthlyAmount),
            onTap: () => _editExpense(e),
            onDelete: () => _removeExpense(e),
          );
        },
      ),
    ),
  ]);

  Widget _buildOffsets() => Column(children: [
    _hint('家賃補助のように、各自の手取りとは別に共通の支出を減らすお金を登録します'),
    Expanded(
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: _plan.offsets.length,
        onReorderItem: (from, to) => _set(_plan.copyWith(offsets: _reordered(_plan.offsets, from, to))),
        footer: _addButton('補助を追加', () => _editOffset()),
        itemBuilder: (_, i) {
          final o = _plan.offsets[i];
          return _itemTile(
            key: ValueKey('offset-${o.id}'),
            index: i,
            title: o.label,
            subtitle: '受け取り: ${_plan.memberName(o.receivedBy)}',
            amount: formatYen(o.monthlyAmount),
            onTap: () => _editOffset(o),
            onDelete: () => _removeOffset(o),
          );
        },
      ),
    ),
  ]);

  Widget _buildBonuses() => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _hint('各自のボーナス（手取りの支給額）と、そこから貯金へ入れる額を登録します。支給月の順に並びます'),
      for (final m in _plan.members) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text('${m.displayName}のボーナス',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            TextButton.icon(
              onPressed: () => _addBonus(m),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('追加'),
            ),
          ]),
        ),
        if (m.bonuses.isEmpty) _hint('登録されていません'),
        for (final (i, b) in m.bonuses.indexed)
          _itemTile(
            key: ValueKey('bonus-${m.memberId}-$i'),
            index: i,
            reorderable: false,
            title: '${b.month}月',
            subtitle: b.payDay == null ? '支給日: 未設定' : '支給日: ${b.payDay}日',
            amount: formatYen(b.amount),
            onTap: () async {
              final edited = await showDialog<Bonus>(context: context, builder: (_) => _BonusDialog(initial: b));
              if (edited != null) {
                _setMemberBonuses(m, [for (final (j, x) in m.bonuses.indexed) j == i ? edited : x]);
              }
            },
            onDelete: () => _setMemberBonuses(m, [...m.bonuses]..removeAt(i)),
          ),
      ],
      const Divider(height: 32, indent: 16, endIndent: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
        child: Row(children: [
          const Expanded(
            child: Text('ボーナスからの貯金',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          TextButton.icon(
            onPressed: _addBonusContribution,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('追加'),
          ),
        ]),
      ),
      if (_plan.savingsGoal.bonusContributions.isEmpty) _hint('登録されていません'),
      for (final (i, b) in _plan.savingsGoal.bonusContributions.indexed)
        _itemTile(
          key: ValueKey('bonus-contribution-$i'),
          index: i,
          reorderable: false,
          title: '${_plan.memberName(b.memberId)}・${b.month}月',
          subtitle: '毎年この月に貯金へ入れる',
          amount: formatYen(b.amount),
          onTap: () async {
            final edited = await showDialog<BonusContribution>(
              context: context,
              builder: (_) => _BonusContributionDialog(members: _plan.members, initial: b),
            );
            if (edited == null) return;
            final list = [
              for (final (j, x) in _plan.savingsGoal.bonusContributions.indexed) j == i ? edited : x,
            ]..sort((a, b) => a.month.compareTo(b.month));
            _set(_plan.copyWith(savingsGoal: _plan.savingsGoal.copyWith(bonusContributions: list)));
          },
          onDelete: () => _removeBonusContribution(i),
        ),
    ],
  );

  Widget _buildMembers() => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _hint('家計プランの中で使う表示名です（アカウントの表示名は変わりません）'),
      for (final m in _plan.members)
        _itemTile(
          key: ValueKey('member-${m.memberId}'),
          index: 0,
          reorderable: false,
          title: m.displayName,
          subtitle: 'タップで表示名を変更',
          amount: '',
          onTap: () => _renameMember(m),
        ),
    ],
  );
}

// ── 入力ダイアログ ──────────────────────────────────

class _AmountInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _AmountInput({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    style: const TextStyle(color: AppColors.textPrimary),
    decoration: InputDecoration(labelText: label, suffixText: '円'),
  );
}

class _ExpenseDialog extends StatefulWidget {
  final SharedExpense initial;
  final bool isNew;
  const _ExpenseDialog({required this.initial, required this.isNew});

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  late final _label = TextEditingController(text: widget.initial.label);
  late final _amount = TextEditingController(
    text: widget.initial.monthlyAmount == 0 ? '' : formatAmount(widget.initial.monthlyAmount),
  );
  late ExpenseCategory _category = widget.initial.category;

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.navyCard,
    title: Text(widget.isNew ? '共通支出を追加' : '共通支出を編集'),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _label,
          autofocus: widget.isNew,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(labelText: '項目名', hintText: '例: 通信費'),
        ),
        const SizedBox(height: 12),
        _AmountInput(controller: _amount, label: '毎月の金額'),
        const SizedBox(height: 12),
        DropdownButtonFormField<ExpenseCategory>(
          initialValue: _category,
          dropdownColor: AppColors.navyCard,
          decoration: const InputDecoration(labelText: 'カテゴリ'),
          items: [
            for (final c in ExpenseCategory.values)
              DropdownMenuItem(value: c, child: Text('${c.emoji} ${c.label}')),
          ],
          onChanged: (c) => setState(() => _category = c ?? _category),
        ),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
      TextButton(
        onPressed: () {
          final label = _label.text.trim();
          if (label.isEmpty) return;
          Navigator.pop(context, widget.initial.copyWith(
            label: label,
            monthlyAmount: parseAmount(_amount.text) ?? 0,
            category: _category,
          ));
        },
        child: const Text('OK'),
      ),
    ],
  );
}

class _OffsetDialog extends StatefulWidget {
  final BudgetOffset initial;
  final List<BudgetMember> members;
  final bool isNew;
  const _OffsetDialog({required this.initial, required this.members, required this.isNew});

  @override
  State<_OffsetDialog> createState() => _OffsetDialogState();
}

class _OffsetDialogState extends State<_OffsetDialog> {
  late final _label = TextEditingController(text: widget.initial.label);
  late final _amount = TextEditingController(
    text: widget.initial.monthlyAmount == 0 ? '' : formatAmount(widget.initial.monthlyAmount),
  );
  late String? _receivedBy = widget.initial.receivedBy;

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.navyCard,
    title: Text(widget.isNew ? '補助を追加' : '補助を編集'),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _label,
          autofocus: widget.isNew,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(labelText: '項目名', hintText: '例: 家賃補助'),
        ),
        const SizedBox(height: 12),
        _AmountInput(controller: _amount, label: '毎月の金額'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _receivedBy,
          dropdownColor: AppColors.navyCard,
          decoration: const InputDecoration(labelText: '受け取る人'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('2人共通')),
            for (final m in widget.members)
              DropdownMenuItem<String?>(value: m.memberId, child: Text(m.displayName)),
          ],
          onChanged: (v) => setState(() => _receivedBy = v),
        ),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
      TextButton(
        onPressed: () {
          final label = _label.text.trim();
          if (label.isEmpty) return;
          Navigator.pop(context, BudgetOffset(
            id: widget.initial.id,
            label: label,
            monthlyAmount: parseAmount(_amount.text) ?? 0,
            receivedBy: _receivedBy,
          ));
        },
        child: const Text('OK'),
      ),
    ],
  );
}

class _MonthDropdown extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _MonthDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: value,
    dropdownColor: AppColors.navyCard,
    decoration: const InputDecoration(labelText: '月'),
    items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text('$m月'))],
    onChanged: (v) => onChanged(v ?? value),
  );
}

class _BonusDialog extends StatefulWidget {
  final Bonus? initial;
  const _BonusDialog({this.initial});

  @override
  State<_BonusDialog> createState() => _BonusDialogState();
}

class _BonusDialogState extends State<_BonusDialog> {
  late int _month = widget.initial?.month ?? 6;
  late final _amount = TextEditingController(
    text: widget.initial == null ? '' : formatAmount(widget.initial!.amount),
  );
  late final _payDay = TextEditingController(text: widget.initial?.payDay?.toString() ?? '');

  @override
  void dispose() {
    _amount.dispose();
    _payDay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.navyCard,
    title: Text(widget.initial == null ? 'ボーナスを追加' : 'ボーナスを編集'),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _MonthDropdown(value: _month, onChanged: (m) => setState(() => _month = m)),
        const SizedBox(height: 12),
        _AmountInput(controller: _amount, label: '支給額（手取り）'),
        const SizedBox(height: 12),
        TextField(
          controller: _payDay,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: '支給日（任意）',
            hintText: '例: 10',
            suffixText: '日',
            helperText: 'カレンダーに表示する日。空欄なら月初に「ボーナス月」と表示',
          ),
        ),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
      TextButton(
        onPressed: () {
          final day = parseAmount(_payDay.text);
          Navigator.pop(context, Bonus(
            month: _month,
            amount: parseAmount(_amount.text) ?? 0,
            payDay: day?.clamp(1, 31),
          ));
        },
        child: const Text('OK'),
      ),
    ],
  );
}

class _BonusContributionDialog extends StatefulWidget {
  final List<BudgetMember> members;
  final BonusContribution? initial;
  const _BonusContributionDialog({required this.members, this.initial});

  @override
  State<_BonusContributionDialog> createState() => _BonusContributionDialogState();
}

class _BonusContributionDialogState extends State<_BonusContributionDialog> {
  late String _memberId = widget.initial?.memberId ??
      (widget.members.isNotEmpty ? widget.members.first.memberId : '');
  late int _month = widget.initial?.month ?? 6;
  late final _amount = TextEditingController(
    text: widget.initial == null ? '' : formatAmount(widget.initial!.amount),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.navyCard,
    title: Text(widget.initial == null ? 'ボーナスからの貯金を追加' : 'ボーナスからの貯金を編集'),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          initialValue: _memberId,
          dropdownColor: AppColors.navyCard,
          decoration: const InputDecoration(labelText: '誰のボーナスから'),
          items: [
            for (final m in widget.members) DropdownMenuItem(value: m.memberId, child: Text(m.displayName)),
          ],
          onChanged: (v) => setState(() => _memberId = v ?? _memberId),
        ),
        const SizedBox(height: 12),
        _MonthDropdown(value: _month, onChanged: (m) => setState(() => _month = m)),
        const SizedBox(height: 12),
        _AmountInput(controller: _amount, label: '貯金へ入れる額'),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
      TextButton(
        onPressed: () => Navigator.pop(context, BonusContribution(
          memberId: _memberId,
          month: _month,
          amount: parseAmount(_amount.text) ?? 0,
        )),
        child: const Text('OK'),
      ),
    ],
  );
}
