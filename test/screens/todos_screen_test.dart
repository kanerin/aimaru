import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/todos_screen.dart';
import 'package:aimaru/services/todo_service.dart';

// やりたいことリストがストリームエラーで無限ローディングのまま固まらないことを確かめる。
//
// 本番でfirestore.rulesがデプロイされておらず、todosコレクションの読み取りが
// 権限エラーになったまま画面が永久にスピナーで固まる不具合が実際に発生した
// （StreamBuilderがhasDataだけを見てhasErrorを見ていなかったため）。
void main() {
  Widget wrap(
    Stream<List<TodoItem>> stream, {
    TodoService? todoService,
    NavigatorObserver? observer,
    String currentUid = 'u1',
  }) =>
      MaterialApp(
        navigatorObservers: observer != null ? [observer] : [],
        home: TodosScreen(
          coupleId: 'couple-1',
          todosStreamOverride: stream,
          todoServiceOverride: todoService,
          currentUidOverride: currentUid,
        ),
      );

  final sampleTodo = TodoItem(
    id: 't1',
    coupleId: 'couple-1',
    text: '温泉に行く',
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
  );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが来たら一覧を表示する', (tester) async {
    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      TodoItem(
        id: 't1',
        coupleId: 'couple-1',
        text: '温泉に行く',
        createdBy: 'u1',
        createdAt: DateTime(2026, 1, 1),
      ),
    ]);
    await tester.pump();

    expect(find.text('温泉に行く'), findsOneWidget);

    await controller.close();
  });

  testWidgets('タイトルをタップするとカレンダー登録画面に遷移する', (tester) async {
    final controller = StreamController<List<TodoItem>>();
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(wrap(controller.stream, observer: observer));

    controller.add([sampleTodo]);
    await tester.pump();

    // カレンダー登録画面(EventFormScreen)自体はFirebase初期化なしには
    // ビルドできないため、遷移が発生したこと（pushされたこと）だけを見る。
    await tester.tap(find.text('温泉に行く'));

    expect(observer.pushedCount, 1);

    await controller.close();
  });

  testWidgets('登録済み(addedToCalendar)のTODOは「登録済み」バッジが出て再タップしても遷移しない', (tester) async {
    final controller = StreamController<List<TodoItem>>();
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(wrap(controller.stream, observer: observer));

    controller.add([
      TodoItem(
        id: 't1',
        coupleId: 'couple-1',
        text: '水族館',
        createdBy: 'u1',
        createdAt: DateTime(2026, 1, 1),
        addedToCalendar: true,
      ),
    ]);
    await tester.pump();

    expect(find.text('登録済み'), findsOneWidget);

    // 重複した予定が増えるのを防ぐため、登録済みのものを再タップしても
    // カレンダー登録画面へは遷移しない。
    await tester.tap(find.text('水族館'));
    expect(observer.pushedCount, 0);

    await controller.close();
  });

  testWidgets('未登録のTODOには「登録済み」バッジが出ない', (tester) async {
    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([sampleTodo]);
    await tester.pump();

    expect(find.text('登録済み'), findsNothing);

    await controller.close();
  });

  testWidgets('削除ボタンを押すとTodoServiceのdeleteTodoが呼ばれる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = TodoService(firestore: db, uid: 'u1');
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('todos')
        .doc('t1')
        .set(sampleTodo.toMap());

    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream, todoService: service));

    controller.add([sampleTodo]);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('todos')
        .doc('t1')
        .get();
    expect(doc.exists, isFalse);

    await controller.close();
  });

  testWidgets('チェックボックスを押すとTodoServiceのsetDoneが呼ばれる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = TodoService(firestore: db, uid: 'u1');
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('todos')
        .doc('t1')
        .set(sampleTodo.toMap());

    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream, todoService: service));

    controller.add([sampleTodo]);
    await tester.pump();

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('todos')
        .doc('t1')
        .get();
    expect(doc.data()!['done'], isTrue);

    await controller.close();
  });

  testWidgets('興味ありボタンを押すと自分のuidがlikedByに入る（TodoServiceのtoggleLikeが呼ばれる）', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = TodoService(firestore: db, uid: 'u1');
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('todos')
        .doc('t1')
        .set(sampleTodo.toMap());

    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream, todoService: service, currentUid: 'u1'));

    controller.add([sampleTodo]);
    await tester.pump();

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('todos')
        .doc('t1')
        .get();
    expect(doc.data()!['likedBy'], ['u1']);

    await controller.close();
  });

  testWidgets('自分が既に興味ありを付けているTodoは塗りつぶしハートで表示される', (tester) async {
    final controller = StreamController<List<TodoItem>>();
    await tester.pumpWidget(wrap(controller.stream, currentUid: 'u1'));

    controller.add([
      TodoItem(
        id: 't1',
        coupleId: 'couple-1',
        text: '水族館',
        createdBy: 'u1',
        createdAt: DateTime(2026, 1, 1),
        likedBy: const ['u1', 'u2'],
      ),
    ]);
    await tester.pump();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(find.text('2'), findsOneWidget);

    await controller.close();
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushedCount = 0;

  @override
  void didPush(Route route, Route? previousRoute) {
    // 最初のpushはTodosScreen自体のホームルートなので数えない。
    if (previousRoute != null) pushedCount++;
  }
}
