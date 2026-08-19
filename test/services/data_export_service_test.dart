import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/data_export_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late DataExportService service;

  const coupleId = 'couple-1';

  CollectionReference<Map<String, dynamic>> col(String name) =>
      db.collection('couples').doc(coupleId).collection(name);

  setUp(() {
    db = FakeFirebaseFirestore();
    service = DataExportService(firestore: db);
  });

  test('データが無いカップルは、各セクションが空配列のJSONを返す', () async {
    final json = await service.exportAsJson(coupleId);
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    expect(decoded['coupleId'], coupleId);
    expect(decoded['events'], isEmpty);
    expect(decoded['chats'], isEmpty);
    expect(decoded['todos'], isEmpty);
    expect(decoded['questionAnswers'], isEmpty);
    expect(decoded['exportedAt'], isNotEmpty);
  });

  test('予定を書き出す。省略可能なフィールドも含めて正しく変換される', () async {
    await col('events').doc('event-1').set({
      'coupleId': coupleId,
      'title': '映画デート',
      'date': Timestamp.fromDate(DateTime(2026, 9, 1, 19, 0)),
      'endDate': Timestamp.fromDate(DateTime(2026, 9, 1, 21, 0)),
      'type': 'date',
      'location': '渋谷',
      'memo': 'チケット予約済み',
      'imageUrls': ['https://example.com/a.jpg'],
      'createdBy': 'user-a',
      'recurring': false,
      'allDay': false,
    });

    final json = await service.exportAsJson(coupleId);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final events = decoded['events'] as List;

    expect(events, hasLength(1));
    final e = events.single as Map<String, dynamic>;
    expect(e['id'], 'event-1');
    expect(e['title'], '映画デート');
    expect(e['date'], DateTime(2026, 9, 1, 19, 0).toIso8601String());
    expect(e['endDate'], DateTime(2026, 9, 1, 21, 0).toIso8601String());
    expect(e['type'], 'date');
    expect(e['location'], '渋谷');
    expect(e['memo'], 'チケット予約済み');
    expect(e['imageUrls'], ['https://example.com/a.jpg']);
    expect(e['createdBy'], 'user-a');
  });

  test('endDate・location・memoが無い予定はnullとして書き出される', () async {
    await col('events').doc('event-2').set({
      'coupleId': coupleId,
      'title': '記念日',
      'date': Timestamp.fromDate(DateTime(2026, 3, 1)),
      'type': 'anniversary',
      'createdBy': 'user-a',
      'recurring': true,
      'allDay': true,
    });

    final json = await service.exportAsJson(coupleId);
    final e = (jsonDecode(json)['events'] as List).single as Map<String, dynamic>;

    expect(e['endDate'], isNull);
    expect(e['location'], isNull);
    expect(e['memo'], isNull);
    expect(e['imageUrls'], isEmpty);
  });

  test('ゴミ箱に入っている（論理削除済みの）予定は含めない', () async {
    await col('events').doc('event-live').set({
      'coupleId': coupleId,
      'title': '生きている予定',
      'date': Timestamp.fromDate(DateTime(2026, 9, 1)),
      'type': 'plan',
      'createdBy': 'user-a',
    });
    await col('events').doc('event-trashed').set({
      'coupleId': coupleId,
      'title': '削除済みの予定',
      'date': Timestamp.fromDate(DateTime(2026, 9, 2)),
      'type': 'plan',
      'createdBy': 'user-a',
      'deletedAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    });

    final json = await service.exportAsJson(coupleId);
    final events = jsonDecode(json)['events'] as List;

    expect(events, hasLength(1));
    expect((events.single as Map)['title'], '生きている予定');
  });

  test('チャットを時系列順に書き出す', () async {
    await col('chats').doc('msg-2').set({
      'coupleId': coupleId,
      'text': '2件目',
      'senderId': 'user-a',
      'timestamp': Timestamp.fromDate(DateTime(2026, 8, 1, 10, 1)),
      'isAi': false,
    });
    await col('chats').doc('msg-1').set({
      'coupleId': coupleId,
      'text': '1件目',
      'senderId': 'user-b',
      'timestamp': Timestamp.fromDate(DateTime(2026, 8, 1, 10, 0)),
      'isAi': false,
    });

    final json = await service.exportAsJson(coupleId);
    final chats = jsonDecode(json)['chats'] as List;

    expect(chats.map((c) => c['text']), ['1件目', '2件目']);
  });

  test('やりたいことリスト・ふたりの質問への回答を書き出す', () async {
    await col('todos').doc('todo-1').set({
      'coupleId': coupleId,
      'text': '水族館に行く',
      'done': false,
      'createdBy': 'user-a',
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
    await col('questionAnswers').doc('2026-01-01_user-a').set({
      'coupleId': coupleId,
      'dateKey': '2026-01-01',
      'uid': 'user-a',
      'text': '初デートの場所',
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });

    final json = await service.exportAsJson(coupleId);
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    final todo = (decoded['todos'] as List).single as Map<String, dynamic>;
    expect(todo['text'], '水族館に行く');
    expect(todo['done'], false);

    final answer = (decoded['questionAnswers'] as List).single as Map<String, dynamic>;
    expect(answer['dateKey'], '2026-01-01');
    expect(answer['text'], '初デートの場所');
  });

  test('別のカップルのデータは含まれない', () async {
    await col('events').doc('mine').set({
      'coupleId': coupleId,
      'title': '自分のカップルの予定',
      'date': Timestamp.fromDate(DateTime(2026, 9, 1)),
      'type': 'plan',
      'createdBy': 'user-a',
    });
    await db
        .collection('couples')
        .doc('other-couple')
        .collection('events')
        .doc('theirs')
        .set({
      'coupleId': 'other-couple',
      'title': '他のカップルの予定',
      'date': Timestamp.fromDate(DateTime(2026, 9, 1)),
      'type': 'plan',
      'createdBy': 'user-x',
    });

    final json = await service.exportAsJson(coupleId);
    final events = jsonDecode(json)['events'] as List;

    expect(events, hasLength(1));
    expect((events.single as Map)['title'], '自分のカップルの予定');
  });
}
