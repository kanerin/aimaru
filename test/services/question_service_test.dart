import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/question_service.dart';

// デイリー質問への回答のCRUDを、Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late QuestionService service;

  const coupleId = 'couple-1';
  const meUid    = 'user-me';
  const partnerUid = 'user-partner';
  const dateKey = '2026-08-17';

  CollectionReference<Map<String, dynamic>> answersRef() =>
      db.collection('couples').doc(coupleId).collection('questionAnswers');

  setUp(() {
    db = FakeFirebaseFirestore();
    service = QuestionService(firestore: db, uid: meUid);
  });

  group('回答の作成', () {
    test('doc idが日付とuidで決まり、内容が保存される', () async {
      await service.submitAnswer(coupleId, dateKey, '水族館に行きたい');

      final doc = await answersRef().doc('${dateKey}_$meUid').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['uid'], meUid);
      expect(doc.data()!['dateKey'], dateKey);
      expect(doc.data()!['text'], '水族館に行きたい');
    });
  });

  group('その日の回答一覧の取得', () {
    test('両者が回答すると2件返る', () async {
      await service.submitAnswer(coupleId, dateKey, '自分の回答');
      await QuestionService(firestore: db, uid: partnerUid)
          .submitAnswer(coupleId, dateKey, '相手の回答');

      final answers = await service.watchAnswers(coupleId, dateKey).first;

      expect(answers.map((a) => a.uid), containsAll([meUid, partnerUid]));
      expect(answers.length, 2);
    });

    test('別の日付の回答は含まれない', () async {
      await service.submitAnswer(coupleId, dateKey, '今日の回答');
      await service.submitAnswer(coupleId, '2026-08-16', '昨日の回答');

      final answers = await service.watchAnswers(coupleId, dateKey).first;

      expect(answers.length, 1);
      expect(answers.first.text, '今日の回答');
    });

    test('誰も回答していなければ空リスト', () async {
      final answers = await service.watchAnswers(coupleId, dateKey).first;

      expect(answers, isEmpty);
    });
  });

  group('過去分を含む直近の回答の取得', () {
    test('日付をまたいだ回答が新しい順に返る', () async {
      await service.submitAnswer(coupleId, '2026-08-15', '一昨日の回答');
      await service.submitAnswer(coupleId, '2026-08-17', '今日の回答');
      await service.submitAnswer(coupleId, '2026-08-16', '昨日の回答');

      final answers = await service.watchRecentAnswers(coupleId).first;

      expect(answers.map((a) => a.dateKey).toList(),
          ['2026-08-17', '2026-08-16', '2026-08-15']);
    });

    test('2人分の回答が同じ日付でどちらも返る', () async {
      await service.submitAnswer(coupleId, dateKey, '自分の回答');
      await QuestionService(firestore: db, uid: partnerUid)
          .submitAnswer(coupleId, dateKey, '相手の回答');

      final answers = await service.watchRecentAnswers(coupleId).first;

      expect(answers.length, 2);
      expect(answers.map((a) => a.uid), containsAll([meUid, partnerUid]));
    });

    test('limitを超える分は返らない（新しい方が残る）', () async {
      await service.submitAnswer(coupleId, '2026-08-15', '古い回答');
      await service.submitAnswer(coupleId, '2026-08-16', '新しい回答');

      final answers = await service.watchRecentAnswers(coupleId, limit: 1).first;

      expect(answers.length, 1);
      expect(answers.first.dateKey, '2026-08-16');
    });

    test('1件も無ければ空リスト', () async {
      expect(await service.watchRecentAnswers(coupleId).first, isEmpty);
    });
  });
}
