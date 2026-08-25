import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/event_detail_screen.dart';
import 'package:aimaru/services/event_comment_service.dart';

// 予定の詳細画面のコメント欄が、ストリームエラーで無限ローディングのまま
// 固まらないことを確かめる。test/screens/todos_screen_test.dartと同じパターン
// （StreamBuilderはhasDataだけでなくhasErrorも見る必要がある）。
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  final sampleEvent = AimaruEvent(
    id: 'event-1',
    coupleId: 'couple-1',
    title: 'デート',
    date: DateTime(2026, 8, 22, 19, 0),
    type: EventType.date,
    createdBy: 'user-me',
  );

  Widget wrap(
    Stream<List<EventComment>> stream, {
    EventCommentService? commentService,
    String currentUid = 'user-me',
  }) =>
      MaterialApp(
        home: EventDetailScreen(
          event: sampleEvent,
          coupleId: 'couple-1',
          commentsStreamOverride: stream,
          commentServiceOverride: commentService,
          currentUidOverride: currentUid,
        ),
      );

  testWidgets('コメントが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<EventComment>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<EventComment>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('コメントが無ければ空の案内を表示する', (tester) async {
    final controller = StreamController<List<EventComment>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    expect(find.text('まだコメントはありません'), findsOneWidget);

    await controller.close();
  });

  testWidgets('コメントが来たら一覧に表示する', (tester) async {
    final controller = StreamController<List<EventComment>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      EventComment(
        id: 'c1',
        coupleId: 'couple-1',
        eventId: 'event-1',
        text: '楽しみ！',
        senderId: 'user-partner',
        createdAt: DateTime(2026, 8, 20, 10, 0),
      ),
    ]);
    await tester.pump();

    expect(find.text('楽しみ！'), findsOneWidget);

    await controller.close();
  });

  testWidgets('自分のコメントは右寄り、相手のコメントは左寄りに表示する', (tester) async {
    final controller = StreamController<List<EventComment>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      EventComment(
        id: 'c1',
        coupleId: 'couple-1',
        eventId: 'event-1',
        text: '自分のコメント',
        senderId: 'user-me',
        createdAt: DateTime(2026, 8, 20, 10, 0),
      ),
      EventComment(
        id: 'c2',
        coupleId: 'couple-1',
        eventId: 'event-1',
        text: '相手のコメント',
        senderId: 'user-partner',
        createdAt: DateTime(2026, 8, 20, 10, 1),
      ),
    ]);
    await tester.pump();

    final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
    final meCenter = tester.getCenter(find.text('自分のコメント'));
    final partnerCenter = tester.getCenter(find.text('相手のコメント'));

    expect(meCenter.dx, greaterThan(screenWidth / 2));
    expect(partnerCenter.dx, lessThan(screenWidth / 2));

    await controller.close();
  });

  testWidgets('送信ボタンを押すとEventCommentServiceのaddCommentが呼ばれる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = EventCommentService(firestore: db, uid: 'user-me');

    final controller = StreamController<List<EventComment>>();
    await tester.pumpWidget(wrap(controller.stream, commentService: service));

    controller.add([]);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'いいね！');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();

    final snap = await db
        .collection('couples')
        .doc('couple-1')
        .collection('events')
        .doc('event-1')
        .collection('comments')
        .get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.first.data()['text'], 'いいね！');
    expect(snap.docs.first.data()['senderId'], 'user-me');

    await controller.close();
  });

  testWidgets('送信すると入力欄が空になる', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = EventCommentService(firestore: db, uid: 'user-me');

    final controller = StreamController<List<EventComment>>();
    await tester.pumpWidget(wrap(controller.stream, commentService: service));

    controller.add([]);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'いいね！');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();

    expect(find.text('いいね！'), findsNothing);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, isEmpty);

    await controller.close();
  });
}
