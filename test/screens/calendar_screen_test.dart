import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/calendar_screen.dart';
import 'package:aimaru/services/couple_service.dart';

// カレンダー画面がストリームエラーで（無限ローディングではなく、予定が0件に
// 見える空のカレンダーで）固まらないことと、基本的な表示・遷移経路を確かめる。
// todos_screen_test.dart / trash_screen_test.dart と同じ再発防止パターン。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const coupleId = 'couple-1';
  const meUid = 'me';
  final today = DateTime(2026, 8, 20);

  late FakeFirebaseFirestore db;

  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
  });

  Widget wrap(
    Stream<Map<DateTime, List<AimaruEvent>>> stream, {
    NavigatorObserver? observer,
  }) =>
      MaterialApp(
        navigatorObservers: observer != null ? [observer] : [],
        home: CalendarScreen(
          coupleId: coupleId,
          eventsStreamOverride: stream,
          // getMyCoupleがnullを返す（couplesドキュメントを何も作らない）限り
          // _loadMembersはFirestoreの生のusers参照へ進まず早期return するため、
          // Firebase未初期化のテストでも安全に動く。
          coupleServiceOverride: CoupleService(firestore: db, uid: meUid),
          currentUidOverride: meUid,
          nowOverride: () => today,
        ),
      );

  AimaruEvent buildEvent({
    required String title,
    DateTime? date,
    String createdBy = meUid,
    EventVisibility visibility = EventVisibility.shared,
  }) =>
      AimaruEvent(
        id: title,
        coupleId: coupleId,
        title: title,
        date: date ?? today,
        type: EventType.plan,
        createdBy: createdBy,
        visibility: visibility,
      );

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが来たら全体表示のカレンダーに予定のタイトルが表示される', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add({today: [buildEvent(title: '水族館デート')]});
    await tester.pump();

    expect(find.textContaining('水族館デート'), findsOneWidget);
    expect(find.textContaining('読み込みに失敗'), findsNothing);

    await controller.close();
  });

  testWidgets('日付をタップすると選択表示に切り替わり予定一覧が出る', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add({today: [buildEvent(title: '水族館デート')]});
    await tester.pump();

    await tester.tap(find.text('${today.day}').first);
    await tester.pump();

    expect(find.textContaining('水族館デート'), findsOneWidget);
    expect(find.text('1件'), findsOneWidget);

    await controller.close();
  });

  testWidgets('privateな予定には鍵アイコンが付く', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add({
      today: [
        buildEvent(
          title: '自分だけの予定',
          createdBy: meUid,
          visibility: EventVisibility.private,
        ),
      ],
    });
    await tester.pump();

    await tester.tap(find.text('${today.day}').first);
    await tester.pump();

    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    await controller.close();
  });

  testWidgets('予定をタップすると詳細画面へ遷移する', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(wrap(controller.stream, observer: observer));

    controller.add({today: [buildEvent(title: '水族館デート')]});
    await tester.pump();

    await tester.tap(find.text('${today.day}').first);
    await tester.pump();
    // EventDetailScreen自体はFirebase初期化なしにはビルドできないため、
    // ここではpushされたこと自体だけを見る（todos_screen_test.dartと同じ設計）。
    await tester.tap(find.textContaining('水族館デート'));

    expect(observer.pushedCount, greaterThanOrEqualTo(1));

    await controller.close();
  });

  testWidgets('FABをタップすると予定作成画面へ遷移する', (tester) async {
    final controller = StreamController<Map<DateTime, List<AimaruEvent>>>();
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(wrap(controller.stream, observer: observer));

    controller.add({});
    await tester.pump();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(observer.pushedCount, 1);

    await controller.close();
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushedCount = 0;

  @override
  void didPush(Route route, Route? previousRoute) {
    // 最初のpushはCalendarScreen自体のホームルートなので数えない。
    if (previousRoute != null) pushedCount++;
  }
}
