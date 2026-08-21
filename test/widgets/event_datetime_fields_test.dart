import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/utils/app_theme.dart';
import 'package:aimaru/widgets/event_datetime_fields.dart';

// 予定の日時入力の操作性（TV-036）。
//
// 終了が開始より前になる状態は、Googleへ送ると拒否されるか期間が壊れるため、
// 入力の時点で通さないことを確かめる。終日の切替で不要な入力欄が消えることも
// あわせて見る（時刻に意味が無いのに時刻欄が残っていると迷う）。
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  final start = DateTime(2026, 8, 14, 19, 0);

  group('clampEnd - 終了は開始より前にならない', () {
    test('開始より前の時刻を指定すると開始の1時間後へ寄る', () {
      final result = clampEnd(
        start: start,
        end: DateTime(2026, 8, 14, 18, 0),
        allDay: false,
      );

      expect(result, DateTime(2026, 8, 14, 20, 0));
    });

    test('開始より前の日付を指定しても開始より前にならない', () {
      final result = clampEnd(
        start: start,
        end: DateTime(2026, 8, 13, 23, 0),
        allDay: false,
      );

      expect(result, DateTime(2026, 8, 14, 20, 0));
    });

    test('開始と同時刻も前扱いにして寄せる', () {
      final result = clampEnd(start: start, end: start, allDay: false);

      expect(result, DateTime(2026, 8, 14, 20, 0));
    });

    test('開始より後ならそのまま通す（日をまたいでよい）', () {
      final end = DateTime(2026, 8, 15, 2, 0);

      expect(clampEnd(start: start, end: end, allDay: false), end);
    });

    test('終日は同じ日で終わってよい（1日だけの予定）', () {
      final result = clampEnd(
        start: start,
        end: DateTime(2026, 8, 14, 3, 0),
        allDay: true,
      );

      expect(result, DateTime(2026, 8, 14));
    });

    test('終日で開始より前の日を指定すると開始日へ寄る', () {
      final result = clampEnd(
        start: start,
        end: DateTime(2026, 8, 12),
        allDay: true,
      );

      expect(result, DateTime(2026, 8, 14));
    });
  });

  group('followStart - 開始を動かすと終了も追従する', () {
    test('長さを保ったまま終了がずれる', () {
      final result = followStart(
        oldStart: start,
        oldEnd: DateTime(2026, 8, 14, 21, 30),
        newStart: DateTime(2026, 8, 20, 9, 0),
      );

      expect(result, DateTime(2026, 8, 20, 11, 30));
    });

    test('日をまたぐ長さも保たれる', () {
      final result = followStart(
        oldStart: DateTime(2026, 8, 14, 22, 0),
        oldEnd: DateTime(2026, 8, 15, 2, 0),
        newStart: DateTime(2026, 8, 20, 22, 0),
      );

      expect(result, DateTime(2026, 8, 21, 2, 0));
    });

    test('元の長さが負なら1時間に正す', () {
      final result = followStart(
        oldStart: start,
        oldEnd: DateTime(2026, 8, 14, 18, 0),
        newStart: DateTime(2026, 8, 20, 9, 0),
      );

      expect(result, DateTime(2026, 8, 20, 10, 0));
    });
  });

  group('終日の切り替え', () {
    // 終日の予定は「開始日＝最終日」なので、開始も終了も同じ日の0:00になる。
    // その状態のまま時刻指定へ戻すと end == start になり、Googleは
    // 時刻指定の予定に end > start を求めるため保存できない。
    testWidgets('終日を解除すると終了が開始より後へ開く', (tester) async {
      final sameDay = DateTime(2026, 8, 14);
      DateTime? newEnd;
      bool? newAllDay;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(AppColors.lavender),
        home: Scaffold(
          body: EventDateTimeFields(
            start: sameDay,
            end: sameDay,
            allDay: true,
            onStartChanged: (_) {},
            onEndChanged: (v) => newEnd = v,
            onAllDayChanged: (v) => newAllDay = v,
          ),
        ),
      ));

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(newAllDay, isFalse);
      expect(newEnd, isNotNull);
      expect(newEnd!.isAfter(sameDay), isTrue);
    });

    // 終日ONにした直後、開始・終了の時刻を持ち越さず0:00へ揃える。
    // 時刻ボタンはallDay中は隠れて気づきにくいが、ここを揃えておかないと
    // 保存されるAimaruEvent.date/endDateに元の時刻が残ったままになり、
    // 一覧・詳細画面で終日のはずの予定に元の時刻が表示されてしまう
    // （実際に「終日にした予定が一覧で9:00と表示される」不具合として報告された）。
    testWidgets('終日にすると開始・終了の時刻が0:00に揃う', (tester) async {
      DateTime? newStart;
      DateTime? newEnd;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(AppColors.lavender),
        home: Scaffold(
          body: EventDateTimeFields(
            start: DateTime(2026, 8, 14, 19, 0),
            end: DateTime(2026, 8, 14, 20, 0),
            allDay: false,
            onStartChanged: (v) => newStart = v,
            onEndChanged: (v) => newEnd = v,
            onAllDayChanged: (_) {},
          ),
        ),
      ));

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(newStart, DateTime(2026, 8, 14));
      expect(newEnd, DateTime(2026, 8, 14));
    });
  });

  group('表示', () {
    Widget wrap({required bool allDay, bool withAllDayToggle = true}) => MaterialApp(
      theme: AppTheme.light(AppColors.lavender),
      home: Scaffold(
        body: EventDateTimeFields(
          start: start,
          end: DateTime(2026, 8, 15, 2, 0),
          allDay: allDay,
          onStartChanged: (_) {},
          onEndChanged: (_) {},
          onAllDayChanged: withAllDayToggle ? (_) {} : null,
        ),
      ),
    );

    testWidgets('時刻指定なら開始・終了それぞれに日付と時刻のボタンが出る', (tester) async {
      await tester.pumpWidget(wrap(allDay: false));

      expect(find.byIcon(Icons.calendar_today), findsNWidgets(2));
      expect(find.byIcon(Icons.access_time), findsNWidgets(2));
      expect(find.text('開始'), findsOneWidget);
      expect(find.text('終了'), findsOneWidget);
    });

    testWidgets('終日なら時刻のボタンが消え、日付だけになる', (tester) async {
      await tester.pumpWidget(wrap(allDay: true));

      expect(find.byIcon(Icons.calendar_today), findsNWidgets(2));
      expect(find.byIcon(Icons.access_time), findsNothing);
    });

    testWidgets('終日の切替を渡さなければトグルを出さない', (tester) async {
      await tester.pumpWidget(wrap(allDay: false, withAllDayToggle: false));

      expect(find.text('終日'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('終了にも日付が表示され、開始と別の日を指せる', (tester) async {
      await tester.pumpWidget(wrap(allDay: false));

      expect(find.text('8月14日（金）'), findsOneWidget);
      expect(find.text('8月15日（土）'), findsOneWidget);
    });
  });
}
