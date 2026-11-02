import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/budget_history_entry.dart';
import '../domain/budget_plan.dart';
import '../domain/budget_plan_diff.dart';
import 'budget_plan_mapper.dart';

// ── 家計プランの読み書き ─────────────────────────────────
// couples/{coupleId}/budgetPlans/{planId}   … プラン本体（確定プラン + シミュレーション）
// couples/{coupleId}/budgetHistory/{id}     … 変更履歴（追記のみ。誰が・いつ・何を）
//
// 書き込みはプランと履歴を必ず同じバッチで行う。片方だけ成功すると
// 「変わったのに履歴が無い」「履歴だけあって変わっていない」になるため。
//
// 確定プラン（isActive）は1カップル1つ。確定にするときは、今の確定プランの
// フラグを同じバッチで外す。
class BudgetPlanRepository {
  // 引数なしで生成すると本番のFirebaseを使う（既存のサービスと同じ設計）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  BudgetPlanRepository({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  // 1回の変更で履歴に残す差分の上限（ドキュメントの肥大化を防ぐ）
  static const maxChangesPerEntry = 100;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> _plans(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('budgetPlans');

  CollectionReference<Map<String, dynamic>> _history(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('budgetHistory');

  // ── 一覧（確定プランが先頭、残りは更新の新しい順）──────────
  Stream<List<BudgetPlan>> watchPlans(String coupleId) =>
      _plans(coupleId).snapshots().map((snap) {
        final plans = snap.docs.map(BudgetPlanMapper.fromDoc).toList();
        plans.sort((a, b) {
          if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
          // サーバー時刻がまだ確定していない（今まさに書いた）ものを最新扱いにする
          final at = a.updatedAt ?? DateTime(9999);
          final bt = b.updatedAt ?? DateTime(9999);
          return bt.compareTo(at);
        });
        return plans;
      });

  // ── 確定プランだけ（カレンダーのボーナス表示用）────────────
  Stream<BudgetPlan?> watchActivePlan(String coupleId) => _plans(coupleId)
      .where('isActive', isEqualTo: true)
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isEmpty ? null : BudgetPlanMapper.fromDoc(snap.docs.first));

  // ── 新規作成（ひな型からの作成・シミュレーションの保存）────────
  // activate=true なら確定プランとして作る（今の確定プランは外す）。
  Future<BudgetPlan> createPlan(String coupleId, BudgetPlan plan, {bool activate = false}) async {
    final ref = _plans(coupleId).doc();
    final batch = _db.batch();
    if (activate) await _deactivateOthers(coupleId, batch, exceptId: ref.id);
    batch.set(ref, {
      ...BudgetPlanMapper.contentToMap(plan),
      'isActive':  activate,
      'createdBy': _uid,
      'updatedBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _addHistory(batch, coupleId, planId: ref.id, planName: plan.name, action: BudgetHistoryAction.created);
    if (activate) {
      _addHistory(batch, coupleId, planId: ref.id, planName: plan.name, action: BudgetHistoryAction.activated);
    }
    await batch.commit();
    return plan.copyWith(id: ref.id, isActive: activate, createdBy: _uid, updatedBy: _uid);
  }

  // ── 内容の変更 ───────────────────────────────────
  // 何も変わっていなければ書き込まない（相手への通知・履歴を無駄に増やさない）。
  // 戻り値は保存後のプラン。
  Future<BudgetPlan> updatePlan(
    String coupleId, {
    required BudgetPlan before,
    required BudgetPlan after,
  }) async {
    assert(before.id == after.id && after.isSaved, '保存済みのプラン同士で比べること');
    final changes = diffBudgetPlans(before, after);
    if (changes.isEmpty) return after;

    final batch = _db.batch();
    // isActiveはここでは変えない（確定の切り替えはactivatePlanだけが行う）
    batch.update(_plans(coupleId).doc(after.id), {
      ...BudgetPlanMapper.contentToMap(after),
      'updatedBy': _uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _addHistory(
      batch, coupleId,
      planId: after.id,
      planName: after.name,
      action: BudgetHistoryAction.updated,
      changes: changes,
    );
    await batch.commit();
    return after.copyWith(updatedBy: _uid);
  }

  // ── 確定プランにする ────────────────────────────────
  Future<void> activatePlan(String coupleId, BudgetPlan plan) async {
    assert(plan.isSaved, '確定にする前に保存すること');
    final batch = _db.batch();
    await _deactivateOthers(coupleId, batch, exceptId: plan.id);
    batch.update(_plans(coupleId).doc(plan.id), {
      'isActive':  true,
      'updatedBy': _uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _addHistory(batch, coupleId, planId: plan.id, planName: plan.name, action: BudgetHistoryAction.activated);
    await batch.commit();
  }

  // ── シミュレーションの削除 ────────────────────────────
  // 確定プランは消せない（消すと「今の家計」が無くなる）。別のプランを
  // 確定にしてから消してもらう。Firestoreのルールでも同じ制限をかけている。
  Future<void> deletePlan(String coupleId, BudgetPlan plan) async {
    if (plan.isActive) {
      throw StateError('確定プランは削除できません');
    }
    final batch = _db.batch();
    batch.delete(_plans(coupleId).doc(plan.id));
    _addHistory(batch, coupleId, planId: plan.id, planName: plan.name, action: BudgetHistoryAction.deleted);
    await batch.commit();
  }

  // ── 変更履歴（新しい順）──────────────────────────────
  Stream<List<BudgetHistoryEntry>> watchHistory(String coupleId, {int limit = 50}) => _history(coupleId)
      .orderBy('changedAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((snap) => snap.docs.map(BudgetPlanMapper.historyFromDoc).toList());

  Future<void> _deactivateOthers(String coupleId, WriteBatch batch, {required String exceptId}) async {
    final actives = await _plans(coupleId).where('isActive', isEqualTo: true).get();
    for (final doc in actives.docs) {
      if (doc.id == exceptId) continue;
      batch.update(doc.reference, {
        'isActive':  false,
        'updatedBy': _uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _addHistory(
    WriteBatch batch,
    String coupleId, {
    required String planId,
    required String planName,
    required BudgetHistoryAction action,
    List<BudgetChange> changes = const [],
  }) {
    batch.set(_history(coupleId).doc(), {
      'planId':    planId,
      'planName':  planName,
      'action':    action.name,
      'changedBy': _uid,
      'changedAt': FieldValue.serverTimestamp(),
      'changes':   [for (final c in changes.take(maxChangesPerEntry)) c.toMap()],
    });
  }
}
