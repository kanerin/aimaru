import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/ics_import_screen.dart';
import 'package:aimaru/services/event_service.dart';

const _sampleIcs = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART:20260301T090000Z
SUMMARY:デート
LOCATION:カフェ
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20260305
SUMMARY:記念日
END:VEVENT
END:VCALENDAR
''';

// 指定回数目の追加から例外を投げるEventService。
class _FailingEventService extends EventService {
  _FailingEventService({required super.firestore, required super.uid, required this.succeedTimes});
  int succeedTimes;

  @override
  Future<AimaruEvent> addEvent(String coupleId, AimaruEvent event) async {
    if (succeedTimes <= 0) throw Exception('firestore unavailable');
    succeedTimes--;
    return super.addEvent(coupleId, event);
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  Widget wrap({
    required Future<String> Function(String) loadIcsTextOverride,
    EventService? eventService,
  }) =>
      MaterialApp(
        home: IcsImportScreen(
          coupleId: 'couple-1',
          loadIcsTextOverride: loadIcsTextOverride,
          eventServiceOverride: eventService,
        ),
      );

  testWidgets('読み込み中はローディング表示', (tester) async {
    final completer = Completer<String>();
    await tester.pumpWidget(wrap(loadIcsTextOverride: (_) => completer.future));

    await tester.enterText(find.byType(TextField), 'https://example.com/cal.ics');
    await tester.tap(find.text('読み込む'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(_sampleIcs);
    await tester.pumpAndSettle();
  });

  testWidgets('読み込みに失敗したらエラー表示にする（無限ローディングにしない）', (tester) async {
    await tester.pumpWidget(wrap(
      loadIcsTextOverride: (_) => Future.error(Exception('HTTP 404')),
    ));

    await tester.enterText(find.byType(TextField), 'https://example.com/cal.ics');
    await tester.tap(find.text('読み込む'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);
  });

  testWidgets('パースできた予定を一覧表示する', (tester) async {
    await tester.pumpWidget(wrap(loadIcsTextOverride: (_) => Future.value(_sampleIcs)));

    await tester.enterText(find.byType(TextField), _sampleIcs);
    await tester.tap(find.text('読み込む'));
    await tester.pumpAndSettle();

    expect(find.text('デート'), findsOneWidget);
    expect(find.text('記念日'), findsOneWidget);
    expect(find.textContaining('選択した2件を追加'), findsOneWidget);
  });

  testWidgets('選択した予定だけがFirestoreに追加される', (tester) async {
    final db = FakeFirebaseFirestore();
    final eventService = EventService(firestore: db, uid: 'user-me');

    await tester.pumpWidget(wrap(
      loadIcsTextOverride: (_) => Future.value(_sampleIcs),
      eventService: eventService,
    ));

    await tester.enterText(find.byType(TextField), _sampleIcs);
    await tester.tap(find.text('読み込む'));
    await tester.pumpAndSettle();

    // 2件目（記念日）のチェックを外す
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(find.textContaining('選択した1件を追加'), findsOneWidget);

    await tester.tap(find.textContaining('選択した1件を追加'));
    await tester.pumpAndSettle();

    final snap = await db.collection('couples').doc('couple-1').collection('events').get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.single.data()['title'], 'デート');
  });

  testWidgets('追加に失敗してもボタンが固まらず、追加済み分は一覧から外れて再試行できる', (tester) async {
    final db = FakeFirebaseFirestore();
    final eventService = _FailingEventService(firestore: db, uid: 'user-me', succeedTimes: 1);

    await tester.pumpWidget(wrap(
      loadIcsTextOverride: (_) => Future.value(_sampleIcs),
      eventService: eventService,
    ));
    await tester.enterText(find.byType(TextField), _sampleIcs);
    await tester.tap(find.text('読み込む'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('選択した2件を追加'));
    await tester.pumpAndSettle();

    expect(find.textContaining('予定の追加に失敗しました'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 1件目は追加済みなので一覧から外れ、2件目だけが残る（再試行で二重登録しない）。
    expect(find.text('デート'), findsNothing);
    expect(find.text('記念日'), findsOneWidget);
    expect(find.textContaining('選択した1件を追加'), findsOneWidget);

    final snap = await db.collection('couples').doc('couple-1').collection('events').get();
    expect(snap.docs, hasLength(1));

    // 復旧後に押し直せる
    eventService.succeedTimes = 1;
    await tester.tap(find.textContaining('選択した1件を追加'));
    await tester.pumpAndSettle();
    final after = await db.collection('couples').doc('couple-1').collection('events').get();
    expect(after.docs, hasLength(2));
  });
}
