import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/shopping_list_screen.dart';
import 'package:aimaru/services/shopping_list_service.dart';

// 買い物リスト画面がストリームエラーで無限ローディングのまま固まらないこと、
// アイテムの追加・購入済み切り替え・削除・一括削除ができることを確かめる。
void main() {
  Widget wrap(
    Stream<List<ShoppingItem>> stream, {
    ShoppingListService? shoppingListService,
  }) =>
      MaterialApp(
        home: ShoppingListScreen(
          coupleId: 'couple-1',
          itemsStreamOverride: stream,
          shoppingListServiceOverride: shoppingListService,
        ),
      );

  final sampleItem = ShoppingItem(
    id: 'i1',
    coupleId: 'couple-1',
    title: '牛乳',
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
  );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<ShoppingItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<ShoppingItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが無ければ空表示になる', (tester) async {
    final controller = StreamController<List<ShoppingItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    expect(find.textContaining('まだ買い物リストは空です'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが来たら一覧を表示し、数量があればバッジ表示する', (tester) async {
    final controller = StreamController<List<ShoppingItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      ShoppingItem(
        id: 'i1', coupleId: 'couple-1', title: '卵',
        quantity: '1パック', createdBy: 'u1', createdAt: DateTime(2026, 1, 1),
      ),
    ]);
    await tester.pump();

    expect(find.text('卵'), findsOneWidget);
    expect(find.text('1パック'), findsOneWidget);

    await controller.close();
  });

  testWidgets('削除ボタンを押すとShoppingListServiceのdeleteItemが呼ばれる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = ShoppingListService(firestore: db, uid: 'u1');
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('shoppingItems')
        .doc('i1')
        .set(sampleItem.toMap());

    final controller = StreamController<List<ShoppingItem>>();
    await tester.pumpWidget(wrap(controller.stream, shoppingListService: service));

    controller.add([sampleItem]);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('shoppingItems')
        .doc('i1')
        .get();
    expect(doc.exists, isFalse);

    await controller.close();
  });

  testWidgets('チェックボックスを押すとShoppingListServiceのsetDoneが呼ばれる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = ShoppingListService(firestore: db, uid: 'u1');
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('shoppingItems')
        .doc('i1')
        .set(sampleItem.toMap());

    final controller = StreamController<List<ShoppingItem>>();
    await tester.pumpWidget(wrap(controller.stream, shoppingListService: service));

    controller.add([sampleItem]);
    await tester.pump();

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('shoppingItems')
        .doc('i1')
        .get();
    expect(doc.data()!['done'], isTrue);

    await controller.close();
  });

  testWidgets('買うものと数量を入力して追加すると、指定した数量で追加される', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = ShoppingListService(firestore: db, uid: 'u1');

    final controller = StreamController<List<ShoppingItem>>();
    await tester.pumpWidget(wrap(controller.stream, shoppingListService: service));

    controller.add([]);
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'にんじん');
    await tester.enterText(find.byType(TextField).at(1), '3本');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    final snap = await db
        .collection('couples')
        .doc('couple-1')
        .collection('shoppingItems')
        .get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.single.data()['title'], 'にんじん');
    expect(snap.docs.single.data()['quantity'], '3本');

    await controller.close();
  });

  testWidgets('一括削除ボタンを押すとShoppingListServiceのclearDoneが呼ばれる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = ShoppingListService(firestore: db, uid: 'u1');
    final done = ShoppingItem(
      id: 'i1', coupleId: 'couple-1', title: '購入済み',
      done: true, createdBy: 'u1', createdAt: DateTime(2026, 1, 1),
    );
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('shoppingItems')
        .doc('i1')
        .set(done.toMap());

    final controller = StreamController<List<ShoppingItem>>();
    await tester.pumpWidget(wrap(controller.stream, shoppingListService: service));

    controller.add([done]);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pump();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('shoppingItems')
        .doc('i1')
        .get();
    expect(doc.exists, isFalse);

    await controller.close();
  });
}
