import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/question_service.dart';
import 'package:aimaru/utils/daily_question_picker.dart';

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

  group('今日の質問の共有', () {
    final today = DateTime(2026, 10, 4);
    const todayKey = '2026-10-04';

    CollectionReference<Map<String, dynamic>> dailyQuestionsRef() =>
        db.collection('couples').doc(coupleId).collection('dailyQuestions');

    QuestionService partnerService() => QuestionService(firestore: db, uid: partnerUid);

    Future<void> seedLegacyAnswer(String uid, String key) => answersRef().doc('${key}_$uid').set({
          'coupleId': coupleId,
          'dateKey': key,
          'uid': uid,
          'text': '質問を保存していなかった頃の回答',
          'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
        });

    test('最初に開いた側が質問を保存し、2人とも同じ質問になる', () async {
      final mine = await service.ensureDailyQuestion(coupleId, today);
      final partners = await partnerService().ensureDailyQuestion(coupleId, today);

      expect(partners, mine);
      final doc = await dailyQuestionsRef().doc(todayKey).get();
      expect(doc.data()!['question'], mine);
      expect(doc.data()!['createdBy'], meUid);
    });

    test('保存済みの質問があれば、手元の表から計算した質問ではなくそれを返す', () async {
      // アプリの版が違う相手が、こちらの表には無い質問を先に保存していた場合。
      await dailyQuestionsRef().doc(todayKey).set({'question': '相手の版が保存した質問', 'dateKey': todayKey});

      expect(await service.ensureDailyQuestion(coupleId, today), '相手の版が保存した質問');
    });

    test('2人が同時に開いても質問は1つに決まる', () async {
      final results = await Future.wait([
        service.ensureDailyQuestion(coupleId, today),
        partnerService().ensureDailyQuestion(coupleId, today),
      ]);

      expect(results[0], results[1]);
      expect((await dailyQuestionsRef().get()).docs.length, 1);
    });

    test('何度開いても同じ日の質問は変わらない', () async {
      final first = await service.ensureDailyQuestion(coupleId, today);
      await service.submitAnswer(coupleId, todayKey, '回答', question: first);

      expect(await service.ensureDailyQuestion(coupleId, today), first);
    });

    test('日付から決まる質問に過去すでに回答していれば、別の質問を出す', () async {
      final preferred = pickDailyQuestion(today);
      await answersRef().doc('2026-09-20_$meUid').set({
        'coupleId': coupleId,
        'dateKey': '2026-09-20',
        'uid': meUid,
        'text': '前に答えた',
        'question': preferred,
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 20)),
      });

      expect(await service.ensureDailyQuestion(coupleId, today), isNot(preferred));
    });

    test('質問を保存していなかった頃に回答した質問（日付から復元）も出さない', () async {
      // 2026-09-04に出ていた質問を、今日の第一候補と同じになるよう仕立てる。
      const legacyKey = '2026-09-04';
      final legacyQuestion = questionForDateKey(legacyKey)!;
      await seedLegacyAnswer(partnerUid, legacyKey);
      // 相手だけが回答した日の質問も「出題済み」として扱う。
      final day = [
        for (var d = 0; d < 400; d++) DateTime(2026, 10, 4).add(Duration(days: d)),
      ].firstWhere((d) => pickDailyQuestion(d) == legacyQuestion);

      expect(await service.ensureDailyQuestion(coupleId, day), isNot(legacyQuestion));
    });

    test('1日ずつ進めても、表を出し切るまで同じ質問が2度出ない', () async {
      final asked = <String>{};
      for (var d = 0; d < allDailyQuestions.length; d++) {
        final day = today.add(Duration(days: d));
        final question = await service.ensureDailyQuestion(coupleId, day);
        expect(asked.add(question), isTrue, reason: '${d + 1}日目に「$question」が再び出た');
      }
    });

    test('回答せずに過ぎた日の質問も出題済みとして扱う', () async {
      final yesterday = await service.ensureDailyQuestion(coupleId, DateTime(2026, 10, 3));
      // 今日の第一候補が昨日の質問と同じになる状況を、保存済みの質問で作る。
      await dailyQuestionsRef().doc('2026-10-02').set({'question': pickDailyQuestion(today)});

      final question = await service.ensureDailyQuestion(coupleId, today);

      expect(question, isNot(yesterday));
      expect(question, isNot(pickDailyQuestion(today)));
    });

    test('古い版の相手が今日すでに回答していたら、相手が見た質問（日付から決まる質問）に合わせる', () async {
      final preferred = pickDailyQuestion(today);
      // 第一候補は出題済みだが、相手は古い版でその質問にもう答えている。
      await dailyQuestionsRef().doc('2026-09-20').set({'question': preferred});
      await seedLegacyAnswer(partnerUid, todayKey);

      expect(await service.ensureDailyQuestion(coupleId, today), preferred);
    });
  });

  group('回答の作成', () {
    test('回答した質問文を一緒に保存する', () async {
      await service.submitAnswer(coupleId, dateKey, '水族館に行きたい', question: '次に行きたい場所は？');

      final doc = await answersRef().doc('${dateKey}_$meUid').get();
      expect(doc.data()!['question'], '次に行きたい場所は？');
    });

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
