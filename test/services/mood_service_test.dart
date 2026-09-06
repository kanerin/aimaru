import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/mood_service.dart';

// きょうの気分の保存・取得を、Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late MoodService service;

  const coupleId = 'couple-1';
  const meUid    = 'user-me';
  const partnerUid = 'user-partner';
  const dateKey = '2026-08-17';

  CollectionReference<Map<String, dynamic>> entriesRef() =>
      db.collection('couples').doc(coupleId).collection('moodEntries');

  setUp(() {
    db = FakeFirebaseFirestore();
    service = MoodService(firestore: db, uid: meUid);
  });

  group('気分の保存', () {
    test('doc idが日付とuidで決まり、内容が保存される', () async {
      await service.setTodayMood(coupleId, dateKey, 'great');

      final doc = await entriesRef().doc('${dateKey}_$meUid').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['uid'], meUid);
      expect(doc.data()!['dateKey'], dateKey);
      expect(doc.data()!['mood'], 'great');
    });

    test('同じ日に選び直すと内容が上書きされる', () async {
      await service.setTodayMood(coupleId, dateKey, 'good');
      await service.setTodayMood(coupleId, dateKey, 'bad');

      final doc = await entriesRef().doc('${dateKey}_$meUid').get();
      expect(doc.data()!['mood'], 'bad');
    });
  });

  group('直近の気分の取得', () {
    test('両者が選ぶと2件返る', () async {
      await service.setTodayMood(coupleId, dateKey, 'great');
      await MoodService(firestore: db, uid: partnerUid)
          .setTodayMood(coupleId, dateKey, 'okay');

      final entries = await service.watchRecentMoods(coupleId).first;

      expect(entries.map((e) => e.uid), containsAll([meUid, partnerUid]));
      expect(entries.length, 2);
    });

    test('新しい日付順に並ぶ', () async {
      await service.setTodayMood(coupleId, '2026-08-15', 'okay');
      await service.setTodayMood(coupleId, '2026-08-17', 'great');
      await service.setTodayMood(coupleId, '2026-08-16', 'good');

      final entries = await service.watchRecentMoods(coupleId).first;

      expect(entries.map((e) => e.dateKey).toList(), ['2026-08-17', '2026-08-16', '2026-08-15']);
    });

    test('誰も選んでいなければ空リスト', () async {
      final entries = await service.watchRecentMoods(coupleId).first;

      expect(entries, isEmpty);
    });
  });
}
