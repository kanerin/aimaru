import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/diary_service.dart';

// ふたりの日記のCRUDを、Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late DiaryService service;

  const coupleId = 'couple-1';
  const meUid    = 'user-me';
  const partnerUid = 'user-partner';
  const dateKey = '2026-08-17';

  CollectionReference<Map<String, dynamic>> entriesRef() =>
      db.collection('couples').doc(coupleId).collection('diaryEntries');

  setUp(() {
    db = FakeFirebaseFirestore();
    service = DiaryService(firestore: db, uid: meUid);
  });

  group('日記の保存', () {
    test('doc idが日付とuidで決まり、内容が保存される', () async {
      await service.saveEntry(coupleId, dateKey, '公園を散歩した');

      final doc = await entriesRef().doc('${dateKey}_$meUid').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['uid'], meUid);
      expect(doc.data()!['dateKey'], dateKey);
      expect(doc.data()!['text'], '公園を散歩した');
    });

    test('前後の空白は取り除いて保存する', () async {
      await service.saveEntry(coupleId, dateKey, '  カフェに行った  ');

      final doc = await entriesRef().doc('${dateKey}_$meUid').get();
      expect(doc.data()!['text'], 'カフェに行った');
    });

    test('空文字は保存しない', () async {
      await service.saveEntry(coupleId, dateKey, '   ');

      final doc = await entriesRef().doc('${dateKey}_$meUid').get();
      expect(doc.exists, isFalse);
    });

    test('同じ日に書き直すと内容が上書きされcreatedAtは変わらない', () async {
      await service.saveEntry(coupleId, dateKey, '最初の内容');
      final firstCreatedAt =
          (await entriesRef().doc('${dateKey}_$meUid').get()).data()!['createdAt'];

      await service.saveEntry(coupleId, dateKey, '書き直した内容');
      final doc = await entriesRef().doc('${dateKey}_$meUid').get();

      expect(doc.data()!['text'], '書き直した内容');
      expect(doc.data()!['createdAt'], firstCreatedAt);
    });
  });

  group('日記の削除', () {
    test('自分の分だけ削除できる', () async {
      await service.saveEntry(coupleId, dateKey, '削除される予定');
      await service.deleteEntry(coupleId, dateKey);

      final doc = await entriesRef().doc('${dateKey}_$meUid').get();
      expect(doc.exists, isFalse);
    });
  });

  group('直近の日記の取得', () {
    test('両者が書くと2件返る', () async {
      await service.saveEntry(coupleId, dateKey, '自分の日記');
      await DiaryService(firestore: db, uid: partnerUid)
          .saveEntry(coupleId, dateKey, '相手の日記');

      final entries = await service.watchRecentEntries(coupleId).first;

      expect(entries.map((e) => e.uid), containsAll([meUid, partnerUid]));
      expect(entries.length, 2);
    });

    test('新しい日付順に並ぶ', () async {
      await service.saveEntry(coupleId, '2026-08-15', '一昨日');
      await service.saveEntry(coupleId, '2026-08-17', '今日');
      await service.saveEntry(coupleId, '2026-08-16', '昨日');

      final entries = await service.watchRecentEntries(coupleId).first;

      expect(entries.map((e) => e.dateKey).toList(), ['2026-08-17', '2026-08-16', '2026-08-15']);
    });

    test('誰も書いていなければ空リスト', () async {
      final entries = await service.watchRecentEntries(coupleId).first;

      expect(entries, isEmpty);
    });
  });
}
