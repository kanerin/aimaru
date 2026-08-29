import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/shopping_list_service.dart';

// 買い物リストのCRUD・購入済みの一括削除・並び順を、
// Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late ShoppingListService service;

  const coupleId = 'couple-1';
  const meUid    = 'user-me';

  CollectionReference<Map<String, dynamic>> itemsRef() =>
      db.collection('couples').doc(coupleId).collection('shoppingItems');

  setUp(() {
    db = FakeFirebaseFirestore();
    service = ShoppingListService(firestore: db, uid: meUid);
  });

  group('アイテムの作成', () {
    test('createdByに操作者が入り、未購入・数量なしで作られる', () async {
      final created = await service.addItem(coupleId, '牛乳');

      expect(created.id, isNotEmpty);
      expect(created.createdBy, meUid);
      expect(created.done, isFalse);
      expect(created.quantity, isNull);

      final data = (await itemsRef().doc(created.id).get()).data()!;
      expect(data['title'], '牛乳');
      expect(data['createdBy'], meUid);
      expect(data['done'], false);
      expect(data['quantity'], isNull);
    });

    test('数量を指定して作成できる', () async {
      final created = await service.addItem(coupleId, '卵', quantity: '1パック');

      expect(created.quantity, '1パック');
      final data = (await itemsRef().doc(created.id).get()).data()!;
      expect(data['quantity'], '1パック');
    });
  });

  group('購入済みの切り替え', () {
    test('購入済みにすると保存される', () async {
      final created = await service.addItem(coupleId, '洗剤');

      await service.setDone(created, true);

      final data = (await itemsRef().doc(created.id).get()).data()!;
      expect(data['done'], true);
    });

    test('未購入に戻すと保存される', () async {
      final created = await service.addItem(coupleId, 'パン');
      await service.setDone(created, true);

      await service.setDone(created, false);

      final data = (await itemsRef().doc(created.id).get()).data()!;
      expect(data['done'], false);
    });
  });

  group('削除', () {
    test('削除するとドキュメントが消える', () async {
      final created = await service.addItem(coupleId, 'ティッシュ');

      await service.deleteItem(created);

      expect((await itemsRef().doc(created.id).get()).exists, isFalse);
    });
  });

  group('購入済みの一括削除', () {
    test('購入済みだけが削除され、未購入のものは残る', () async {
      final done1 = await service.addItem(coupleId, '購入済みA');
      await service.setDone(done1, true);
      final done2 = await service.addItem(coupleId, '購入済みB');
      await service.setDone(done2, true);
      final notDone = await service.addItem(coupleId, '未購入');

      await service.clearDone(coupleId);

      final items = await service.watchItems(coupleId).first;
      expect(items.map((i) => i.title), ['未購入']);
      final notDoneData = (await itemsRef().doc(notDone.id).get()).data()!;
      expect(notDoneData['title'], '未購入');
    });

    test('購入済みが無ければ何も変わらない', () async {
      final created = await service.addItem(coupleId, '未購入のみ');

      await service.clearDone(coupleId);

      final data = (await itemsRef().doc(created.id).get()).data()!;
      expect(data['done'], false);
      expect(created.id, isNotEmpty);
    });
  });

  group('一覧の取得', () {
    // addItemはDateTime.now()でcreatedAtを決めるため、順序を確定させたいテストでは
    // 作成後にcreatedAtを明示的な値へ上書きする（実行タイミングに依存させない）。
    Future<void> setCreatedAt(String id, DateTime at) =>
        itemsRef().doc(id).update({'createdAt': Timestamp.fromDate(at)});

    test('未購入が先、それぞれ新しい順に並ぶ', () async {
      final oldDone = await service.addItem(coupleId, '古い購入済み');
      await service.setDone(oldDone, true);
      await setCreatedAt(oldDone.id, DateTime(2026, 8, 1));

      final recentDone = await service.addItem(coupleId, '新しい購入済み');
      await service.setDone(recentDone, true);
      await setCreatedAt(recentDone.id, DateTime(2026, 8, 3));

      final oldItem = await service.addItem(coupleId, '古い未購入');
      await setCreatedAt(oldItem.id, DateTime(2026, 8, 2));

      final recentItem = await service.addItem(coupleId, '新しい未購入');
      await setCreatedAt(recentItem.id, DateTime(2026, 8, 4));

      final items = await service.watchItems(coupleId).first;

      expect(items.map((i) => i.title),
          ['新しい未購入', '古い未購入', '新しい購入済み', '古い購入済み']);
    });
  });
}
