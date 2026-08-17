import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/free_time_screen.dart';

// 2人の空き時間が、休みの日だけを対象に「一日空いてる日」と
// 「ちょっと会える日」に分かれて出ること、および読み込みが失敗しても
// 無限ローディングで固まらないことを確かめる。
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  // テストの実行日に左右されないよう、必ず先の土日を対象にする
  DateTime nextSaturday() {
    var d = DateTime.now().add(const Duration(days: 1));
    while (d.weekday != DateTime.saturday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day);
  }

  CoupleModel couple() => CoupleModel(
        id: 'couple-1',
        memberIds: const ['u1', 'u2'],
        inviteCode: 'TEST01',
        createdAt: DateTime(2026, 1, 1),
      );

  Widget wrap({
    required Stream<List<AimaruEvent>> events,
    required Stream<Map<String, List<GCalEventSummary>>> gcal,
  }) =>
      MaterialApp(
        home: FreeTimeScreen(
          coupleId: 'couple-1',
          eventsStreamOverride: events,
          gcalStreamOverride: gcal,
          coupleOverride: couple(),
        ),
      );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final events = StreamController<List<AimaruEvent>>();
    final gcal = StreamController<Map<String, List<GCalEventSummary>>>();

    await tester.pumpWidget(wrap(events: events.stream, gcal: gcal.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await events.close();
    await gcal.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする',
      (tester) async {
    final events = StreamController<List<AimaruEvent>>();
    final gcal = StreamController<Map<String, List<GCalEventSummary>>>();

    await tester.pumpWidget(wrap(events: events.stream, gcal: gcal.stream));

    events.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await events.close();
    await gcal.close();
  });

  testWidgets('予定が無い休日は「一日空いてる日」として出る', (tester) async {
    final events = StreamController<List<AimaruEvent>>();
    final gcal = StreamController<Map<String, List<GCalEventSummary>>>();

    await tester.pumpWidget(wrap(events: events.stream, gcal: gcal.stream));

    events.add(const []);
    gcal.add(const {});
    await tester.pump();

    expect(find.text('一日空いてる日'), findsOneWidget);
    expect(find.text('ちょっと会える日'), findsNothing);

    await events.close();
    await gcal.close();
  });

  testWidgets('予定の合間しか空いていない休日は「ちょっと会える日」として出る',
      (tester) async {
    final events = StreamController<List<AimaruEvent>>();
    final gcal = StreamController<Map<String, List<GCalEventSummary>>>();
    final saturday = nextSaturday();

    await tester.pumpWidget(wrap(events: events.stream, gcal: gcal.stream));

    // 土曜の9:00〜15:00を埋める（残り15:00〜22:00が空く）
    events.add([
      AimaruEvent(
        id: 'e1',
        coupleId: 'couple-1',
        title: '用事',
        date: DateTime(saturday.year, saturday.month, saturday.day, 9),
        endDate: DateTime(saturday.year, saturday.month, saturday.day, 15),
        type: EventType.plan,
        createdBy: 'u1',
      ),
    ]);
    gcal.add(const {});
    await tester.pump();

    // 「一日空いてる日」が先に並ぶので、ListViewの遅延構築を考慮して
    // 見出しが見えるところまでスクロールしてから確認する
    await tester.scrollUntilVisible(find.text('ちょっと会える日'), 300);
    expect(find.text('ちょっと会える日'), findsOneWidget);

    await events.close();
    await gcal.close();
  });

  testWidgets('Googleカレンダーの予定でも埋まっていれば候補から外れる', (tester) async {
    final events = StreamController<List<AimaruEvent>>();
    final gcal = StreamController<Map<String, List<GCalEventSummary>>>();
    final saturday = nextSaturday();

    await tester.pumpWidget(wrap(events: events.stream, gcal: gcal.stream));

    events.add(const []);
    // 直近の土曜を終日で埋める。日曜以降は空くので「一日空いてる日」は残るが、
    // その土曜の見出し日付は消えているはず。
    gcal.add({
      'u2': [
        GCalEventSummary(
          id: 'g1',
          title: '出張',
          start: saturday,
          end: saturday.add(const Duration(days: 1)),
          allDay: true,
        ),
      ],
    });
    await tester.pump();

    // 埋めた土曜は候補から消え、翌日の日曜が先頭に来ているはず。
    // 日曜が出ていることも確かめて、単に一覧が空なだけでないことを担保する。
    final sunday = saturday.add(const Duration(days: 1));
    expect(find.textContaining('${sunday.month}月${sunday.day}日'), findsOneWidget);
    expect(find.textContaining('${saturday.month}月${saturday.day}日'), findsNothing);

    await events.close();
    await gcal.close();
  });
}
