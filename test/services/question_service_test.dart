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

    test('質問文を渡すと回答と一緒に残り、読み出せる', () async {
      await service.submitAnswer(coupleId, dateKey, '札幌', question: '2人で行きたい雪国の街は？');

      final answers = await service.watchAnswers(coupleId, dateKey).first;
      expect(answers.single.question, '2人で行きたい雪国の街は？');
    });

    test('質問文を渡さなければ保存しない（古い回答と同じ形）', () async {
      await service.submitAnswer(coupleId, dateKey, '水族館に行きたい');

      final doc = await answersRef().doc('${dateKey}_$meUid').get();
      expect(doc.data()!.containsKey('question'), isFalse);
    });
  });

  group('今日の質問文の取得', () {
    test('サーバーが用意した質問があれば、その文を返す', () async {
      await db.collection('dailyQuestions').doc(dateKey).set({
        'dateKey': dateKey,
        'text': '2人で行きたい雪国の街は？',
        'source': 'gemini',
      });

      expect(await service.fetchDailyQuestion(dateKey), '2人で行きたい雪国の街は？');
    });

    test('その日の質問がまだ無ければnull', () async {
      expect(await service.fetchDailyQuestion(dateKey), isNull);
    });

    test('質問文が空ならnull（手書きの質問に切り替えさせる）', () async {
      await db.collection('dailyQuestions').doc(dateKey).set({'text': ''});

      expect(await service.fetchDailyQuestion(dateKey), isNull);
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
