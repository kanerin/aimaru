import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/utils/expense_balance.dart';

// 割り勘の精算額計算。「多く払った方が受け取るべき額」を正しく出せているかを検証する。
void main() {
  const uidA = 'user-a';
  const uidB = 'user-b';
  const memberIds = [uidA, uidB];

  ExpenseItem buildExpense({required int amount, required String paidBy}) => ExpenseItem(
        id: 'e1',
        coupleId: 'couple-1',
        title: 'ディナー代',
        amount: amount,
        paidBy: paidBy,
        createdBy: paidBy,
        createdAt: DateTime(2026, 8, 1),
      );

  group('calculateBalance', () {
    test('記録が無ければ精算不要', () {
      final balance = calculateBalance([], memberIds);

      expect(balance.amount, 0);
      expect(balance.owedByUid, isNull);
      expect(balance.owedToUid, isNull);
    });

    test('片方だけが払っていれば、その半額をもう片方が渡す', () {
      final balance = calculateBalance(
        [buildExpense(amount: 4000, paidBy: uidA)],
        memberIds,
      );

      expect(balance.owedByUid, uidB);
      expect(balance.owedToUid, uidA);
      expect(balance.amount, 2000);
    });

    test('払った額が同じなら精算不要', () {
      final balance = calculateBalance(
        [
          buildExpense(amount: 3000, paidBy: uidA),
          buildExpense(amount: 3000, paidBy: uidB),
        ],
        memberIds,
      );

      expect(balance.amount, 0);
    });

    test('複数件の記録を合算してから差額を出す', () {
      final balance = calculateBalance(
        [
          buildExpense(amount: 4000, paidBy: uidA),
          buildExpense(amount: 1000, paidBy: uidA),
          buildExpense(amount: 2000, paidBy: uidB),
        ],
        memberIds,
      );

      // A: 5000, B: 2000 → 差額3000の半分をBがAに渡す
      expect(balance.owedByUid, uidB);
      expect(balance.owedToUid, uidA);
      expect(balance.amount, 1500);
    });

    test('差額が1円なら端数を切り捨てて精算不要扱いにする', () {
      final balance = calculateBalance(
        [buildExpense(amount: 1, paidBy: uidA)],
        memberIds,
      );

      expect(balance.amount, 0);
    });

    test('メンバーが2人でなければ精算額を計算しない', () {
      final balance = calculateBalance(
        [buildExpense(amount: 4000, paidBy: uidA)],
        [uidA],
      );

      expect(balance.amount, 0);
    });
  });
}
