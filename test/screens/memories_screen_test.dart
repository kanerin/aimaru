import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/memories_screen.dart';

// 思い出画面がストリームエラーで無限ローディングのまま固まらないこと、
// および「n年前の今日」の振り返りが正しく出ることを確かめる。
void main() {
  Widget wrap(
    Stream<Map<DateTime, List<AimaruEvent>>> stream, {
    DateTime? now,
  }) =>
      MaterialApp(
        home: MemoriesScreen(
          coupleId: 'couple-1',
          eventsStreamOverride: stream,
          nowOverride: now != null ? () => now : null,
        ),
      );

  AimaruEvent buildEvent({
    required String id,
    required DateTime date,
    List<String> imageUrls = const [],
  }) =>
      AimaruEvent(
        id: id,
        coupleId: 'couple-1',
        title: 'イベント$id',
        date: date,
        type: EventType.date,
        createdBy: 'u1',
        imageUrls: imageUrls,
      );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('写真つきの予定を一覧表示する', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    await tester.pumpWidget(wrap(controller.stream, now: DateTime(2026, 8, 16)));

    final e = buildEvent(id: 'a', date: DateTime(2026, 1, 1), imageUrls: const ['https://example.com/a.jpg']);
    controller.add({DateTime(2026, 1, 1): [e]});
    await tester.pump();

    expect(find.text('1枚'), findsOneWidget);

    await controller.close();
  });

  testWidgets('n年前の今日と一致する予定があれば振り返りセクションを表示する', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    await tester.pumpWidget(wrap(controller.stream, now: DateTime(2026, 8, 16)));

    final e = buildEvent(id: 'b', date: DateTime(2024, 8, 16));
    controller.add({DateTime(2024, 8, 16): [e]});
    await tester.pump();

    expect(find.text('📅 今日の思い出'), findsOneWidget);
    expect(find.text('2年前の今日'), findsOneWidget);
    expect(find.text('イベントb'), findsOneWidget);

    await controller.close();
  });

  testWidgets('n年前の今日と一致する予定が無ければ振り返りセクションを表示しない', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    await tester.pumpWidget(wrap(controller.stream, now: DateTime(2026, 8, 16)));

    final e = buildEvent(id: 'c', date: DateTime(2024, 1, 1));
    controller.add({DateTime(2024, 1, 1): [e]});
    await tester.pump();

    expect(find.text('📅 今日の思い出'), findsNothing);

    await controller.close();
  });
}
