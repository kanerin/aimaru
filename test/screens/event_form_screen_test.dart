import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/event_form_screen.dart';
import 'package:aimaru/services/event_service.dart';
import 'package:aimaru/services/google_calendar_service.dart';
import 'package:aimaru/services/storage_service.dart';

// StorageService/GoogleCalendarServiceは本番実装がFirebase/Google APIに
// 触れるため、必要なメソッドだけを差し替えたフェイクをサブクラスとして用意する
// （bug_report_screen_test.dartの_FakeStorageServiceと同じ設計）。
class _FakeStorageService extends StorageService {
  final Future<String> Function(String coupleId, String eventId, File file) uploadEventImageImpl;
  _FakeStorageService(this.uploadEventImageImpl);

  @override
  Future<String> uploadEventImage(String coupleId, String eventId, File file) =>
      uploadEventImageImpl(coupleId, eventId, file);
}

class _FakeGoogleCalendarService extends GoogleCalendarService {
  final Future<String?> Function(AimaruEvent event)? pushEventImpl;
  _FakeGoogleCalendarService({this.pushEventImpl});

  @override
  Future<String?> pushEvent(AimaruEvent event) =>
      pushEventImpl?.call(event) ?? Future.value(null);

  @override
  Future<GCalResult> deleteEvent(String googleEventId) => Future.value(const GCalResult.success());
}

// addEvent/updateEventの失敗経路（保存失敗時の画面挙動）を検証するための、
// 常に例外を投げるフェイク。
class _ThrowingEventService extends EventService {
  _ThrowingEventService({required FirebaseFirestore firestore, required String uid})
      : super(firestore: firestore, uid: uid);

  @override
  Future<AimaruEvent> addEvent(String coupleId, AimaruEvent event) async {
    throw Exception('firestore unavailable');
  }

  @override
  Future<void> updateEvent(AimaruEvent event) async {
    throw Exception('firestore unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const coupleId = 'couple-1';
  const meUid = 'user-me';

  late FakeFirebaseFirestore db;
  late EventService eventService;

  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    eventService = EventService(firestore: db, uid: meUid);
  });

  CollectionReference<Map<String, dynamic>> eventsRef() =>
      db.collection('couples').doc(coupleId).collection('events');

  AimaruEvent buildExisting() => AimaruEvent(
        id: 'event-1',
        coupleId: coupleId,
        title: '水族館デート',
        date: DateTime(2026, 9, 1, 10, 0),
        endDate: DateTime(2026, 9, 1, 12, 0),
        type: EventType.date,
        createdBy: meUid,
      );

  // EventFormScreenはpushして開く画面のため、遷移元の画面からpushして開き、
  // 保存後にpopされて遷移元へ戻ったかどうかまで含めて検証する。
  Future<void> openForm(
    WidgetTester tester, {
    AimaruEvent? existing,
    EventService? eventServiceOverride,
    StorageService? storageService,
    GoogleCalendarService? calendarService,
    List<File>? initialImages,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EventFormScreen(
                  coupleId: coupleId,
                  existing: existing,
                  eventServiceOverride: eventServiceOverride ?? eventService,
                  storageServiceOverride: storageService,
                  calendarServiceOverride: calendarService,
                  initialImagesForTest: initialImages,
                ),
              )),
              child: const Text('起点画面'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('起点画面'));
    await tester.pumpAndSettle();
  }

  testWidgets('タイトルが空のまま保存するとバリデーションメッセージが出て保存されない', (tester) async {
    await openForm(tester);

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('タイトルを入力してください'), findsOneWidget);
    expect((await eventsRef().get()).docs, isEmpty);
    expect(find.text('新しい予定'), findsOneWidget);
  });

  testWidgets('タイトルを入力して保存すると予定が作成され、前の画面に戻る', (tester) async {
    await openForm(tester);

    await tester.enterText(find.byType(TextField).first, '水族館デート');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    final docs = (await eventsRef().get()).docs;
    expect(docs, hasLength(1));
    expect(docs.first.data()['title'], '水族館デート');
    expect(docs.first.data()['createdBy'], meUid);
    expect(find.text('起点画面'), findsOneWidget);
  });

  testWidgets('既存の予定を編集すると、内容がFirestoreへ反映される', (tester) async {
    final existing = buildExisting();
    await eventsRef().doc(existing.id).set(existing.toMap());

    await openForm(tester, existing: existing);

    expect(find.text('水族館デート'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '花火大会');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    final doc = await eventsRef().doc(existing.id).get();
    expect(doc.data()!['title'], '花火大会');
    expect(find.text('起点画面'), findsOneWidget);
  });

  testWidgets('保存に失敗した場合はエラーメッセージを表示し、再度保存できる状態に戻す', (tester) async {
    final failingService = _ThrowingEventService(firestore: db, uid: meUid);
    await openForm(tester, eventServiceOverride: failingService);

    await tester.enterText(find.byType(TextField).first, '水族館デート');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('保存に失敗しました。もう一度お試しください'), findsOneWidget);
    // popされず、保存ボタンが再度押せる状態（_saving == false）に戻っている
    expect(find.text('新しい予定'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '保存'), findsOneWidget);
  });

  testWidgets('「自分だけに表示」をONにして保存すると、visibilityがprivateとして保存される', (tester) async {
    await openForm(tester);

    await tester.enterText(find.byType(TextField).first, '内緒の予定');
    await tester.tap(find.byType(Switch).at(2)); // 「自分だけに表示（相手には見えません）」
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    final docs = (await eventsRef().get()).docs;
    expect(docs.first.data()['visibility'], 'private');
  });

  testWidgets('Googleカレンダー同期をONにして保存すると、pushEventが呼ばれgoogleCalendarEventIdが保存される', (tester) async {
    // フォーム末尾の「Googleカレンダーに同期」トグルまで、スクロールせず
    // 一画面に収まるよう十分な高さを確保する
    // （TextFieldのEditableTextも内部にScrollableを持つため、
    // Scrollableが複数存在しscrollUntilVisibleでは一意に特定できない）。
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final calendarService = _FakeGoogleCalendarService(
      pushEventImpl: (event) async => 'gcal-event-1',
    );
    await openForm(tester, calendarService: calendarService);

    await tester.enterText(find.byType(TextField).first, '水族館デート');
    await tester.tap(find.byType(Switch).at(3)); // 「Googleカレンダーに同期」
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    final docs = (await eventsRef().get()).docs;
    expect(docs.first.data()['googleCalendarEventId'], 'gcal-event-1');
  });

  testWidgets('新しい画像を選択済みの状態で保存すると、アップロードされURLが保存される', (tester) async {
    final storageService = _FakeStorageService(
      (coupleId, eventId, file) async => 'https://example.com/${file.path}',
    );
    await openForm(
      tester,
      storageService: storageService,
      initialImages: [File('fake/photo.jpg')],
    );

    await tester.enterText(find.byType(TextField).first, '水族館デート');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    final docs = (await eventsRef().get()).docs;
    expect(docs.first.data()['imageUrls'], ['https://example.com/fake/photo.jpg']);
  });
}
