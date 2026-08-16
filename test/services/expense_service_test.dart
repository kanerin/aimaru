import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/expense_service.dart';

// 割り勘・立て替え記録のCRUDと並び順を、Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late ExpenseService service;

  const coupleId = 'couple-1';
  const meUid    = 'user-me';
  const partnerUid = 'user-partner';

  CollectionReference<Map<String, dynamic>> expensesRef() =>
      db.collection('couples').doc(coupleId).collection('expenses');

  setUp(() {
    db = FakeFirebaseFirestore();
    service = ExpenseService(firestore: db, uid: meUid);
  });

  group('記録の作成', () {
    test('createdByに操作者が入り、指定した支払者・金額で作られる', () async {
      final created = await service.addExpense(coupleId, 'ディナー代', 4000, partnerUid);

      expect(created.id, isNotEmpty);
      expect(created.createdBy, meUid);
      expect(created.paidBy, partnerUid);
      expect(created.amount, 4000);

      final data = (await expensesRef().doc(created.id).get()).data()!;
      expect(data['title'], 'ディナー代');
      expect(data['amount'], 4000);
      expect(data['paidBy'], partnerUid);
      expect(data['createdBy'], meUid);
    });
  });

  group('削除', () {
    test('削除するとドキュメントが消える', () async {
      final created = await service.addExpense(coupleId, '映画代', 3600, meUid);

      await service.deleteExpense(created);

      expect((await expensesRef().doc(created.id).get()).exists, isFalse);
    });
  });

  group('一覧の取得', () {
    Future<void> setCreatedAt(String id, DateTime at) =>
        expensesRef().doc(id).update({'createdAt': Timestamp.fromDate(at)});

    test('新しい順に並ぶ', () async {
      final oldest = await service.addExpense(coupleId, '古い記録', 1000, meUid);
      await setCreatedAt(oldest.id, DateTime(2026, 8, 1));

      final newest = await service.addExpense(coupleId, '新しい記録', 2000, partnerUid);
      await setCreatedAt(newest.id, DateTime(2026, 8, 3));

      final middle = await service.addExpense(coupleId, '真ん中の記録', 3000, meUid);
      await setCreatedAt(middle.id, DateTime(2026, 8, 2));

      final expenses = await service.watchExpenses(coupleId).first;

      expect(expenses.map((e) => e.title), ['新しい記録', '真ん中の記録', '古い記録']);
    });
  });
}
