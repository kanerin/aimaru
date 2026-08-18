// 結合テスト: 割り勘・立て替えが実際のFirestoreを通して成立することを確認する。
//
// test/screens/expenses_screen_test.dart は注入したストリームで3状態を見ているが、
// それでは ExpenseService.watchExpenses（orderBy付きのクエリ）も
// ExpenseItem.fromDoc（Timestampの読み取り）もセキュリティルールも通らない。
// 実際に「画面を開くと読み込みに失敗しました」になる不具合が出たとき、
// この経路が一度も検証されていなかったため、原因がコードなのかルールなのかを
// 切り分けられなかった。ここを実データで往復させて塞ぐ。
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:aimaru/screens/expenses_screen.dart';
import 'package:aimaru/services/expense_service.dart';

import 'helpers/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initE2E();
  });

  setUp(() async {
    await signInAndSeedCouple(withPartner: true);
  });

  tearDownAll(() async {
    await signOutTestUser();
  });

  Future<List<String>> memberIds() async {
    final doc = await FirebaseFirestore.instance
        .collection('couples')
        .doc(testCoupleId)
        .get();
    return List<String>.from(doc.data()!['memberIds'] as List);
  }

  Future<Widget> screen() async => ExpensesScreen(
        coupleId: testCoupleId,
        memberIds: await memberIds(),
        partnerName: 'テスト花子',
      );

  testWidgets('記録が無くても読み込みに失敗せず、空の状態が出る', (tester) async {
    await pumpScreen(tester, await screen());

    await pumpUntil(
      tester,
      () => find.textContaining('まだ記録がありません').evaluate().isNotEmpty,
      reason: '空のときに「読み込みに失敗しました」になっていないか',
    );

    expect(find.textContaining('読み込みに失敗'), findsNothing);
    expect(find.text('精算は完了しています'), findsOneWidget);
  });

  testWidgets('入力して追加すると、一覧とFirestoreの両方に反映される', (tester) async {
    await pumpScreen(tester, await screen());
    await pumpUntil(
      tester,
      () => find.textContaining('まだ記録がありません').evaluate().isNotEmpty,
    );

    await tester.enterText(textFieldWithHint('内容'), 'ディナー代');
    await tester.enterText(textFieldWithHint('金額'), '3600');
    await settle(tester);
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);

    await pumpUntil(
      tester,
      () => find.text('ディナー代').evaluate().isNotEmpty,
      reason: '追加した記録が一覧に出ない',
    );
    expect(find.text('¥3600'), findsOneWidget);
    expect(find.textContaining('読み込みに失敗'), findsNothing);

    final snap = await FirebaseFirestore.instance
        .collection('couples')
        .doc(testCoupleId)
        .collection('expenses')
        .get();
    expect(snap.docs, hasLength(1), reason: 'Firestoreに保存されていない');
    expect(snap.docs.first.data()['amount'], 3600);
    expect(snap.docs.first.data()['createdAt'], isA<Timestamp>(),
        reason: 'createdAtがTimestampでないとfromDocの読み取りで落ちる');
  });

  testWidgets('既にある記録を読み直しても失敗せず、精算額が出る', (tester) async {
    // 画面を開く前にデータを入れておく（既存データの読み取り経路）
    final members = await memberIds();
    final service = ExpenseService();
    await service.addExpense(testCoupleId, '映画代', 3000, members.first);
    await service.addExpense(testCoupleId, 'カフェ代', 1000, members.last);

    await pumpScreen(tester, await screen());

    await pumpUntil(
      tester,
      () => find.text('映画代').evaluate().isNotEmpty,
      reason: '既存の記録が読み込めない（読み込みに失敗しましたになっていないか）',
    );

    expect(find.textContaining('読み込みに失敗'), findsNothing);
    expect(find.text('カフェ代'), findsOneWidget);
    // 自分が3000、パートナーが1000払ったので差額1000を渡すと精算される
    expect(find.textContaining('¥1000を渡すと精算されます'), findsOneWidget);
  });
}
