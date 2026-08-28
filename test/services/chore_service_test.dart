import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/chore_service.dart';

// 家事分担チェックリストのCRUD・担当変更・一括リセット・並び順を、
// Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late ChoreService service;

  const coupleId = 'couple-1';
  const meUid    = 'user-me';
  const partnerUid = 'user-partner';

  CollectionReference<Map<String, dynamic>> choresRef() =>
      db.collection('couples').doc(coupleId).collection('chores');

  setUp(() {
    db = FakeFirebaseFirestore();
    service = ChoreService(firestore: db, uid: meUid);
  });

  group('家事の作成', () {
    test('createdByに操作者が入り、未完了・担当なしで作られる', () async {
      final created = await service.addChore(coupleId, '皿洗い');

      expect(created.id, isNotEmpty);
      expect(created.createdBy, meUid);
      expect(created.done, isFalse);
      expect(created.assignedTo, isNull);

      final data = (await choresRef().doc(created.id).get()).data()!;
      expect(data['title'], '皿洗い');
      expect(data['createdBy'], meUid);
      expect(data['done'], false);
      expect(data['assignedTo'], isNull);
    });

    test('担当者を指定して作成できる', () async {
      final created = await service.addChore(coupleId, 'ゴミ出し', assignedTo: partnerUid);

      expect(created.assignedTo, partnerUid);
      final data = (await choresRef().doc(created.id).get()).data()!;
      expect(data['assignedTo'], partnerUid);
    });
  });

  group('完了の切り替え', () {
    test('完了にすると保存される', () async {
      final created = await service.addChore(coupleId, '洗濯');

      await service.setDone(created, true);

      final data = (await choresRef().doc(created.id).get()).data()!;
      expect(data['done'], true);
    });

    test('未完了に戻すと保存される', () async {
      final created = await service.addChore(coupleId, '掃除機がけ');
      await service.setDone(created, true);

      await service.setDone(created, false);

      final data = (await choresRef().doc(created.id).get()).data()!;
      expect(data['done'], false);
    });
  });

  group('担当者の変更', () {
    test('担当なしから担当者を設定できる', () async {
      final created = await service.addChore(coupleId, '料理');

      await service.setAssignee(created, meUid);

      final data = (await choresRef().doc(created.id).get()).data()!;
      expect(data['assignedTo'], meUid);
    });

    test('nullに戻すと「どちらでも」になる', () async {
      final created = await service.addChore(coupleId, '風呂掃除', assignedTo: meUid);

      await service.setAssignee(created, null);

      final data = (await choresRef().doc(created.id).get()).data()!;
      expect(data['assignedTo'], isNull);
    });
  });

  group('削除', () {
    test('削除するとドキュメントが消える', () async {
      final created = await service.addChore(coupleId, 'アイロンがけ');

      await service.deleteChore(created);

      expect((await choresRef().doc(created.id).get()).exists, isFalse);
    });
  });

  group('完了済みの一括リセット', () {
    test('完了済みだけが未完了に戻り、未完了のものはそのまま', () async {
      final done1 = await service.addChore(coupleId, '完了済みA');
      await service.setDone(done1, true);
      final done2 = await service.addChore(coupleId, '完了済みB');
      await service.setDone(done2, true);
      final notDone = await service.addChore(coupleId, '未完了');

      await service.resetAllDone(coupleId);

      final chores = await service.watchChores(coupleId).first;
      expect(chores.every((c) => c.done == false), isTrue);
      expect(chores.map((c) => c.title), containsAll(['完了済みA', '完了済みB', '未完了']));
      // 未完了だったものが誤って何か変化していないか（他フィールド破壊が無いか）念のため確認
      final notDoneData = (await choresRef().doc(notDone.id).get()).data()!;
      expect(notDoneData['done'], false);
    });

    test('完了済みが無ければ何も変わらない', () async {
      final created = await service.addChore(coupleId, '未完了のみ');

      await service.resetAllDone(coupleId);

      final data = (await choresRef().doc(created.id).get()).data()!;
      expect(data['done'], false);
      expect(created.id, isNotEmpty);
    });
  });

  group('一覧の取得', () {
    // addChoreはDateTime.now()でcreatedAtを決めるため、順序を確定させたいテストでは
    // 作成後にcreatedAtを明示的な値へ上書きする（実行タイミングに依存させない）。
    Future<void> setCreatedAt(String id, DateTime at) =>
        choresRef().doc(id).update({'createdAt': Timestamp.fromDate(at)});

    test('未完了が先、それぞれ新しい順に並ぶ', () async {
      final oldDone = await service.addChore(coupleId, '古い完了済み');
      await service.setDone(oldDone, true);
      await setCreatedAt(oldDone.id, DateTime(2026, 8, 1));

      final recentDone = await service.addChore(coupleId, '新しい完了済み');
      await service.setDone(recentDone, true);
      await setCreatedAt(recentDone.id, DateTime(2026, 8, 3));

      final oldChore = await service.addChore(coupleId, '古い未完了');
      await setCreatedAt(oldChore.id, DateTime(2026, 8, 2));

      final recentChore = await service.addChore(coupleId, '新しい未完了');
      await setCreatedAt(recentChore.id, DateTime(2026, 8, 4));

      final chores = await service.watchChores(coupleId).first;

      expect(chores.map((c) => c.title),
          ['新しい未完了', '古い未完了', '新しい完了済み', '古い完了済み']);
    });
  });
}
