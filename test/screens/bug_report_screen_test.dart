import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/screens/bug_report_screen.dart';
import 'package:aimaru/services/bug_report_service.dart';

void main() {
  Widget wrap(BugReportService service) => MaterialApp(
        home: BugReportScreen(serviceOverride: service),
      );

  testWidgets('受理されたらフィールドをクリアしメッセージを表示する', (tester) async {
    final service = BugReportService(invoke: (data) async {
      return {'accepted': true, 'classification': 'bug', 'summary': '要約'};
    });
    await tester.pumpWidget(wrap(service));

    await tester.enterText(find.byType(TextField), 'カレンダーが表示されないバグがあります');
    await tester.tap(find.widgetWithText(FilledButton, '送信する'));
    await tester.pumpAndSettle();

    expect(find.textContaining('バグ報告として受け付けました'), findsOneWidget);
    expect(find.text('カレンダーが表示されないバグがあります'), findsNothing);
  });

  testWidgets('feature_requestとして受理された場合は機能要望と表示する', (tester) async {
    final service = BugReportService(invoke: (data) async {
      return {'accepted': true, 'classification': 'feature_request', 'summary': '要約'};
    });
    await tester.pumpWidget(wrap(service));

    await tester.enterText(find.byType(TextField), 'ダークモードを追加してほしいです');
    await tester.tap(find.widgetWithText(FilledButton, '送信する'));
    await tester.pumpAndSettle();

    expect(find.textContaining('機能要望として受け付けました'), findsOneWidget);
  });

  testWidgets('拒否された場合はエラーではなく判定結果のメッセージを表示する', (tester) async {
    final service = BugReportService(invoke: (data) async {
      return {'accepted': false, 'classification': 'invalid', 'summary': ''};
    });
    await tester.pumpWidget(wrap(service));

    await tester.enterText(find.byType(TextField), 'アプリと無関係な内容を送ってみます');
    await tester.tap(find.widgetWithText(FilledButton, '送信する'));
    await tester.pumpAndSettle();

    expect(find.textContaining('判定できませんでした'), findsOneWidget);
  });

  testWidgets('短すぎる入力はサーバーへ送らずにエラーメッセージを表示する', (tester) async {
    var called = false;
    final service = BugReportService(invoke: (data) async {
      called = true;
      return {'accepted': true, 'classification': 'bug', 'summary': ''};
    });
    await tester.pumpWidget(wrap(service));

    await tester.enterText(find.byType(TextField), 'あ');
    await tester.tap(find.widgetWithText(FilledButton, '送信する'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.textContaining(kBugReportEmptyMessage), findsOneWidget);
  });

  testWidgets('送信中はボタンが無効化され、進捗表示になる', (tester) async {
    final service = BugReportService(invoke: (data) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return {'accepted': true, 'classification': 'bug', 'summary': ''};
    });
    await tester.pumpWidget(wrap(service));

    await tester.enterText(find.byType(TextField), 'カレンダーが表示されないバグがあります');
    await tester.tap(find.widgetWithText(FilledButton, '送信する'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.pumpAndSettle();
  });

  testWidgets('送信失敗時はエラーメッセージを表示する', (tester) async {
    final service = BugReportService(invoke: (data) async {
      throw Exception('通信エラー');
    });
    await tester.pumpWidget(wrap(service));

    await tester.enterText(find.byType(TextField), 'カレンダーが表示されないバグがあります');
    await tester.tap(find.widgetWithText(FilledButton, '送信する'));
    await tester.pumpAndSettle();

    expect(find.text(kBugReportUnknownMessage), findsOneWidget);
  });
}
