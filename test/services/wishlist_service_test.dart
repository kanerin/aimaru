import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/wishlist_service.dart';

// ほしいものリストのCRUD・予約(reserve/unreserve)・
// 「自分が予約したものだけ」を絞り込むクエリを、Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late WishlistService meService;
  late WishlistService partnerService;

  const coupleId = 'couple-1';
  const meUid = 'user-me';
  const partnerUid = 'user-partner';

  CollectionReference<Map<String, dynamic>> itemsRef() =>
      db.collection('couples').doc(coupleId).collection('wishlistItems');
  CollectionReference<Map<String, dynamic>> reservationsRef() =>
      db.collection('couples').doc(coupleId).collection('wishlistReservations');

  setUp(() {
    db = FakeFirebaseFirestore();
    meService = WishlistService(firestore: db, uid: meUid);
    partnerService = WishlistService(firestore: db, uid: partnerUid);
  });

  group('アイテムの作成', () {
    test('addedByに操作者が入る', () async {
      final created = await meService.addItem(coupleId, 'マグカップ');

      expect(created.id, isNotEmpty);
      expect(created.addedBy, meUid);
      expect(created.url, isNull);

      final data = (await itemsRef().doc(created.id).get()).data()!;
      expect(data['text'], 'マグカップ');
      expect(data['addedBy'], meUid);
    });

    test('リンクを指定して作成できる', () async {
      final created = await meService.addItem(coupleId, 'ヘッドホン', url: 'https://example.com');

      expect(created.url, 'https://example.com');
      final data = (await itemsRef().doc(created.id).get()).data()!;
      expect(data['url'], 'https://example.com');
    });
  });

  group('削除', () {
    test('削除するとドキュメントが消える', () async {
      final created = await meService.addItem(coupleId, '本');

      await meService.deleteItem(created);

      expect((await itemsRef().doc(created.id).get()).exists, isFalse);
    });
  });

  group('一覧の取得', () {
    Future<void> setCreatedAt(String id, DateTime at) =>
        itemsRef().doc(id).update({'createdAt': Timestamp.fromDate(at)});

    test('新しい順に並ぶ', () async {
      final old = await meService.addItem(coupleId, '古いもの');
      await setCreatedAt(old.id, DateTime(2026, 8, 1));
      final recent = await meService.addItem(coupleId, '新しいもの');
      await setCreatedAt(recent.id, DateTime(2026, 8, 2));

      final items = await meService.watchItems(coupleId).first;

      expect(items.map((i) => i.text), ['新しいもの', '古いもの']);
    });
  });

  group('予約', () {
    test('予約すると自分の予約済みIDに含まれる', () async {
      final item = await partnerService.addItem(coupleId, 'ネックレス');

      await meService.reserveItem(coupleId, item.id);

      final reserved = await meService.watchMyReservedItemIds(coupleId).first;
      expect(reserved, {item.id});
      final data = (await reservationsRef().doc(item.id).get()).data()!;
      expect(data['reservedBy'], meUid);
    });

    test('予約を取り消すと自分の予約済みIDから消える', () async {
      final item = await partnerService.addItem(coupleId, '靴下');
      await meService.reserveItem(coupleId, item.id);

      await meService.unreserveItem(coupleId, item.id);

      final reserved = await meService.watchMyReservedItemIds(coupleId).first;
      expect(reserved, isEmpty);
    });

    test('自分が予約したものだけが返り、相手が予約したものは含まれない', () async {
      final itemForPartner = await partnerService.addItem(coupleId, '自分が欲しいもの');
      final itemForMe = await meService.addItem(coupleId, '相手が欲しいもの');

      await meService.reserveItem(coupleId, itemForPartner.id);
      await partnerService.reserveItem(coupleId, itemForMe.id);

      final myReserved = await meService.watchMyReservedItemIds(coupleId).first;
      final partnerReserved = await partnerService.watchMyReservedItemIds(coupleId).first;

      expect(myReserved, {itemForPartner.id});
      expect(partnerReserved, {itemForMe.id});
    });
  });
}
