import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/wishlist_screen.dart';
import 'package:aimaru/services/wishlist_service.dart';

// ほしいものリスト画面がストリームエラーで無限ローディングのまま固まらないこと、
// 追加・削除・「用意する」の予約トグルができること、
// 予約状態が「自分が追加したアイテム」には一切出ないことを確かめる。
void main() {
  const meUid = 'user-me';
  const partnerUid = 'user-partner';

  Widget wrap(
    Stream<List<WishlistItem>> itemsStream, {
    Stream<Set<String>>? reservedIdsStream,
    WishlistService? wishlistService,
  }) =>
      MaterialApp(
        home: WishlistScreen(
          coupleId: 'couple-1',
          memberIds: const [meUid, partnerUid],
          partnerName: 'パートナー',
          currentUidOverride: meUid,
          itemsStreamOverride: itemsStream,
          reservedIdsStreamOverride: reservedIdsStream ?? const Stream.empty(),
          wishlistServiceOverride: wishlistService,
        ),
      );

  final mine = WishlistItem(
    id: 'i-mine', coupleId: 'couple-1', text: 'マグカップ',
    addedBy: meUid, createdAt: DateTime(2026, 1, 1),
  );
  final partners = WishlistItem(
    id: 'i-partner', coupleId: 'couple-1', text: 'ヘッドホン', url: 'https://example.com',
    addedBy: partnerUid, createdAt: DateTime(2026, 1, 2),
  );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<WishlistItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<WishlistItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが無ければ空表示になる', (tester) async {
    final controller = StreamController<List<WishlistItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    expect(find.textContaining('まだほしいものリストは空です'), findsOneWidget);

    await controller.close();
  });

  testWidgets('自分が追加したアイテムには削除ボタンだけで予約表示は出ない', (tester) async {
    final controller = StreamController<List<WishlistItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([mine]);
    await tester.pump();

    expect(find.text('マグカップ'), findsOneWidget);
    expect(find.text('あなたが追加'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.textContaining('用意する'), findsNothing);
    expect(find.textContaining('予約済み'), findsNothing);
  });

  testWidgets('相手が追加したアイテムはリンクと「用意する」ボタンを表示し、削除ボタンは出ない', (tester) async {
    final controller = StreamController<List<WishlistItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([partners]);
    await tester.pump();

    expect(find.text('ヘッドホン'), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);
    expect(find.text('パートナーが追加'), findsOneWidget);
    expect(find.textContaining('用意する'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('相手のアイテムが自分の予約済みIDに含まれていれば予約済み表示になる', (tester) async {
    final itemsController = StreamController<List<WishlistItem>>();
    final reservedController = StreamController<Set<String>>();
    await tester.pumpWidget(wrap(itemsController.stream, reservedIdsStream: reservedController.stream));

    itemsController.add([partners]);
    await tester.pump();
    reservedController.add({partners.id});
    await tester.pump();

    expect(find.textContaining('予約済み'), findsOneWidget);
    expect(find.textContaining('用意する'), findsNothing);

    await itemsController.close();
    await reservedController.close();
  });

  testWidgets('「用意する」を押すとWishlistServiceのreserveItemが呼ばれる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = WishlistService(firestore: db, uid: meUid);
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('wishlistItems')
        .doc(partners.id)
        .set(partners.toMap());

    final itemsController = StreamController<List<WishlistItem>>();
    await tester.pumpWidget(wrap(
      itemsController.stream,
      reservedIdsStream: const Stream.empty(),
      wishlistService: service,
    ));

    itemsController.add([partners]);
    await tester.pump();

    await tester.tap(find.textContaining('用意する'));
    await tester.pump();

    final reservation = await db
        .collection('couples')
        .doc('couple-1')
        .collection('wishlistReservations')
        .doc(partners.id)
        .get();
    expect(reservation.data()!['reservedBy'], meUid);

    await itemsController.close();
  });

  testWidgets('削除ボタンは確認をとってから消す（キャンセルすれば残る）', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = WishlistService(firestore: db, uid: meUid);
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('wishlistItems')
        .doc(mine.id)
        .set(mine.toMap());

    final controller = StreamController<List<WishlistItem>>();
    await tester.pumpWidget(wrap(controller.stream, wishlistService: service));

    controller.add([mine]);
    await tester.pump();

    Future<DocumentSnapshot<Map<String, dynamic>>> storedDoc() => db
        .collection('couples')
        .doc('couple-1')
        .collection('wishlistItems')
        .doc(mine.id)
        .get();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.textContaining('元に戻せません'), findsOneWidget);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect((await storedDoc()).exists, isTrue, reason: 'キャンセルでは消さない');

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();

    expect((await storedDoc()).exists, isFalse);

    await controller.close();
  });

  testWidgets('欲しいものとリンクを入力して追加すると、指定したリンクで追加される', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = WishlistService(firestore: db, uid: meUid);

    final controller = StreamController<List<WishlistItem>>();
    await tester.pumpWidget(wrap(controller.stream, wishlistService: service));

    controller.add([]);
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), '腕時計');
    await tester.enterText(find.byType(TextField).at(1), 'https://example.com/watch');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    final snap = await db
        .collection('couples')
        .doc('couple-1')
        .collection('wishlistItems')
        .get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.single.data()['text'], '腕時計');
    expect(snap.docs.single.data()['url'], 'https://example.com/watch');
    expect(snap.docs.single.data()['addedBy'], meUid);

    await controller.close();
  });

  testWidgets('追加に失敗したら入力欄の文字列を戻してエラーを表示する', (tester) async {
    final controller = StreamController<List<WishlistItem>>();
    await tester.pumpWidget(wrap(controller.stream, wishlistService: _ThrowingWishlistService()));

    controller.add([]);
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), '腕時計');
    await tester.enterText(find.byType(TextField).at(1), 'https://example.com/watch');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('追加に失敗しました。もう一度お試しください'), findsOneWidget);
    expect(find.text('腕時計'), findsOneWidget, reason: '失敗したら入力欄に文字列を戻す');
    expect(find.text('https://example.com/watch'), findsOneWidget);

    await controller.close();
  });

  testWidgets('削除に失敗したらエラーを表示する', (tester) async {
    final controller = StreamController<List<WishlistItem>>();
    await tester.pumpWidget(wrap(controller.stream, wishlistService: _ThrowingWishlistService()));

    controller.add([mine]);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();

    expect(find.text('削除に失敗しました。もう一度お試しください'), findsOneWidget);

    await controller.close();
  });
}

class _ThrowingWishlistService extends WishlistService {
  _ThrowingWishlistService() : super(firestore: FakeFirebaseFirestore(), uid: 'user-me');

  @override
  Future<WishlistItem> addItem(String coupleId, String text, {String? url}) {
    throw Exception('firestore unavailable');
  }

  @override
  Future<void> deleteItem(WishlistItem item) {
    throw Exception('firestore unavailable');
  }
}
