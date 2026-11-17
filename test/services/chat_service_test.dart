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

  group('ピン留め', () {
    Future<String> send(ChatService service, String text) async {
      await service.sendMessage(coupleId, text: text);
      final messages = await service.watchMessages(coupleId).first;
      return messages.lastWhere((m) => m.text == text).id;
    }

    test('送ったばかりのメッセージはピン留めされていない（フィールドも持たない）', () async {
      final id = await send(meService, 'おはよう');

      final doc = await db.collection('couples').doc(coupleId).collection('chats').doc(id).get();
      expect(doc.data()!.containsKey('pinnedAt'), isFalse);
      expect((await meService.watchMessages(coupleId).first).single.isPinned, isFalse);
      expect(await meService.watchPinnedMessages(coupleId).first, isEmpty);
    });

    test('ピン留めすると日時とピン留めした人が残り、ピン留め一覧に出る', () async {
      final id = await send(partnerService, '金曜19時に駅前で');
      await send(meService, 'りょうかい');

      await meService.pinMessage(coupleId, id);

      final pinned = await partnerService.watchPinnedMessages(coupleId).first;
      expect(pinned.map((m) => m.text), ['金曜19時に駅前で']);
      expect(pinned.single.pinnedBy, meUid);
      expect(pinned.single.pinnedAt, isNotNull);
    });

    test('ピン留め一覧は新しくピン留めした順に並ぶ', () async {
      final first = await send(meService, '先にピン留め');
      final second = await send(meService, '後でピン留め');

      await meService.pinMessage(coupleId, first);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await partnerService.pinMessage(coupleId, second);

      final pinned = await meService.watchPinnedMessages(coupleId).first;
      expect(pinned.map((m) => m.text), ['後でピン留め', '先にピン留め']);
    });

    test('ピン留めを外すとフィールドが消え、一覧からも消える（相手がピン留めしたものも外せる）', () async {
      final id = await send(meService, '金曜19時に駅前で');
      await meService.pinMessage(coupleId, id);

      await partnerService.unpinMessage(coupleId, id);

      final doc = await db.collection('couples').doc(coupleId).collection('chats').doc(id).get();
      expect(doc.data()!.containsKey('pinnedAt'), isFalse);
      expect(doc.data()!.containsKey('pinnedBy'), isFalse);
      expect(await meService.watchPinnedMessages(coupleId).first, isEmpty);
    });
  });
}
