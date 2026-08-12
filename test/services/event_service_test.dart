import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/services/event_service.dart';

// 予定のCRUDと期間クエリを、Firebaseに接続せず検証する。
//
// リマインダー管理用フィールド（reminded / remindedYear）の扱いを
// 特に見ている。ここがずれると「通知が二重に飛ぶ」か
// 「通知が永久に来ない」のどちらかになり、どちらも致命的なため。
void main() {
  late FakeFirebaseFirestore db;
  late EventService service;

  const coupleId = 'couple-1';
  const meUid    = 'user-me';

  CollectionReference<Map<String, dynamic>> eventsRef() =>
      db.collection('couples').doc(coupleId).collection('events');

  AimaruEvent buildEvent({
    String title = 'デート',
    DateTime? date,
    EventType type = EventType.date,
    bool recurring = false,
    String? location,
    String? memo,
  }) =>
      AimaruEvent(
        id: '',
        coupleId: coupleId,
        title: title,
        date: date ?? DateTime(2026, 8, 22, 19, 0),
        type: type,
        location: location,
        memo: memo,
        createdBy: '',
        recurring: recurring,
      );

  setUp(() {
    db = FakeFirebaseFirestore();
    service = EventService(firestore: db, uid: meUid);
  });

  group('予定の作成', () {
    test('createdByに操作者が入り、リマインダー用フィールドが初期化される', () async {
      final created = await service.addEvent(coupleId, buildEvent());

      expect(created.id, isNotEmpty);
      expect(created.createdBy, meUid);

      final doc = await eventsRef().doc(created.id).get();
      final data = doc.data()!;
      expect(data['createdBy'], meUid);
      expect(data['title'], 'デート');
      expect(data['reminded'], false);
      expect(data['remindedYear'], isNull);
    });

    test('渡したcreatedByではなくログイン中のuidが使われる', () async {
      final spoofed = AimaruEvent(
        id: '',
        coupleId: coupleId,
        title: 'なりすまし',
        date: DateTime(2026, 8, 22),
        type: EventType.plan,
        createdBy: 'someone-else',
      );

      final created = await service.addEvent(coupleId, spoofed);

      expect(created.createdBy, meUid);
    });

    test('GeminiParsedEvent経由でも通常の追加と同じ状態になる', () async {
      final parsed = GeminiParsedEvent(
        title: 'miwaの誕生日',
        date: DateTime(2026, 6, 15),
        type: EventType.celebrity,
        recurring: true,
        location: null,
        memo: null,
      );

      final created = await service.addFromGemini(coupleId, parsed);

      expect(created.createdBy, meUid);
      expect(created.recurring, isTrue);
      expect(created.type, EventType.celebrity);

      final data = (await eventsRef().doc(created.id).get()).data()!;
      expect(data['title'], 'miwaの誕生日');
      expect(data['recurring'], true);
      expect(data['reminded'], false);
      expect(data['remindedYear'], isNull);
    });
  });

  group('予定の更新', () {
    test('日時を変えるとリマインダーの送信済み状態がリセットされる', () async {
      final created = await service.addEvent(coupleId, buildEvent());

      // 送信済みの状態を作る
      await eventsRef().doc(created.id).update({
        'reminded': true,
        'remindedYear': 2026,
      });

      await service.updateEvent(
        created.copyWith(date: DateTime(2026, 8, 25, 19, 0)),
      );

      final data = (await eventsRef().doc(created.id).get()).data()!;
      expect(data['reminded'], false, reason: '新しい日時で再通知されない');
      expect(data['remindedYear'], isNull);
    });

    test('タイトルの変更が保存される', () async {
      final created = await service.addEvent(coupleId, buildEvent());

      await service.updateEvent(created.copyWith(title: '映画デート'));

      final data = (await eventsRef().doc(created.id).get()).data()!;
      expect(data['title'], '映画デート');
    });
  });

  group('予定の削除', () {
    test('削除するとドキュメントが消える', () async {
      final created = await service.addEvent(coupleId, buildEvent());

      await service.deleteEvent(created);

      expect((await eventsRef().doc(created.id).get()).exists, isFalse);
    });
  });

  group('月単位の取得', () {
    test('月初00:00と月末23:59の予定を取りこぼさない', () async {
      await service.addEvent(coupleId,
          buildEvent(title: '月初', date: DateTime(2026, 8, 1, 0, 0)));
      await service.addEvent(coupleId,
          buildEvent(title: '月末', date: DateTime(2026, 8, 31, 23, 59)));
      await service.addEvent(coupleId,
          buildEvent(title: '前月', date: DateTime(2026, 7, 31, 23, 59)));
      await service.addEvent(coupleId,
          buildEvent(title: '翌月', date: DateTime(2026, 9, 1, 0, 0)));

      final events =
          await service.watchMonthEvents(coupleId, DateTime(2026, 8)).first;

      expect(events.map((e) => e.title), ['月初', '月末']);
    });

    test('12月を指定しても翌年1月の計算が破綻しない', () async {
      await service.addEvent(coupleId,
          buildEvent(title: '大晦日', date: DateTime(2026, 12, 31, 23, 0)));
      await service.addEvent(coupleId,
          buildEvent(title: '元日', date: DateTime(2027, 1, 1, 9, 0)));

      final events =
          await service.watchMonthEvents(coupleId, DateTime(2026, 12)).first;

      expect(events.map((e) => e.title), ['大晦日']);
    });

    test('日付の昇順で返る', () async {
      await service.addEvent(coupleId,
          buildEvent(title: '後', date: DateTime(2026, 8, 20)));
      await service.addEvent(coupleId,
          buildEvent(title: '先', date: DateTime(2026, 8, 5)));

      final events =
          await service.watchMonthEvents(coupleId, DateTime(2026, 8)).first;

      expect(events.map((e) => e.title), ['先', '後']);
    });
  });

  group('カレンダー用のMap取得', () {
    test('同じ日の予定が同じキーにまとまる', () async {
      await service.addEvent(coupleId,
          buildEvent(title: '昼', date: DateTime(2026, 8, 22, 12, 0)));
      await service.addEvent(coupleId,
          buildEvent(title: '夜', date: DateTime(2026, 8, 22, 19, 0)));
      await service.addEvent(coupleId,
          buildEvent(title: '別の日', date: DateTime(2026, 8, 23, 12, 0)));

      final map = await service.watchEventsAsMap(coupleId).first;

      expect(map[DateTime(2026, 8, 22)]!.map((e) => e.title), ['昼', '夜']);
      expect(map[DateTime(2026, 8, 23)], hasLength(1));
    });
  });

  group('今後の予定の取得', () {
    test('過去の予定を含めず、件数上限を守る', () async {
      final now = DateTime.now();
      await service.addEvent(coupleId,
          buildEvent(title: '過去', date: now.subtract(const Duration(days: 2))));
      for (var i = 1; i <= 3; i++) {
        await service.addEvent(coupleId,
            buildEvent(title: '未来$i', date: now.add(Duration(days: i))));
      }

      final events =
          await service.watchUpcomingEvents(coupleId, limit: 2).first;

      expect(events, hasLength(2));
      expect(events.map((e) => e.title), ['未来1', '未来2']);
    });
  });
}
