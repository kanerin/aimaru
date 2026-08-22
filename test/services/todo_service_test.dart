import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/services/todo_service.dart';

// 共有TODOのCRUDと並び順を、Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late TodoService service;

  const coupleId = 'couple-1';
  const meUid    = 'user-me';

  CollectionReference<Map<String, dynamic>> todosRef() =>
      db.collection('couples').doc(coupleId).collection('todos');

  setUp(() {
    db = FakeFirebaseFirestore();
    service = TodoService(firestore: db, uid: meUid);
  });

  group('TODOの作成', () {
    test('createdByに操作者が入り、未完了で作られる', () async {
      final created = await service.addTodo(coupleId, '水族館に行く');

      expect(created.id, isNotEmpty);
      expect(created.createdBy, meUid);
      expect(created.done, isFalse);

      final data = (await todosRef().doc(created.id).get()).data()!;
      expect(data['text'], '水族館に行く');
      expect(data['createdBy'], meUid);
      expect(data['done'], false);
    });
  });

  group('完了の切り替え', () {
    test('完了にすると保存される', () async {
      final created = await service.addTodo(coupleId, '温泉旅行');

      await service.setDone(created, true);

      final data = (await todosRef().doc(created.id).get()).data()!;
      expect(data['done'], true);
    });

    test('未完了に戻すと保存される', () async {
      final created = await service.addTodo(coupleId, '花火大会');
      await service.setDone(created, true);

      await service.setDone(created, false);

      final data = (await todosRef().doc(created.id).get()).data()!;
      expect(data['done'], false);
    });
  });

  group('カレンダー登録済みのマーク', () {
    test('markAddedToCalendarで立てるとaddedToCalendarがtrueになる', () async {
      final created = await service.addTodo(coupleId, '花見');
      expect(created.addedToCalendar, isFalse);

      await service.markAddedToCalendar(created);

      final data = (await todosRef().doc(created.id).get()).data()!;
      expect(data['addedToCalendar'], true);
    });

    test('マークしても削除はされない（以前は削除していた）', () async {
      final created = await service.addTodo(coupleId, '紅葉狩り');

      await service.markAddedToCalendar(created);

      expect((await todosRef().doc(created.id).get()).exists, isTrue);
    });
  });

  group('興味ありの切り替え', () {
    test('未反応から押すとlikedByに自分のuidが入る', () async {
      final created = await service.addTodo(coupleId, '花火大会');
      expect(created.likedBy, isEmpty);

      await service.toggleLike(created, meUid);

      final data = (await todosRef().doc(created.id).get()).data()!;
      expect(data['likedBy'], [meUid]);
    });

    test('既に反応済みなら押すと外れる', () async {
      final created = await service.addTodo(coupleId, '紅葉狩り');
      final liked = TodoItem(
        id: created.id,
        coupleId: created.coupleId,
        text: created.text,
        createdBy: created.createdBy,
        createdAt: created.createdAt,
        likedBy: [meUid],
      );

      await service.toggleLike(liked, meUid);

      final data = (await todosRef().doc(created.id).get()).data()!;
      expect(data['likedBy'], isEmpty);
    });

    test('2人分の反応が独立して積み上がる', () async {
      const partnerUid = 'user-partner';
      final created = await service.addTodo(coupleId, 'キャンプ');

      await service.toggleLike(created, meUid);
      final likedByMe = TodoItem(
        id: created.id,
        coupleId: created.coupleId,
        text: created.text,
        createdBy: created.createdBy,
        createdAt: created.createdAt,
        likedBy: [meUid],
      );
      await service.toggleLike(likedByMe, partnerUid);

      final data = (await todosRef().doc(created.id).get()).data()!;
      expect(Set<String>.from(data['likedBy']), {meUid, partnerUid});
    });
  });

  group('削除', () {
    test('削除するとドキュメントが消える', () async {
      final created = await service.addTodo(coupleId, 'キャンプ');

      await service.deleteTodo(created);

      expect((await todosRef().doc(created.id).get()).exists, isFalse);
    });
  });

  group('一覧の取得', () {
    // addTodoはDateTime.now()でcreatedAtを決めるため、順序を確定させたいテストでは
    // 作成後にcreatedAtを明示的な値へ上書きする（実行タイミングに依存させない）。
    Future<void> setCreatedAt(String id, DateTime at) =>
        todosRef().doc(id).update({'createdAt': Timestamp.fromDate(at)});

    test('未完了が先、それぞれ新しい順に並ぶ', () async {
      final oldDone = await service.addTodo(coupleId, '古い完了済み');
      await service.setDone(oldDone, true);
      await setCreatedAt(oldDone.id, DateTime(2026, 8, 1));

      final recentDone = await service.addTodo(coupleId, '新しい完了済み');
      await service.setDone(recentDone, true);
      await setCreatedAt(recentDone.id, DateTime(2026, 8, 3));

      final oldTodo = await service.addTodo(coupleId, '古い未完了');
      await setCreatedAt(oldTodo.id, DateTime(2026, 8, 2));

      final recentTodo = await service.addTodo(coupleId, '新しい未完了');
      await setCreatedAt(recentTodo.id, DateTime(2026, 8, 4));

      final todos = await service.watchTodos(coupleId).first;

      expect(todos.map((t) => t.text),
          ['新しい未完了', '古い未完了', '新しい完了済み', '古い完了済み']);
    });
  });
}
