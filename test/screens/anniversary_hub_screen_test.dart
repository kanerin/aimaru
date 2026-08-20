import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/anniversary_hub_screen.dart';
import 'package:aimaru/services/anniversary_service.dart';
import 'package:aimaru/widgets/anniversary_card.dart';

// 記念日タブ（次に会う日・記念日・記念日リストを1画面に統合したもの）を検証する。
// 記念日リスト部分は、旧AnniversariesScreenと同じくストリームエラーで
// 無限ローディングのまま固まらないことを確かめる
// （todos_screen_test.dartと同じ経路の再発防止パターン）。
void main() {
  final couple = CoupleModel(
    id: 'couple-1',
    memberIds: const ['u1', 'u2'],
    inviteCode: 'ABC123',
    createdAt: DateTime(2020, 1, 1),
  );

  Widget wrap(Stream<List<AnniversaryItem>> stream) => MaterialApp(
        home: AnniversaryHubScreen(
          coupleId: 'couple-1',
          anniversariesStreamOverride: stream,
          initialCoupleOverride: couple,
          nowOverride: () => DateTime(2026, 8, 19),
        ),
      );

  testWidgets('次に会う日・記念日のカードが表示される', (tester) async {
    final controller = StreamController<List<AnniversaryItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.text('🗓️ 次に会う日'), findsOneWidget);
    expect(find.text('🎉 記念日'), findsOneWidget);
    expect(find.text('記念日リスト'), findsOneWidget);

    await controller.close();
  });

  testWidgets('記念日リストのデータが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<AnniversaryItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('記念日リストのストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<AnniversaryItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('記念日リストが空なら案内文を表示する', (tester) async {
    final controller = StreamController<List<AnniversaryItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    expect(find.textContaining('まだ記念日がありません'), findsOneWidget);
  });

  testWidgets('記念日リストのデータが来たら一覧を、次の記念日が近い順に表示する', (tester) async {
    final controller = StreamController<List<AnniversaryItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      AnniversaryItem(
        id: 'a1',
        coupleId: 'couple-1',
        title: '入籍日',
        // 2026-08-19基準で次の周年（8/25）が遠い方
        date: DateTime(2020, 8, 25),
        createdBy: 'u1',
        createdAt: DateTime(2020, 8, 25),
      ),
      AnniversaryItem(
        id: 'a2',
        coupleId: 'couple-1',
        title: '初デート',
        // 次の周年（8/20）が近い方
        date: DateTime(2021, 8, 20),
        createdBy: 'u1',
        createdAt: DateTime(2021, 8, 20),
      ),
    ]);
    await tester.pump();

    expect(find.text('🎉 入籍日'), findsOneWidget);
    expect(find.text('🎉 初デート'), findsOneWidget);

    // 近い順（初デートが先）に並んでいることを確認する
    final firstTitleCenter = tester.getCenter(find.text('🎉 初デート'));
    final secondTitleCenter = tester.getCenter(find.text('🎉 入籍日'));
    expect(firstTitleCenter.dy, lessThan(secondTitleCenter.dy));

    await controller.close();
  });

  testWidgets('記念日を追加ボタンがある', (tester) async {
    final controller = StreamController<List<AnniversaryItem>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    expect(find.widgetWithText(OutlinedButton, '記念日を追加'), findsOneWidget);

    await controller.close();
  });

  // ── 記念日リストの編集・削除 ────────────────────────────
  // 以前は左スワイプで消すだけ（確認なし）で、タイトルや日付を間違えても
  // 直す手段が無かった。上の2枚のカードと同じく、右上のアイコンから
  // 編集・削除できるようにしてある。
  group('記念日リストの編集・削除', () {
    late FakeFirebaseFirestore firestore;
    late AnniversaryService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = AnniversaryService(firestore: firestore, uid: 'u1');
    });

    // ストリームを差し替えず、fakeのFirestoreを実際に読み書きさせることで
    // 「操作したら一覧も変わる」ところまで通しで確かめる。
    Widget wrapWithService({
      Future<DateTime?> Function(BuildContext context, DateTime? initial)? pickDate,
    }) =>
        MaterialApp(
          home: AnniversaryHubScreen(
            coupleId: 'couple-1',
            anniversaryServiceOverride: service,
            initialCoupleOverride: couple,
            nowOverride: () => DateTime(2026, 8, 19),
            pickDateOverride: pickDate,
          ),
        );

    Future<AnniversaryItem> seed() =>
        service.addAnniversary('couple-1', '入籍日', DateTime(2020, 8, 25));

    Future<Map<String, dynamic>?> storedDoc(String id) async {
      final doc = await firestore
          .collection('couples').doc('couple-1')
          .collection('anniversaries').doc(id)
          .get();
      return doc.data();
    }

    testWidgets('各項目に編集・削除のボタンがある', (tester) async {
      await seed();
      await tester.pumpWidget(wrapWithService());
      await tester.pumpAndSettle();

      expect(find.byTooltip('記念日を編集'), findsOneWidget);
      expect(find.byTooltip('記念日を削除'), findsOneWidget);
    });

    testWidgets('削除は確認をとってから消す（キャンセルすれば残る）', (tester) async {
      final item = await seed();
      await tester.pumpWidget(wrapWithService());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('記念日を削除'));
      await tester.pumpAndSettle();
      expect(find.textContaining('元に戻せません'), findsOneWidget);

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(await storedDoc(item.id), isNotNull, reason: 'キャンセルでは消さない');
      expect(find.text('🎉 入籍日'), findsOneWidget);

      await tester.tap(find.byTooltip('記念日を削除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();

      expect(await storedDoc(item.id), isNull);
      expect(find.text('🎉 入籍日'), findsNothing);
    });

    testWidgets('編集でタイトルと日付を直せる', (tester) async {
      final item = await seed();
      await tester.pumpWidget(wrapWithService(
        pickDate: (_, __) async => DateTime(2021, 9, 1),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('記念日を編集'));
      await tester.pumpAndSettle();

      // 入力欄には今の値が入っていて、打ち直せる
      expect(find.text('記念日を編集'), findsOneWidget);
      expect(find.widgetWithText(TextField, '入籍日'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '結婚記念日');
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();

      final stored = await storedDoc(item.id);
      expect(stored!['title'], '結婚記念日');
      expect((stored['date'] as Timestamp).toDate(), DateTime(2021, 9, 1));
      // 登録者・登録日時は編集で書き換えない
      expect(stored['createdBy'], 'u1');

      expect(find.text('🎉 結婚記念日'), findsOneWidget);
    });

    testWidgets('編集をキャンセルすると何も変わらない', (tester) async {
      final item = await seed();
      await tester.pumpWidget(wrapWithService(
        pickDate: (_, __) async => DateTime(2021, 9, 1),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('記念日を編集'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      final stored = await storedDoc(item.id);
      expect(stored!['title'], '入籍日');
      expect((stored['date'] as Timestamp).toDate(), DateTime(2020, 8, 25));
    });

    // 「記念日リストだけ中央に細長い」という見た目のちぐはぐさを直したところ。
    testWidgets('リストの項目は上の記念日カードと同じ幅で並ぶ', (tester) async {
      await seed();
      await tester.pumpWidget(wrapWithService());
      await tester.pumpAndSettle();

      final cardWidth = tester.getSize(find.byType(AnniversaryCard)).width;
      final tileWidth = tester
          .getSize(find
              .ancestor(of: find.text('🎉 入籍日'), matching: find.byType(Container))
              .first)
          .width;

      expect(tileWidth, cardWidth);
    });
  });
}
