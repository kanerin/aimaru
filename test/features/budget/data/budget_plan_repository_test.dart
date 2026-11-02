import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/data/budget_plan_mapper.dart';
import 'package:aimaru/features/budget/data/budget_plan_repository.dart';
import 'package:aimaru/features/budget/domain/budget_history_entry.dart';
import 'package:aimaru/features/budget/domain/budget_plan.dart';

import '../../../helpers/budget_fixtures.dart';

// 家計プランの読み書き（確定プランは1つ・変更履歴をプランと同じバッチで残す）を
// Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late BudgetPlanRepository repo;

  const coupleId = 'couple-1';
  const meUid = 'user-me';

  CollectionReference<Map<String, dynamic>> plansRef() =>
      db.collection('couples').doc(coupleId).collection('budgetPlans');
  CollectionReference<Map<String, dynamic>> historyRef() =>
      db.collection('couples').doc(coupleId).collection('budgetHistory');

  Future<List<Map<String, dynamic>>> history() async =>
      (await historyRef().get()).docs.map((d) => d.data()).toList();

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = BudgetPlanRepository(firestore: db, uid: meUid);
  });

  group('Firestoreとの変換', () {
    test('保存した内容をそのまま読み戻せる', () async {
      final saved = await repo.createPlan(coupleId, realCouplePlan(), activate: true);

      final doc = await plansRef().doc(saved.id).get();
      final loaded = BudgetPlanMapper.fromDoc(doc);

      expect(loaded.name, '確定プラン');
      expect(loaded.isActive, isTrue);
      expect(loaded.members.map((m) => m.monthlyTakeHome), [180000, 400000]);
      expect(loaded.members[1].bonuses.first.payDay, 30);
      expect(loaded.sharedExpenses.map((e) => e.monthlyAmount), [110000, 10000, 15000, 70000]);
      expect(loaded.sharedExpenses.first.category, ExpenseCategory.housing);
      expect(loaded.offsets.single.receivedBy, memberB);
      expect(loaded.livingAccount.contributions, {memberA: 60000, memberB: 150000});
      expect(loaded.livingAccount.surplusHandling, SurplusHandling.keep);
      expect(loaded.savingsGoal.targetAmount, 8000000);
      expect(loaded.savingsGoal.deadline, DateTime(2029, 10, 31));
      expect(loaded.savingsGoal.bonusContributions, hasLength(2));
      expect(loaded.createdBy, meUid);
      expect(loaded.updatedBy, meUid);
      expect(loaded.updatedAt, isNotNull);
      expect(doc.data()!['schemaVersion'], BudgetPlanMapper.schemaVersion);
    });

    test('毎月の貯金の決め方（比率・固定するメンバー）も保存して読み戻せる', () async {
      final plan = realCouplePlan();
      final saved = await repo.createPlan(
        coupleId,
        plan.copyWith(
          savingsGoal: plan.savingsGoal.copyWith(
            contributionMode: SavingsContributionMode.fixed,
            contributionWeights: {memberA: 40, memberB: 60},
            fixedMemberIds: [memberA],
          ),
        ),
        activate: true,
      );

      final loaded = BudgetPlanMapper.fromDoc(await plansRef().doc(saved.id).get());
      expect(loaded.savingsGoal.contributionMode, SavingsContributionMode.fixed);
      expect(loaded.savingsGoal.contributionWeights, {memberA: 40, memberB: 60});
      expect(loaded.savingsGoal.fixedMemberIds, [memberA]);
    });

    test('決め方が無い既存のプランは、従来どおり手入力（カスタム）として読む', () {
      final plan = BudgetPlanMapper.fromMap('p1', {
        'name': '既存のプラン',
        'savingsGoal': {'targetAmount': 8000000, 'monthlyContributions': {memberA: 50000}},
      });

      expect(plan.savingsGoal.contributionMode, SavingsContributionMode.custom);
      expect(plan.savingsGoal.monthlyContributions, {memberA: 50000});
      expect(plan.savingsGoal.fixedMemberIds, isEmpty);
    });

    test('金額がdoubleで入っていても、フィールドが欠けていても読める', () {
      final plan = BudgetPlanMapper.fromMap('p1', {
        'name': '古いプラン',
        'members': [
          {'memberId': memberA, 'displayName': 'A', 'monthlyTakeHome': 180000.0},
        ],
        'sharedExpenses': [
          {'label': '家賃', 'monthlyAmount': 110000, 'category': '未知のカテゴリ'},
        ],
      });

      expect(plan.isActive, isFalse);
      expect(plan.members.single.monthlyTakeHome, 180000);
      expect(plan.sharedExpenses.single.id, isNotEmpty);
      expect(plan.sharedExpenses.single.category, ExpenseCategory.other);
      expect(plan.livingAccount.mode, LivingAccountMode.fixed);
      expect(plan.savingsGoal.targetAmount, 0);
    });
  });

  group('作成', () {
    test('シミュレーションとして作ると確定プランは変わらない', () async {
      final active = await repo.createPlan(coupleId, realCouplePlan(), activate: true);

      final sim = await repo.createPlan(
        coupleId,
        realCouplePlan().duplicateAsDraft(name: '家賃上げた場合'),
      );

      expect(sim.isActive, isFalse);
      expect((await plansRef().doc(active.id).get()).data()!['isActive'], isTrue);
      expect((await plansRef().doc(sim.id).get()).data()!['isActive'], isFalse);
    });

    test('作成は履歴に「作成」、確定として作れば「確定プランに設定」も残す', () async {
      await repo.createPlan(coupleId, realCouplePlan(), activate: true);

      final actions = (await history()).map((h) => h['action']).toList();
      expect(actions, containsAll(['created', 'activated']));
      expect((await history()).every((h) => h['changedBy'] == meUid), isTrue);
    });
  });

  group('変更', () {
    test('変更した内容と、誰が変えたかを履歴に残す', () async {
      final saved = await repo.createPlan(coupleId, realCouplePlan(), activate: true);
      final partnerRepo = BudgetPlanRepository(firestore: db, uid: 'user-partner');

      await partnerRepo.updatePlan(
        coupleId,
        before: saved,
        after: saved.copyWith(sharedExpenses: [
          saved.sharedExpenses[0].copyWith(monthlyAmount: 120000),
          ...saved.sharedExpenses.skip(1),
        ]),
      );

      final doc = (await plansRef().doc(saved.id).get()).data()!;
      expect(doc['updatedBy'], 'user-partner');
      expect(doc['createdBy'], meUid, reason: '作成者は書き換えない');
      expect(doc['isActive'], isTrue, reason: '内容の変更で確定フラグは変えない');
      expect((doc['sharedExpenses'] as List).first['monthlyAmount'], 120000);

      final updates = (await history()).where((h) => h['action'] == 'updated').toList();
      expect(updates, hasLength(1));
      expect(updates.single['changedBy'], 'user-partner');
      expect(updates.single['planId'], saved.id);
      expect(updates.single['changes'], [
        {'label': '家賃', 'before': '110,000円', 'after': '120,000円'},
      ]);
    });

    test('何も変わっていなければ書き込まない（相手への通知・履歴を増やさない）', () async {
      final saved = await repo.createPlan(coupleId, realCouplePlan(), activate: true);
      final before = await history();

      await repo.updatePlan(coupleId, before: saved, after: saved);

      expect(await history(), hasLength(before.length));
    });
  });

  group('確定プランの切り替え', () {
    test('確定にすると、それまでの確定プランは外れて常に1つだけになる', () async {
      final active = await repo.createPlan(coupleId, realCouplePlan(), activate: true);
      final sim = await repo.createPlan(coupleId, realCouplePlan().duplicateAsDraft(name: '案'));

      await repo.activatePlan(coupleId, sim);

      final actives = await plansRef().where('isActive', isEqualTo: true).get();
      expect(actives.docs.map((d) => d.id), [sim.id]);
      expect((await plansRef().doc(active.id).get()).data()!['isActive'], isFalse);

      final activations = (await history()).where((h) => h['action'] == 'activated' && h['planId'] == sim.id);
      expect(activations, hasLength(1));
    });

    test('確定として新規作成しても、確定プランは1つだけ', () async {
      await repo.createPlan(coupleId, realCouplePlan(), activate: true);
      final second = await repo.createPlan(coupleId, realCouplePlan(name: '新しい家計'), activate: true);

      final actives = await plansRef().where('isActive', isEqualTo: true).get();
      expect(actives.docs.map((d) => d.id), [second.id]);
    });
  });

  group('削除', () {
    test('シミュレーションは削除でき、削除したことが履歴に残る', () async {
      final sim = await repo.createPlan(coupleId, realCouplePlan().duplicateAsDraft(name: '案'));

      await repo.deletePlan(coupleId, sim);

      expect((await plansRef().doc(sim.id).get()).exists, isFalse);
      final deletions = (await history()).where((h) => h['action'] == 'deleted');
      expect(deletions.single['planName'], '案');
    });

    test('確定プランは削除できない', () async {
      final active = await repo.createPlan(coupleId, realCouplePlan(), activate: true);

      expect(() => repo.deletePlan(coupleId, active), throwsStateError);
      expect((await plansRef().doc(active.id).get()).exists, isTrue);
    });
  });

  group('購読', () {
    test('一覧は確定プランが先頭', () async {
      await repo.createPlan(coupleId, realCouplePlan().duplicateAsDraft(name: '案1'));
      await repo.createPlan(coupleId, realCouplePlan(), activate: true);
      await repo.createPlan(coupleId, realCouplePlan().duplicateAsDraft(name: '案2'));

      final plans = await repo.watchPlans(coupleId).first;

      expect(plans, hasLength(3));
      expect(plans.first.isActive, isTrue);
      expect(plans.first.name, '確定プラン');
    });

    test('確定プランだけを購読できる（無ければnull）', () async {
      expect(await repo.watchActivePlan(coupleId).first, isNull);

      final active = await repo.createPlan(coupleId, realCouplePlan(), activate: true);

      expect((await repo.watchActivePlan(coupleId).first)?.id, active.id);
    });

    test('履歴を新しい順に読める', () async {
      final saved = await repo.createPlan(coupleId, realCouplePlan(), activate: true);
      await repo.updatePlan(
        coupleId,
        before: saved,
        after: saved.copyWith(name: '確定プラン（2027年）'),
      );

      final entries = await repo.watchHistory(coupleId).first;

      expect(entries, isNotEmpty);
      final update = entries.firstWhere((e) => e.action == BudgetHistoryAction.updated);
      expect(update.changedBy, meUid);
      expect(update.changes.single.describe(), 'プラン名: 確定プラン → 確定プラン（2027年）');
    });
  });
}
