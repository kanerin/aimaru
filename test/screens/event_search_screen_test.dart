import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/event_search_screen.dart';

// 予定検索画面がストリームエラーで無限ローディングのまま固まらないこと、
// キーワードでタイトル・メモ・場所を絞り込めることを確かめる。
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  Widget wrap(Stream<List<AimaruEvent>> stream) => MaterialApp(
        home: EventSearchScreen(coupleId: 'couple-1', eventsStreamOverride: stream),
      );

  AimaruEvent buildEvent({
    required String id,
    required String title,
    DateTime? date,
    String? memo,
    String? location,
  }) =>
      AimaruEvent(
        id: id,
        coupleId: 'couple-1',
        title: title,
        date: date ?? DateTime(2026, 8, 22, 19, 0),
        type: EventType.date,
        memo: memo,
        location: location,
        createdBy: 'u1',
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

  testWidgets('キーワード未入力時は検索を促す案内を出す', (tester) async {
    final controller = StreamController<List<AimaruEvent>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([buildEvent(id: 'e1', title: 'デート')]);
    await tester.pump();

    expect(find.textContaining('キーワードを入力'), findsOneWidget);
    expect(find.text('デート'), findsNothing);

    await controller.close();
  });

  testWidgets('タイトルに一致する予定だけを表示する', (tester) async {
    final controller = StreamController<List<AimaruEvent>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      buildEvent(id: 'e1', title: '温泉旅行'),
      buildEvent(id: 'e2', title: '歯医者'),
    ]);
    await tester.pump();

    await tester.enterText(find.byType(TextField), '温泉');
    await tester.pump();

    expect(find.text('温泉旅行'), findsOneWidget);
    expect(find.text('歯医者'), findsNothing);

    await controller.close();
  });

  testWidgets('メモ・場所も検索対象になる（大小文字を無視する）', (tester) async {
    final controller = StreamController<List<AimaruEvent>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([
      buildEvent(id: 'e1', title: '予定A', location: 'Cafe Sora'),
      buildEvent(id: 'e2', title: '予定B', memo: '誕生日プレゼントを渡す'),
      buildEvent(id: 'e3', title: '予定C'),
    ]);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'sora');
    await tester.pump();
    expect(find.text('予定A'), findsOneWidget);
    expect(find.text('予定B'), findsNothing);

    await tester.enterText(find.byType(TextField), 'プレゼント');
    await tester.pump();
    expect(find.text('予定B'), findsOneWidget);
    expect(find.text('予定A'), findsNothing);

    await controller.close();
  });

  testWidgets('該当が無い場合は見つからなかった旨を表示する', (tester) async {
    final controller = StreamController<List<AimaruEvent>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([buildEvent(id: 'e1', title: 'デート')]);
    await tester.pump();

    await tester.enterText(find.byType(TextField), '存在しないキーワード');
    await tester.pump();

    expect(find.text('見つかりませんでした'), findsOneWidget);

    await controller.close();
  });
}
