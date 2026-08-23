import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/services/event_comment_service.dart';

// 予定ごとのコメントのCRUDを、Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late EventCommentService service;

  const coupleId = 'couple-1';
  const eventId  = 'event-1';
  const meUid    = 'user-me';

  CollectionReference<Map<String, dynamic>> commentsRef() => db
      .collection('couples').doc(coupleId)
      .collection('events').doc(eventId)
      .collection('comments');

  setUp(() {
    db = FakeFirebaseFirestore();
    service = EventCommentService(firestore: db, uid: meUid);
  });

  group('コメントの追加', () {
    test('senderIdに操作者のuidが入る', () async {
      await service.addComment(coupleId, eventId, '楽しみ！');

      final snap = await commentsRef().get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.first.data()['senderId'], meUid);
      expect(snap.docs.first.data()['text'], '楽しみ！');
      expect(snap.docs.first.data()['coupleId'], coupleId);
      expect(snap.docs.first.data()['eventId'], eventId);
    });
  });

  group('コメント一覧の取得', () {
    test('作成日時の古い順で返る', () async {
      final other = EventCommentService(firestore: db, uid: 'user-partner');

      await service.addComment(coupleId, eventId, '最初のコメント');
      await other.addComment(coupleId, eventId, '2番目のコメント');

      final comments = await service.watchComments(coupleId, eventId).first;

      expect(comments.map((c) => c.text), ['最初のコメント', '2番目のコメント']);
      expect(comments.map((c) => c.senderId), [meUid, 'user-partner']);
    });

    test('別の予定のコメントは含まれない', () async {
      await service.addComment(coupleId, eventId, 'この予定のコメント');
      await service.addComment(coupleId, 'event-2', '別の予定のコメント');

      final comments = await service.watchComments(coupleId, eventId).first;

      expect(comments.map((c) => c.text), ['この予定のコメント']);
    });

    test('fromDocでの変換がtoMapと往復する', () async {
      await service.addComment(coupleId, eventId, '往復確認');

      final doc = (await commentsRef().get()).docs.first;
      final loaded = EventComment.fromDoc(doc);

      expect(loaded.id, doc.id);
      expect(loaded.coupleId, coupleId);
      expect(loaded.eventId, eventId);
      expect(loaded.text, '往復確認');
      expect(loaded.senderId, meUid);
    });
  });
}
