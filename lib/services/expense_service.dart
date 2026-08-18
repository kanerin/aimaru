import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class ExpenseService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  ExpenseService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _expensesRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('expenses');

  // ── 立て替えを記録 ────────────────────────────────
  Future<ExpenseItem> addExpense(String coupleId, String title, int amount, String paidBy) async {
    final ref = _expensesRef(coupleId).doc();
    final expense = ExpenseItem(
      id:        ref.id,
      coupleId:  coupleId,
      title:     title,
      amount:    amount,
      paidBy:    paidBy,
      createdBy: _uid,
      createdAt: DateTime.now(),
    );
    await ref.set(expense.toMap());
    return expense;
  }

  // ── 記録を削除 ────────────────────────────────────
  Future<void> deleteExpense(ExpenseItem expense) async {
    await _expensesRef(expense.coupleId).doc(expense.id).delete();
  }

  // ── 精算を記録 ────────────────────────────────────
  // owedByUidがowedToUidにamountを渡したことを記録し、以降の精算額計算を
  // 0円に戻す（履歴は削除せず「精算」として残す）。
  Future<ExpenseItem> recordSettlement(String coupleId, String owedByUid, int amount) async {
    final ref = _expensesRef(coupleId).doc();
    final settlement = ExpenseItem(
      id:           ref.id,
      coupleId:     coupleId,
      title:        '精算',
      amount:       amount,
      paidBy:       owedByUid,
      createdBy:    _uid,
      createdAt:    DateTime.now(),
      isSettlement: true,
    );
    await ref.set(settlement.toMap());
    return settlement;
  }

  // ── 一覧をリアルタイム取得（新しい順）────────────────
  Stream<List<ExpenseItem>> watchExpenses(String coupleId) {
    return _expensesRef(coupleId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ExpenseItem.fromDoc).toList());
  }
}
