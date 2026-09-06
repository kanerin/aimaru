import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/mood_screen.dart';
import 'package:aimaru/services/mood_service.dart';

// きょうの気分画面がストリームエラーで無限ローディングのまま固まらないこと、
// 自分/相手の気分の表示の出し分けを確かめる。
void main() {
  const uidA = 'user-a';
  const uidB = 'user-b';
  final now = DateTime(2026, 8, 17);

  Widget wrap(Stream<List<MoodEntry>> stream, {MoodService? moodServiceOverride}) => MaterialApp(
        home: MoodScreen(
          coupleId: 'couple-1',
          memberIds: const [uidA, uidB],
          partnerName: 'パートナー',
          currentUidOverride: uidA,
          nowOverride: now,
          entriesStreamOverride: stream,
          moodServiceOverride: moodServiceOverride,
        ),
      );

  MoodEntry buildEntry({required String uid, required String dateKey, required String mood}) =>
      MoodEntry(
        id: '${dateKey}_$uid',
        coupleId: 'couple-1',
        dateKey: dateKey,
        uid: uid,
        mood: mood,
        createdAt: now,
      );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<MoodEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<MoodEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('誰も選んでいなければ気分の選択肢だけ表示する', (tester) async {
    final controller = StreamController<List<MoodEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    for (final option in moodOptions) {
      expect(find.text(option.emoji), findsOneWidget);
    }
    expect(find.textContaining('あなた'), findsNothing);
  });

  testWidgets('気分をタップすると保存される', (tester) async {
    final db = FakeFirebaseFirestore();
    final moodService = MoodService(firestore: db, uid: uidA);
    final controller = StreamController<List<MoodEntry>>();
    await tester.pumpWidget(wrap(controller.stream, moodServiceOverride: moodService));

    controller.add([]);
    await tester.pump();

    await tester.tap(find.text('😄'));
    await tester.pumpAndSettle();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('moodEntries')
        .doc('2026-08-17_$uidA')
        .get();
    expect(doc.data()!['mood'], 'great');

    await controller.close();
  });

  testWidgets('パートナーが今日選んでいれば内容を表示する', (tester) async {
    final controller = StreamController<List<MoodEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([buildEntry(uid: uidB, dateKey: '2026-08-17', mood: 'good')]);
    await tester.pump();

    expect(find.text('🙂 良い'), findsOneWidget);
    expect(find.text('パートナー'), findsOneWidget);
  });

  testWidgets('過去の気分は日付ごとにまとめて履歴に表示する', (tester) async {
    final controller = StreamController<List<MoodEntry>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      buildEntry(uid: uidA, dateKey: '2026-08-16', mood: 'okay'),
      buildEntry(uid: uidB, dateKey: '2026-08-16', mood: 'bad'),
    ]);
    await tester.pump();

    expect(find.text('これまでの気分'), findsOneWidget);
    expect(find.text('2026-08-16'), findsOneWidget);
    expect(find.text('😐 ふつう'), findsOneWidget);
    expect(find.text('😔 いまいち'), findsOneWidget);
  });
}
