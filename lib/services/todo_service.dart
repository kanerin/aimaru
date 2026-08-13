import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class TodoService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  TodoService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _todosRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('todos');

  // ── TODOを追加 ────────────────────────────────────
  Future<TodoItem> addTodo(String coupleId, String text) async {
    final ref = _todosRef(coupleId).doc();
    final todo = TodoItem(
      id:        ref.id,
      coupleId:  coupleId,
      text:      text,
      createdBy: _uid,
      createdAt: DateTime.now(),
    );
    await ref.set(todo.toMap());
    return todo;
  }

  // ── 完了/未完了を切り替え ─────────────────────────
  Future<void> setDone(TodoItem todo, bool done) async {
    await _todosRef(todo.coupleId).doc(todo.id).update({'done': done});
  }

  // ── TODOを削除 ────────────────────────────────────
  Future<void> deleteTodo(TodoItem todo) async {
    await _todosRef(todo.coupleId).doc(todo.id).delete();
  }

  // ── 一覧をリアルタイム取得（未完了→完了、それぞれ新しい順）───
  Stream<List<TodoItem>> watchTodos(String coupleId) {
    return _todosRef(coupleId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          final todos = snap.docs.map(TodoItem.fromDoc).toList();
          todos.sort((a, b) {
            if (a.done != b.done) return a.done ? 1 : -1;
            return b.createdAt.compareTo(a.createdAt);
          });
          return todos;
        });
  }
}
