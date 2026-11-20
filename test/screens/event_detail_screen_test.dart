import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/event_detail_screen.dart';
import 'package:aimaru/services/event_comment_service.dart';
import 'package:aimaru/services/event_service.dart';
import 'package:aimaru/widgets/circular_action_button.dart';

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
    EventService? eventService,
  }) =>
      MaterialApp(
        home: EventDetailScreen(
          event: sampleEvent,
          coupleId: 'couple-1',
          commentsStreamOverride: stream,
          commentServiceOverride: commentService,
          currentUidOverride: currentUid,
          eventServiceOverride: eventService,
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

  testWidgets('送信ボタンはボタンとして読み上げられ、タップ時にリップルを出せる', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = StreamController<List<EventComment>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(
      tester.getSemantics(find.bySemanticsLabel('コメントを送信')),
      matchesSemantics(
          label: 'コメントを送信', isButton: true, hasEnabledState: true, isEnabled: true),
    );
    expect(find.descendant(
      of: find.byType(CircularActionButton),
      matching: find.byType(InkWell),
    ), findsOneWidget);

    await controller.close();
    handle.dispose();
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

  testWidgets('コメントの送信に失敗したら入力を戻してSnackBarで知らせる', (tester) async {
    final controller = StreamController<List<EventComment>>();
    await tester.pumpWidget(
        wrap(controller.stream, commentService: _ThrowingCommentService()));
    controller.add([]);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'いいね！');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump();

    expect(find.text('コメントの送信に失敗しました。もう一度お試しください'), findsOneWidget);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, 'いいね！');
    expect(tester.takeException(), isNull);

    await controller.close();
  });

  testWidgets('予定の削除に失敗したらSnackBarで知らせ、画面に留まる', (tester) async {
    final controller = StreamController<List<EventComment>>();
    await tester.pumpWidget(
        wrap(controller.stream, eventService: _ThrowingEventService()));
    controller.add([]);
    await tester.pump();

    final deleteButton = find.text('この予定を削除');
    await tester.ensureVisible(deleteButton.first);
    await tester.tap(deleteButton.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除する'));
    await tester.pumpAndSettle();

    expect(find.text('削除に失敗しました。もう一度お試しください'), findsOneWidget);
    expect(find.byType(EventDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await controller.close();
  });
}

class _ThrowingCommentService extends EventCommentService {
  _ThrowingCommentService() : super(firestore: FakeFirebaseFirestore(), uid: 'user-me');

  @override
  Future<void> addComment(String coupleId, String eventId, String text) =>
      Future.error(Exception('PERMISSION_DENIED'));
}

class _ThrowingEventService extends EventService {
  _ThrowingEventService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<void> deleteEvent(AimaruEvent event) =>
      Future.error(Exception('PERMISSION_DENIED'));
}
