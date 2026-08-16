import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';
import '../services/expense_service.dart';
import '../utils/app_theme.dart';
import '../utils/expense_balance.dart';

// ── 割り勘・立て替え ─────────────────────────────────
// デート代や買い物の立て替えを記録して、どちらがいくら多く払っているかを
// 精算額として自動計算する。TimeTreeなど競合のカレンダー機能には無い、
// カップル/夫婦アプリでよく比較される費用共有の要素。
class ExpensesScreen extends StatefulWidget {
  final String coupleId;
  final List<String> memberIds;
  final String partnerName;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<ExpenseItem>>? expensesStreamOverride;
  // テストからFirebase Authに触れずに「自分」を差し込むための注入ポイント。
  final String? currentUidOverride;

  const ExpensesScreen({
    super.key,
    required this.coupleId,
    required this.memberIds,
    required this.partnerName,
    this.expensesStreamOverride,
    this.currentUidOverride,
  });

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  ExpenseService? _serviceInstance;
  ExpenseService get _service => _serviceInstance ??= ExpenseService();

  late final Stream<List<ExpenseItem>> _expensesStream =
      widget.expensesStreamOverride ?? _service.watchExpenses(widget.coupleId);

  String get _uid => widget.currentUidOverride ?? FirebaseAuth.instance.currentUser!.uid;

  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _addExpense() async {
    final title = _titleController.text.trim();
    final amount = int.tryParse(_amountController.text.trim());
    if (title.isEmpty || amount == null || amount <= 0) return;
    _titleController.clear();
    _amountController.clear();
    await _service.addExpense(widget.coupleId, title, amount, _uid);
  }

  Future<void> _delete(ExpenseItem expense) => _service.deleteExpense(expense);

  String _payerLabel(String paidBy) => paidBy == _uid ? 'あなた' : widget.partnerName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('割り勘・立て替え')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ExpenseItem>>(
              stream: _expensesStream,
              builder: (context, snap) {
                // hasDataだけを見ていると、権限エラー等でストリームがエラーに
                // 落ちたときに無限ローディングのまま固まる。
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
                final expenses = snap.data!;
                final balance = calculateBalance(expenses, widget.memberIds);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildBalanceCard(balance),
                    ),
                    if (expenses.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text('まだ記録がありません\n立て替えた費用を記録してみましょう',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: expenses.length,
                          itemBuilder: (ctx, i) => _buildTile(expenses[i]),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          _buildInputBar(context),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(ExpenseBalance balance) {
    final text = balance.amount == 0
        ? '精算は完了しています'
        : '${_payerLabel(balance.owedByUid!)}が${_payerLabel(balance.owedToUid!)}に'
            '¥${balance.amount}を渡すと精算されます';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(text, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)),
    );
  }

  Widget _buildTile(ExpenseItem expense) {
    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      onDismissed: (_) => _delete(expense),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.title, style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                )),
                const SizedBox(height: 4),
                Text('${_payerLabel(expense.paidBy)}が支払い',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text('¥${expense.amount}', style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
          )),
        ]),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: const BoxDecoration(
        color: AppColors.navyCard,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _titleController,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: '内容（例: ディナー代）'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: '金額'),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _addExpense,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: appAccent(context), shape: BoxShape.circle),
            child: const Icon(Icons.add, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}
