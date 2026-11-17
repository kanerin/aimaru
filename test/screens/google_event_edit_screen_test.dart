import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/google_event_edit_screen.dart';
import 'package:aimaru/services/google_calendar_cache_service.dart';
import 'package:aimaru/services/google_calendar_service.dart';

// Googleカレンダー側の更新が成功したあと、ふたりのカレンダー用キャッシュへの
// 反映だけが失敗しても、保存ボタンが回り続けたまま画面が閉じなくならないことを確かめる。
class _FakeCalendarService extends Fake implements GoogleCalendarService {
  _FakeCalendarService({this.fetchThrows = false});
  final bool fetchThrows;
  int updateCalls = 0;

  @override
  Future<GCalResult> updateGoogleEvent({
    required String eventId,
    required String title,
    DateTime? start,
    DateTime? end,
    bool allDay = false,
    String? location,
    String? memo,
  }) async {
    updateCalls++;
    return const GCalResult.success();
  }

  @override
  Future<GCalResult> deleteEvent(String googleEventId) async => const GCalResult.success();

  @override
  Future<List<GCalEventSummary>> fetchEvents({required DateTime start, required DateTime end}) async {
    if (fetchThrows) throw Exception('network');
    return [];
  }
}

class _FakeCacheService extends Fake implements GoogleCalendarCacheService {
  @override
  Future<void> setEventPrivate(String coupleId, String eventId, bool private) async {}

  @override
  Future<void> pushMyEvents(String coupleId, List<GCalEventSummary> events) async {}
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  final event = GCalEventSummary(
    id: 'g1',
    title: '映画',
    start: DateTime(2026, 11, 20, 19),
    end: DateTime(2026, 11, 20, 21),
    allDay: false,
  );

  Widget host(_FakeCalendarService cal, List<bool?> results) => MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  results.add(await Navigator.of(context).push<bool>(MaterialPageRoute(
                    builder: (_) => GoogleEventEditScreen(
                      coupleId: 'c1',
                      event: event,
                      calendarServiceOverride: cal,
                      cacheServiceOverride: _FakeCacheService(),
                    ),
                  )));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('保存: キャッシュ反映に失敗しても画面は閉じ、遅れる旨を案内する', (tester) async {
    final results = <bool?>[];
    await tester.pumpWidget(host(_FakeCalendarService(fetchThrows: true), results));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(results, [true]);
    expect(find.textContaining('反映は少し遅れる'), findsOneWidget);
  });

  testWidgets('保存: 全て成功したら案内なしで閉じる', (tester) async {
    final results = <bool?>[];
    await tester.pumpWidget(host(_FakeCalendarService(), results));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(results, [true]);
    expect(find.textContaining('反映は少し遅れる'), findsNothing);
  });
}
