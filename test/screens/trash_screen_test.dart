import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/trash_screen.dart';

// ゴミ箱画面がストリームエラーで無限ローディングのまま固まらないことを確かめる。
// test/screens/todos_screen_test.dart と同じパターン
// (StreamBuilderはhasDataだけでなくhasErrorも見る必要がある)。
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  Widget wrap(Stream<List<AimaruEvent>> stream) => MaterialApp(
        home: TrashScreen(coupleId: 'couple-1', eventsStreamOverride: stream),
      );

  AimaruEvent buildEvent({required String title, DateTime? deletedAt}) => AimaruEvent(
        id: title,
        coupleId: 'couple-1',
        title: title,
        date: DateTime(2026, 8, 20),
        type: EventType.date,
        createdBy: 'u1',
        deletedAt: deletedAt ?? DateTime(2026, 8, 15),
      );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<AimaruEvent>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<AimaruEvent>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが空ならゴミ箱が空である旨を表示', (tester) async {
    final controller = StreamController<List<AimaruEvent>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([]);
    await tester.pump();

    expect(find.textContaining('ゴミ箱は空です'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが来たら削除済みの予定を一覧表示する', (tester) async {
    final controller = StreamController<List<AimaruEvent>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([buildEvent(title: '削除された旅行')]);
    await tester.pump();

    expect(find.text('削除された旅行'), findsOneWidget);
    expect(find.byIcon(Icons.restore), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever), findsOneWidget);

    await controller.close();
  });

  Widget wrapWith({
    Future<void> Function(AimaruEvent)? restore,
    Future<void> Function(AimaruEvent)? permanentlyDelete,
  }) =>
      MaterialApp(
        home: TrashScreen(
          coupleId: 'couple-1',
          eventsStreamOverride: Stream.value([buildEvent(title: '削除された旅行')]),
          restoreOverride: restore,
          permanentlyDeleteOverride: permanentlyDelete,
        ),
      );

  testWidgets('元に戻すと完了を知らせる', (tester) async {
    AimaruEvent? restored;
    await tester.pumpWidget(wrapWith(restore: (e) async => restored = e));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.restore));
    await tester.pump();

    expect(restored?.title, '削除された旅行');
    expect(find.textContaining('元に戻しました'), findsOneWidget);
  });

  testWidgets('元に戻すのに失敗したらSnackBarで知らせる', (tester) async {
    await tester.pumpWidget(wrapWith(restore: (e) async => throw Exception('network')));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.restore));
    await tester.pump();

    expect(find.textContaining('元に戻せませんでした'), findsOneWidget);
  });

  testWidgets('完全削除に失敗したらSnackBarで知らせる', (tester) async {
    await tester.pumpWidget(
        wrapWith(permanentlyDelete: (e) async => throw Exception('PERMISSION_DENIED')));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_forever));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完全に削除する'));
    await tester.pump();

    expect(find.textContaining('削除できませんでした'), findsOneWidget);
  });

  testWidgets('完全削除の確認でキャンセルしたら削除しない', (tester) async {
    var called = false;
    await tester.pumpWidget(wrapWith(permanentlyDelete: (e) async => called = true));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_forever));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
  });
}
