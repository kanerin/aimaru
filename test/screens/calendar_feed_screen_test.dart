import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/screens/calendar_feed_screen.dart';
import 'package:aimaru/services/calendar_feed_service.dart';

// 外部カレンダー購読リンクの画面が、ローディング・エラー・データ表示の
// 3状態を正しく出し分けることを確かめる（CLAUDE.mdの「FutureBuilderは
// hasErrorを必ずハンドリングする」ルールに沿ったテスト）。
void main() {
  const sampleUrl = 'https://us-central1-aimaru-7eb2e.cloudfunctions.net/calendarFeed?uid=u1&token=abc';

  Widget wrap(CalendarFeedService service) => MaterialApp(
        home: CalendarFeedScreen(serviceOverride: service),
      );

  testWidgets('URLが来る前はローディング表示', (tester) async {
    final completer = Completer<String>();
    final service = _FakeCalendarFeedService(fetchUrl: () => completer.future);

    await tester.pumpWidget(wrap(service));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(sampleUrl);
    await tester.pumpAndSettle();
  });

  testWidgets('URL取得に失敗したら無限ローディングではなくエラー表示にする', (tester) async {
    final service = _FakeCalendarFeedService(
      fetchUrl: () async => throw Exception('unavailable'),
    );

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('リンクの取得に失敗しました'), findsOneWidget);
  });

  testWidgets('URLが取得できたら表示し、コピーボタンでスナックバーを出す', (tester) async {
    final messages = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        messages.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final service = _FakeCalendarFeedService(fetchUrl: () async => sampleUrl);

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    expect(find.text(sampleUrl), findsOneWidget);

    await tester.tap(find.text('リンクをコピー'));
    await tester.pump();
    await tester.pump();

    expect(messages.any((c) => c.method == 'Clipboard.setData'), isTrue);
    expect(find.text('リンクをコピーしました'), findsOneWidget);
  });

  testWidgets('作り直すと確認ダイアログを経て新しいURLに差し替わる', (tester) async {
    const newUrl = 'https://us-central1-aimaru-7eb2e.cloudfunctions.net/calendarFeed?uid=u1&token=new';
    final service = _FakeCalendarFeedService(
      fetchUrl: () async => sampleUrl,
      regenerateUrl: () async => newUrl,
    );

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('リンクを作り直す'));
    await tester.pumpAndSettle();

    // 確認ダイアログが出る
    expect(find.text('リンクを作り直しますか？'), findsOneWidget);

    await tester.tap(find.text('作り直す'));
    await tester.pumpAndSettle();

    expect(find.text(newUrl), findsOneWidget);
    expect(find.text(sampleUrl), findsNothing);
  });

  testWidgets('作り直しに失敗したらエラーを知らせ、元のURLのまま残す', (tester) async {
    final service = _FakeCalendarFeedService(
      fetchUrl: () async => sampleUrl,
      regenerateUrl: () async => throw Exception('unavailable'),
    );

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('リンクを作り直す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作り直す'));
    await tester.pumpAndSettle();

    expect(find.textContaining('作り直しに失敗しました'), findsOneWidget);
    expect(find.text(sampleUrl), findsOneWidget);
  });

  testWidgets('作り直しをキャンセルすると元のURLのまま残る', (tester) async {
    final service = _FakeCalendarFeedService(
      fetchUrl: () async => sampleUrl,
      regenerateUrl: () async => throw StateError('呼ばれないはず'),
    );

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('リンクを作り直す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(find.text(sampleUrl), findsOneWidget);
  });
}

class _FakeCalendarFeedService extends CalendarFeedService {
  final Future<String> Function() _fetchUrl;
  final Future<String> Function()? _regenerateUrl;

  _FakeCalendarFeedService({
    required Future<String> Function() fetchUrl,
    Future<String> Function()? regenerateUrl,
  })  : _fetchUrl = fetchUrl,
        _regenerateUrl = regenerateUrl;

  @override
  Future<String> fetchUrl() => _fetchUrl();

  @override
  Future<String> regenerateUrl() =>
      _regenerateUrl?.call() ?? Future.error(StateError('regenerateUrl not stubbed'));
}
