import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/anniversary_service.dart';

// 複数記念日のCRUDを、Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late AnniversaryService service;

  const coupleId = 'couple-1';
  const meUid    = 'user-me';

  CollectionReference<Map<String, dynamic>> anniversariesRef() =>
      db.collection('couples').doc(coupleId).collection('anniversaries');

  setUp(() {
    db = FakeFirebaseFirestore();
    service = AnniversaryService(firestore: db, uid: meUid);
  });

  group('記念日の作成', () {
    test('createdByに操作者が入り、指定した日付とタイトルで作られる', () async {
      final created = await service.addAnniversary(
          coupleId, 'プロポーズ記念日', DateTime(2024, 3, 10));

      expect(created.id, isNotEmpty);
      expect(created.title, 'プロポーズ記念日');
      expect(created.date, DateTime(2024, 3, 10));
      expect(created.createdBy, meUid);

      final data = (await anniversariesRef().doc(created.id).get()).data()!;
      expect(data['title'], 'プロポーズ記念日');
      expect((data['date'] as Timestamp).toDate(), DateTime(2024, 3, 10));
      expect(data['createdBy'], meUid);
    });
  });

  group('削除', () {
    test('削除するとドキュメントが消える', () async {
      final created = await service.addAnniversary(coupleId, '入籍日', DateTime(2023, 5, 1));

      await service.deleteAnniversary(created);

      expect((await anniversariesRef().doc(created.id).get()).exists, isFalse);
    });
  });

  group('一覧の取得', () {
    test('登録した記念日がすべて返る', () async {
      await service.addAnniversary(coupleId, '初デート', DateTime(2022, 1, 1));
      await service.addAnniversary(coupleId, 'プロポーズ記念日', DateTime(2024, 3, 10));

      final items = await service.watchAnniversaries(coupleId).first;

      expect(items.map((e) => e.title), containsAll(['初デート', 'プロポーズ記念日']));
    });
  });
}
