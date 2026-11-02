import 'package:flutter/material.dart';

import '../../../utils/app_theme.dart';
import '../data/budget_plan_repository.dart';
import '../domain/budget_history_entry.dart';
import 'budget_widgets.dart';

// ── 家計の変更履歴（誰が・いつ・何を変えたか）──────────────────
class BudgetHistoryScreen extends StatefulWidget {
  final String coupleId;
  // uid → 表示名（家計プランに登録された名前）
  final Map<String, String> memberNames;
  // テスト用の注入ポイント
  final Stream<List<BudgetHistoryEntry>>? historyStreamOverride;
  final BudgetPlanRepository? repositoryOverride;

  const BudgetHistoryScreen({
    super.key,
    required this.coupleId,
    required this.memberNames,
    this.historyStreamOverride,
    this.repositoryOverride,
  });

  @override
  State<BudgetHistoryScreen> createState() => _BudgetHistoryScreenState();
}

class _BudgetHistoryScreenState extends State<BudgetHistoryScreen> {
  late final Stream<List<BudgetHistoryEntry>> _stream = widget.historyStreamOverride ??
      (widget.repositoryOverride ?? BudgetPlanRepository()).watchHistory(widget.coupleId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('家計の変更履歴')),
      body: StreamBuilder<List<BudgetHistoryEntry>>(
        stream: _stream,
        builder: (context, snap) {
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
          final entries = snap.data!;
          if (entries.isEmpty) {
            return const Center(
              child: Text('まだ変更履歴はありません',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: entries.length,
            itemBuilder: (_, i) => _HistoryTile(entry: entries[i], memberNames: widget.memberNames),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final BudgetHistoryEntry entry;
  final Map<String, String> memberNames;

  const _HistoryTile({required this.entry, required this.memberNames});

  @override
  Widget build(BuildContext context) {
    final who = memberNames[entry.changedBy] ?? 'メンバー';
    final at = entry.changedAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '$whoが「${entry.planName}」を${entry.action.label}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ),
            Text(at == null ? '保存中…' : formatDateTimeShort(at),
                style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          ]),
          if (entry.changes.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final c in entry.changes)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('・${c.describe()}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecond, height: 1.5)),
              ),
          ],
        ],
      ),
    );
  }
}
