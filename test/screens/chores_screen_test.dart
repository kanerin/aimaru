import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/chores_screen.dart';
import 'package:aimaru/services/chore_service.dart';

// 家事分担画面がストリームエラーで無限ローディングのまま固まらないこと、
// 担当の割り当て・完了切り替え・削除ができることを確かめる。
void main() {
  Widget wrap(
    Stream<List<ChoreItem>> stream, {
    ChoreService? choreService,
    String currentUid = 'u1',
    List<String> memberIds = const ['u1', 'u2'],
    String partnerName = 'ぱーとなー',
  }) =>
      MaterialApp(
        home: ChoresScreen(
          coupleId: 'couple-1',
          memberIds: memberIds,
          partnerName: partnerName,
          choresStreamOverride: stream,
          choreServiceOverride: choreService,
          currentUidOverride: currentUid,
        ),
      );

  final sampleChore = ChoreItem(
    id: 'c1',
    coupleId: 'couple-1',
    title: '皿洗い',
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
  );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<ChoreItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<ChoreItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが無ければ空表示になる', (tester) async {
    final controller = StreamController<List<ChoreItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    expect(find.textContaining('まだ家事がありません'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが来たら一覧を表示し、担当なしは「どちらでも」表示', (tester) async {
    final controller = StreamController<List<ChoreItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([sampleChore]);
    await tester.pump();

    expect(find.text('皿洗い'), findsOneWidget);
    expect(find.text('どちらでも'), findsWidgets);

    await controller.close();
  });

  testWidgets('自分の担当は「自分」、相手の担当はパートナー名で表示', (tester) async {
    final controller = StreamController<List<ChoreItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      ChoreItem(
        id: 'c1', coupleId: 'couple-1', title: '皿洗い',
        assignedTo: 'u1', createdBy: 'u1', createdAt: DateTime(2026, 1, 1),
      ),
      ChoreItem(
        id: 'c2', coupleId: 'couple-1', title: 'ゴミ出し',
        assignedTo: 'u2', createdBy: 'u1', createdAt: DateTime(2026, 1, 1),
      ),
    ]);
    await tester.pump();

    expect(find.text('自分'), findsWidgets);
    expect(find.text('ぱーとなー'), findsWidgets);

    await controller.close();
  });

  testWidgets('削除ボタンを押すとChoreServiceのdeleteChoreが呼ばれる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = ChoreService(firestore: db, uid: 'u1');
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('chores')
        .doc('c1')
        .set(sampleChore.toMap());

    final controller = StreamController<List<ChoreItem>>();
    await tester.pumpWidget(wrap(controller.stream, choreService: service));

    controller.add([sampleChore]);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('chores')
        .doc('c1')
        .get();
    expect(doc.exists, isFalse);

    await controller.close();
  });

  testWidgets('チェックボックスを押すとChoreServiceのsetDoneが呼ばれる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = ChoreService(firestore: db, uid: 'u1');
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('chores')
        .doc('c1')
        .set(sampleChore.toMap());

    final controller = StreamController<List<ChoreItem>>();
    await tester.pumpWidget(wrap(controller.stream, choreService: service));

    controller.add([sampleChore]);
    await tester.pump();

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('chores')
        .doc('c1')
        .get();
    expect(doc.data()!['done'], isTrue);

    await controller.close();
  });

  testWidgets('担当チップを選んでから追加すると、指定した担当で追加される', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = ChoreService(firestore: db, uid: 'u1');

    final controller = StreamController<List<ChoreItem>>();
    await tester.pumpWidget(wrap(controller.stream, choreService: service));

    controller.add([]);
    await tester.pump();

    // 「自分」チップを選んでから入力・追加する。
    await tester.tap(find.widgetWithText(ChoiceChip, '自分'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '洗濯物をたたむ');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    final snap = await db
        .collection('couples')
        .doc('couple-1')
        .collection('chores')
        .get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.single.data()['title'], '洗濯物をたたむ');
    expect(snap.docs.single.data()['assignedTo'], 'u1');

    await controller.close();
  });

  testWidgets('リセットボタンを押すとChoreServiceのresetAllDoneが呼ばれる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = ChoreService(firestore: db, uid: 'u1');
    final done = ChoreItem(
      id: 'c1', coupleId: 'couple-1', title: '完了済み',
      done: true, createdBy: 'u1', createdAt: DateTime(2026, 1, 1),
    );
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('chores')
        .doc('c1')
        .set(done.toMap());

    final controller = StreamController<List<ChoreItem>>();
    await tester.pumpWidget(wrap(controller.stream, choreService: service));

    controller.add([done]);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('chores')
        .doc('c1')
        .get();
    expect(doc.data()!['done'], isFalse);

    await controller.close();
  });
}
