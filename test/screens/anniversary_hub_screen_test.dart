import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/anniversary_hub_screen.dart';

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

    expect(find.text('入籍日'), findsOneWidget);
    expect(find.text('初デート'), findsOneWidget);

    // 近い順（初デートが先）に並んでいることを確認する
    final firstTitleCenter = tester.getCenter(find.text('初デート'));
    final secondTitleCenter = tester.getCenter(find.text('入籍日'));
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
}
