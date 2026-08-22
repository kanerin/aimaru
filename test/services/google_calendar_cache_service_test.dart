import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/services/google_calendar_cache_service.dart';

// Googleカレンダーの予定を「自分だけに表示（相手には見えません）」にできる
// 機能（#71・#73）の検証。Googleカレンダー自体にこの概念が無いため、
// AIMARU側でgoogleEventVisibility/{uid}として別途持ち、pushMyEventsの
// たびにgoogleCalendarCache側のvisibilityへ焼き直す設計になっている。
void main() {
  late FakeFirebaseFirestore db;
  const coupleId = 'couple-1';
  const meUid = 'user-me';

  GoogleCalendarCacheService serviceFor(String uid) =>
      GoogleCalendarCacheService(firestore: db, uid: uid);

  GCalEventSummary event(String id) => GCalEventSummary(
        id: id,
        title: '予定 $id',
        start: DateTime(2026, 8, 20, 10),
        end: DateTime(2026, 8, 20, 11),
        allDay: false,
      );

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  group('pushMyEvents', () {
    test('privateに指定していない予定はsharedとしてキャッシュされる', () async {
      await serviceFor(meUid).pushMyEvents(coupleId, [event('e1')]);

      final doc = await db
          .collection('couples')
          .doc(coupleId)
          .collection('googleCalendarCache')
          .doc(meUid)
          .get();
      final events = (doc.data()!['events'] as List)
          .map((e) => GCalEventSummary.fromMap(e as Map<String, dynamic>))
          .toList();

      expect(events.single.visibility, EventVisibility.shared);
    });

    test('setEventPrivateで指定した予定はprivateとしてキャッシュされる', () async {
      final service = serviceFor(meUid);
      await service.setEventPrivate(coupleId, 'e1', true);

      await service.pushMyEvents(coupleId, [event('e1'), event('e2')]);

      final doc = await db
          .collection('couples')
          .doc(coupleId)
          .collection('googleCalendarCache')
          .doc(meUid)
          .get();
      final events = (doc.data()!['events'] as List)
          .map((e) => GCalEventSummary.fromMap(e as Map<String, dynamic>))
          .toList();

      expect(events.firstWhere((e) => e.id == 'e1').visibility, EventVisibility.private);
      expect(events.firstWhere((e) => e.id == 'e2').visibility, EventVisibility.shared);
    });

    test('Google側から取り直すたびにgoogleEventVisibilityの指定が焼き直される', () async {
      // fetchEventsは毎回Google側から取り直すため、以前pushした際の
      // visibilityは引き継がれない（GCalEventSummaryはGoogle由来の値のみ）。
      // それでも最終的な表示は正しくprivateのままになることを確認する。
      final service = serviceFor(meUid);
      await service.setEventPrivate(coupleId, 'e1', true);
      await service.pushMyEvents(coupleId, [event('e1')]);

      // 2回目の同期。Googleから取り直した「visibilityを持たない」新しい
      // インスタンスを渡しても、指定は保持される。
      await service.pushMyEvents(coupleId, [event('e1')]);

      final doc = await db
          .collection('couples')
          .doc(coupleId)
          .collection('googleCalendarCache')
          .doc(meUid)
          .get();
      final events = (doc.data()!['events'] as List)
          .map((e) => GCalEventSummary.fromMap(e as Map<String, dynamic>))
          .toList();
      expect(events.single.visibility, EventVisibility.private);
    });

    test('setEventPrivate(false)で指定を解除するとsharedへ戻る', () async {
      final service = serviceFor(meUid);
      await service.setEventPrivate(coupleId, 'e1', true);
      await service.setEventPrivate(coupleId, 'e1', false);

      await service.pushMyEvents(coupleId, [event('e1')]);

      final doc = await db
          .collection('couples')
          .doc(coupleId)
          .collection('googleCalendarCache')
          .doc(meUid)
          .get();
      final events = (doc.data()!['events'] as List)
          .map((e) => GCalEventSummary.fromMap(e as Map<String, dynamic>))
          .toList();
      expect(events.single.visibility, EventVisibility.shared);
    });
  });

  group('watchAll', () {
    test('pushした内容をvisibilityを含めてそのまま読み戻せる', () async {
      final service = serviceFor(meUid);
      await service.setEventPrivate(coupleId, 'e1', true);
      await service.pushMyEvents(coupleId, [event('e1'), event('e2')]);

      final map = await service.watchAll(coupleId).first;

      expect(map[meUid], hasLength(2));
      expect(
        map[meUid]!.firstWhere((e) => e.id == 'e1').visibility,
        EventVisibility.private,
      );
    });
  });

  group('setEventPrivate', () {
    test('自分の指定は他人のカップルドキュメントに影響しない', () async {
      await serviceFor(meUid).setEventPrivate(coupleId, 'e1', true);

      final doc = await db
          .collection('couples')
          .doc(coupleId)
          .collection('googleEventVisibility')
          .doc(meUid)
          .get();
      expect(doc.data()!['privateEventIds'], [
        'e1',
      ]);
    });
  });
}
