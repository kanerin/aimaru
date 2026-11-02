import 'budget_plan_diff.dart';

// ── 家計プランの変更履歴の1件（誰が・いつ・何を）────────────────
// プラン本体とは別のコレクション（couples/{coupleId}/budgetHistory）に
// 追記だけで残す。プランのサブコレクションにしないのは、シミュレーションを
// 削除しても「削除した」という履歴まで一緒に消えてしまわないようにするため。
enum BudgetHistoryAction {
  created,   // プランを作成
  updated,   // 内容を変更
  activated, // 確定プランに設定
  deleted,   // シミュレーションを削除
}

extension BudgetHistoryActionLabel on BudgetHistoryAction {
  String get label => switch (this) {
    BudgetHistoryAction.created   => '作成',
    BudgetHistoryAction.updated   => '変更',
    BudgetHistoryAction.activated => '確定プランに設定',
    BudgetHistoryAction.deleted   => '削除',
  };

  static BudgetHistoryAction parse(String? name) => BudgetHistoryAction.values
      .firstWhere((a) => a.name == name, orElse: () => BudgetHistoryAction.updated);
}

class BudgetHistoryEntry {
  final String id;
  final String planId;
  final String planName;
  final BudgetHistoryAction action;
  final String changedBy; // uid
  // サーバー時刻で記録する。書き込み直後のローカル反映ではまだ確定しておらずnull。
  final DateTime? changedAt;
  final List<BudgetChange> changes;

  const BudgetHistoryEntry({
    required this.id,
    required this.planId,
    required this.planName,
    required this.action,
    required this.changedBy,
    this.changedAt,
    this.changes = const [],
  });
}
