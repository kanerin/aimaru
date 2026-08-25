import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/album_service.dart';

// 共有アルバムのメタデータCRUDと並び順を、Firebaseに接続せず検証する。
// 実ファイルのアップロード・削除（StorageService）はここでは扱わない。
void main() {
  late FakeFirebaseFirestore db;
  late AlbumService service;

  const coupleId = 'couple-1';
  const meUid    = 'user-me';

  CollectionReference<Map<String, dynamic>> photosRef() =>
      db.collection('couples').doc(coupleId).collection('albumPhotos');

  setUp(() {
    db = FakeFirebaseFirestore();
    service = AlbumService(firestore: db, uid: meUid);
  });

  group('写真の追加', () {
    test('uploadedByに操作者が入る', () async {
      final added = await service.addPhoto(coupleId, 'https://example.com/a.jpg');

      expect(added.id, isNotEmpty);
      expect(added.uploadedBy, meUid);
      expect(added.imageUrl, 'https://example.com/a.jpg');

      final data = (await photosRef().doc(added.id).get()).data()!;
      expect(data['imageUrl'], 'https://example.com/a.jpg');
      expect(data['uploadedBy'], meUid);
    });
  });

  group('写真の削除', () {
    test('削除するとドキュメントが消える', () async {
      final added = await service.addPhoto(coupleId, 'https://example.com/a.jpg');

      await service.deletePhoto(added);

      expect((await photosRef().doc(added.id).get()).exists, isFalse);
    });
  });

  group('一覧の取得', () {
    Future<void> setCreatedAt(String id, DateTime at) =>
        photosRef().doc(id).update({'createdAt': Timestamp.fromDate(at)});

    test('新しい順に並ぶ', () async {
      final oldest = await service.addPhoto(coupleId, 'https://example.com/old.jpg');
      await setCreatedAt(oldest.id, DateTime(2026, 8, 1));

      final newest = await service.addPhoto(coupleId, 'https://example.com/new.jpg');
      await setCreatedAt(newest.id, DateTime(2026, 8, 3));

      final middle = await service.addPhoto(coupleId, 'https://example.com/mid.jpg');
      await setCreatedAt(middle.id, DateTime(2026, 8, 2));

      final photos = await service.watchPhotos(coupleId).first;

      expect(photos.map((p) => p.imageUrl), [
        'https://example.com/new.jpg',
        'https://example.com/mid.jpg',
        'https://example.com/old.jpg',
      ]);
    });

    test('別のカップルの写真は混ざらない', () async {
      await service.addPhoto(coupleId, 'https://example.com/mine.jpg');
      await service.addPhoto('couple-other', 'https://example.com/other.jpg');

      final photos = await service.watchPhotos(coupleId).first;

      expect(photos.map((p) => p.imageUrl), ['https://example.com/mine.jpg']);
    });
  });
}
