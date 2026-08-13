import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/todo_service.dart';
import '../utils/app_theme.dart';

// ── 共有TODO・やりたいことリスト ──────────────────────
// 日付がまだ決まっていないアイデアの置き場。カレンダーの予定にするほど
// 確定していない「今度やりたいこと」を、ペアで持ち寄って眺められるようにする。
class TodosScreen extends StatefulWidget {
  final String coupleId;
  const TodosScreen({super.key, required this.coupleId});

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen> {
  final _todoService = TodoService();
  final _controller   = TextEditingController();

  late final Stream<List<TodoItem>> _todosStream =
      _todoService.watchTodos(widget.coupleId);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await _todoService.addTodo(widget.coupleId, text);
  }

  Future<void> _delete(TodoItem todo) async {
    await _todoService.deleteTodo(todo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('やりたいことリスト')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<TodoItem>>(
              stream: _todosStream,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return Center(child: CircularProgressIndicator(color: appAccent(context)));
                }
                final todos = snap.data!;
                if (todos.isEmpty) {
                  return const Center(
                    child: Text('まだ何もありません\n今度やりたいことを書いてみましょう',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: todos.length,
                  itemBuilder: (ctx, i) => _buildTile(todos[i]),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: const BoxDecoration(
              color: AppColors.navyCard,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '今度やりたいことを入力...',
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _add,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: appAccent(context), shape: BoxShape.circle),
                  child: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(TodoItem todo) {
    return Dismissible(
      key: ValueKey(todo.id),
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
      onDismissed: (_) => _delete(todo),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: CheckboxListTile(
          value: todo.done,
          onChanged: (v) => _todoService.setDone(todo, v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          activeColor: appAccent(context),
          title: Text(
            todo.text,
            style: TextStyle(
              fontSize: 14,
              color: todo.done ? AppColors.textMuted : AppColors.textPrimary,
              decoration: todo.done ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }
}
