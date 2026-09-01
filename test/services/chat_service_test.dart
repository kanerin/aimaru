import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/chat_service.dart';

// チャットの送受信・既読状態を、Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late ChatService meService;
  late ChatService partnerService;

  const coupleId  = 'couple-1';
  const meUid     = 'user-me';
  const partnerUid = 'user-partner';

  DocumentReference<Map<String, dynamic>> readStatusDoc(String uid) => db
      .collection('couples')
      .doc(coupleId)
      .collection('chatReadStatus')
      .doc(uid);

  setUp(() {
    db = FakeFirebaseFirestore();
    meService = ChatService(firestore: db, uid: meUid);
    partnerService = ChatService(firestore: db, uid: partnerUid);
  });

  group('メッセージの送受信', () {
    test('送信したメッセージがwatchMessagesで送信者順に取れる', () async {
      await meService.sendMessage(coupleId, text: 'おはよう');
      await partnerService.sendMessage(coupleId, text: 'おはよう！');

      final messages = await meService.watchMessages(coupleId).first;

      expect(messages.map((m) => m.text), ['おはよう', 'おはよう！']);
      expect(messages.first.senderId, meUid);
      expect(messages.last.senderId, partnerUid);
    });

    test('送信直後のメッセージはreactionsが空', () async {
      await meService.sendMessage(coupleId, text: 'おはよう');

      final message = (await meService.watchMessages(coupleId).first).single;
      expect(message.reactions, isEmpty);
    });
  });

  group('リアクション', () {
    late String messageId;

    setUp(() async {
      await meService.sendMessage(coupleId, text: 'おはよう');
      messageId = (await meService.watchMessages(coupleId).first).single.id;
    });

    test('setReactionで自分のリアクションが付く', () async {
      await partnerService.setReaction(coupleId, messageId, '❤️');

      final message = (await meService.watchMessages(coupleId).first).single;
      expect(message.reactions, {partnerUid: '❤️'});
    });

    test('setReactionを別の絵文字で呼ぶと自分の分だけ上書きされる', () async {
      await meService.setReaction(coupleId, messageId, '👍');
      await partnerService.setReaction(coupleId, messageId, '❤️');
      await meService.setReaction(coupleId, messageId, '😢');

      final message = (await meService.watchMessages(coupleId).first).single;
      expect(message.reactions, {meUid: '😢', partnerUid: '❤️'});
    });

    test('removeReactionで自分のリアクションだけ消える', () async {
      await meService.setReaction(coupleId, messageId, '👍');
      await partnerService.setReaction(coupleId, messageId, '❤️');

      await meService.removeReaction(coupleId, messageId);

      final message = (await meService.watchMessages(coupleId).first).single;
      expect(message.reactions, {partnerUid: '❤️'});
    });
  });

  group('既読状態', () {
    test('markAsReadで自分のドキュメントにlastReadAtが書かれる', () async {
      await meService.markAsRead(coupleId);

      final data = (await readStatusDoc(meUid).get()).data();
      expect(data, isNotNull);
      expect(data!['lastReadAt'], isA<Timestamp>());
    });

    test('パートナーが未読のうちはwatchPartnerLastReadAtがnullを返す', () async {
      final lastReadAt = await meService.watchPartnerLastReadAt(coupleId, partnerUid).first;
      expect(lastReadAt, isNull);
    });

    test('パートナーがmarkAsReadすると自分側のwatchPartnerLastReadAtに反映される', () async {
      final stream = meService.watchPartnerLastReadAt(coupleId, partnerUid);
      final updates = <DateTime?>[];
      final sub = stream.listen(updates.add);

      await partnerService.markAsRead(coupleId);
      await Future<void>.delayed(Duration.zero);

      expect(updates.last, isNotNull);
      await sub.cancel();
    });
  });
}
