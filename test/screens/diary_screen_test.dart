import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/diary_screen.dart';

// ふたりの日記画面がストリームエラーで無限ローディングのまま固まらないこと、
// 自分/相手の日記の表示の出し分けを確かめる。
void main() {
  const uidA = 'user-a';
  const uidB = 'user-b';
  final now = DateTime(2026, 8, 17);

  Widget wrap(Stream<List<DiaryEntry>> stream) => MaterialApp(
        home: DiaryScreen(
          coupleId: 'couple-1',
          memberIds: const [uidA, uidB],
          partnerName: 'パートナー',
          currentUidOverride: uidA,
          nowOverride: now,
          entriesStreamOverride: stream,
        ),
      );

  DiaryEntry buildEntry({required String uid, required String dateKey, required String text}) =>
      DiaryEntry(
        id: '${dateKey}_$uid',
        coupleId: 'couple-1',
        dateKey: dateKey,
        uid: uid,
        text: text,
        createdAt: now,
        updatedAt: now,
      );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<DiaryEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<DiaryEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('誰も書いていなければ空の入力欄のみ表示する', (tester) async {
    final controller = StreamController<List<DiaryEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('保存する'), findsOneWidget);
    expect(find.text('削除'), findsNothing);
  });

  testWidgets('自分が今日書いていれば入力欄に反映され削除ボタンが出る', (tester) async {
    final controller = StreamController<List<DiaryEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([buildEntry(uid: uidA, dateKey: '2026-08-17', text: '公園を散歩した')]);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '公園を散歩した');
    expect(find.text('削除'), findsOneWidget);
  });

  testWidgets('パートナーが今日書いていれば内容を表示する', (tester) async {
    final controller = StreamController<List<DiaryEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([buildEntry(uid: uidB, dateKey: '2026-08-17', text: '映画を見た')]);
    await tester.pump();

    expect(find.text('映画を見た'), findsOneWidget);
    expect(find.text('パートナー'), findsOneWidget);
  });

  testWidgets('過去の日記は日付ごとにまとめて履歴に表示する', (tester) async {
    final controller = StreamController<List<DiaryEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      buildEntry(uid: uidA, dateKey: '2026-08-16', text: '昨日の自分の日記'),
      buildEntry(uid: uidB, dateKey: '2026-08-16', text: '昨日の相手の日記'),
    ]);
    await tester.pump();

    expect(find.text('これまでの日記'), findsOneWidget);
    expect(find.text('2026-08-16'), findsOneWidget);
    expect(find.text('昨日の自分の日記'), findsOneWidget);
    expect(find.text('昨日の相手の日記'), findsOneWidget);
  });
}
