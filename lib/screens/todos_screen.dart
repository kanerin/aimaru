import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/todo_service.dart';
import '../utils/app_theme.dart';
import 'event_form_screen.dart';

// ── 共有TODO・やりたいことリスト ──────────────────────
// 日付がまだ決まっていないアイデアの置き場。カレンダーの予定にするほど
// 確定していない「今度やりたいこと」を、ペアで持ち寄って眺められるようにする。
class TodosScreen extends StatefulWidget {
  final String coupleId;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<TodoItem>>? todosStreamOverride;
  // テストからfake_cloud_firestore等を差し込むための注入ポイント。
  final TodoService? todoServiceOverride;
  // テストからFirebase Authに触れずに「自分」を差し込むための注入ポイント。
  final String? currentUidOverride;
  const TodosScreen({
    super.key,
    required this.coupleId,
    this.todosStreamOverride,
    this.todoServiceOverride,
    this.currentUidOverride,
  });

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen> {
  // TodoService() は生成時にFirebaseFirestore.instanceへ即座に触れるため、
  // todosStreamOverrideを使うテストではFirebase初期化なしに動けるよう
  // 実際に使うときまで生成を遅らせる。
  TodoService? _todoServiceInstance;
  TodoService get _todoService =>
      _todoServiceInstance ??= widget.todoServiceOverride ?? TodoService();
  final _controller = TextEditingController();

  late final Stream<List<TodoItem>> _todosStream =
      widget.todosStreamOverride ?? _todoService.watchTodos(widget.coupleId);

  String get _uid => widget.currentUidOverride ?? FirebaseAuth.instance.currentUser!.uid;

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

  // タイトルをタップしたときに、そのままカレンダーの新規予定として登録できる
  // ようにする。以前は登録と同時にこのTODO自体を削除していたが、一覧から
  // 突然消えて「登録されたのかわからない」という報告（#69・#72）があった
  // ため、削除せずaddedToCalendarを立てて一覧に残す（_buildTileでバッジ表示）。
  Future<void> _addToCalendar(TodoItem todo) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventFormScreen(
          coupleId: widget.coupleId,
          initialTitle: todo.text,
        ),
      ),
    );
    if (saved == true) {
      await _todoService.markAddedToCalendar(todo);
    }
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
                // hasDataだけを見ていると、権限エラー等でストリームがエラーに
                // 落ちたときに無限ローディングのまま固まる
                // （本番でFirestoreルール未反映のまま実際に発生した）。
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

  // 「興味あり」ボタン。相手が持ち寄った案のうちどれに乗り気かを
  // 一目で伝えられるようにする（Pairyの移行先候補として比較される
  // Pairtoの「やりたいことリスト」いいね機能に近い差別化要素）。
  Widget _buildLikeButton(TodoItem todo) {
    final liked = todo.likedBy.contains(_uid);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (todo.likedBy.isNotEmpty)
          Text('${todo.likedBy.length}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        IconButton(
          icon: Icon(
            liked ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: liked ? Colors.redAccent : AppColors.textMuted,
          ),
          tooltip: '興味あり',
          onPressed: () => _todoService.toggleLike(todo, _uid),
        ),
      ],
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        // CheckboxListTile（ListTile系）はMaterial祖先の上でないと
        // タップ時のインクスプラッシュが描画されない
        // （Containerの背景色に隠れて見えなくなるとFlutterが警告する）ため、
        // 背景色はここではなくMaterialに持たせる。
        child: Material(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Checkbox(
                  value: todo.done,
                  onChanged: (v) => _todoService.setDone(todo, v ?? false),
                  activeColor: appAccent(context),
                ),
                // タイトルをタップするとカレンダー登録に遷移する
                // （チェックボックス・削除ボタンとタップ領域を分ける）。
                // 登録済みのものを再タップすると重複した予定が増えてしまう
                // ため、登録済みならタップを無効にしてバッジ表示だけにする。
                Expanded(
                  child: InkWell(
                    onTap: todo.addedToCalendar ? null : () => _addToCalendar(todo),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              todo.text,
                              style: TextStyle(
                                fontSize: 14,
                                color: todo.done ? AppColors.textMuted : AppColors.textPrimary,
                                decoration: todo.done ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                          if (todo.addedToCalendar) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: appAccent(context).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.event_available, size: 11, color: appAccent(context)),
                                const SizedBox(width: 3),
                                Text('登録済み',
                                    style: TextStyle(fontSize: 10.5, color: appAccent(context))),
                              ]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                _buildLikeButton(todo),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.textMuted),
                  tooltip: '削除',
                  onPressed: () => _delete(todo),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
