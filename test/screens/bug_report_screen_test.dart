import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/bug_report_screen.dart';
import 'package:aimaru/services/bug_report_service.dart';

void main() {
  // myReportsStreamOverrideを渡さないと、BugReportServiceがwatchMyReports()経由で
  // 実際のFirebaseへ触れてしまう（テストでは未初期化なので落ちる）。
  // 送信フォーム自体を検証するテストでは一覧の中身に興味が無いので、
  // 空のストリームを既定値として渡しておく。
  Widget wrap(
    BugReportService service, {
    Stream<List<BugReportRecord>>? myReportsStreamOverride,
  }) =>
      MaterialApp(
        home: BugReportScreen(
          serviceOverride: service,
          myReportsStreamOverride: myReportsStreamOverride ?? Stream.value(const []),
        ),
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

  BugReportService dummyService() => BugReportService(invoke: (data) async => {});

  testWidgets('自分の報告が無ければ案内文を表示する', (tester) async {
    await tester.pumpWidget(wrap(dummyService(), myReportsStreamOverride: Stream.value(const [])));
    await tester.pump();

    expect(find.text('まだ報告はありません'), findsOneWidget);
  });

  testWidgets('報告一覧を状況バッジ付きで表示する', (tester) async {
    final reports = [
      BugReportRecord(
        id: 'r1',
        summary: 'カレンダーが表示されない',
        classification: 'bug',
        status: 'in_progress',
        createdAt: DateTime(2026, 1, 1),
      ),
      BugReportRecord(
        id: 'r2',
        summary: 'ダークモードが欲しい',
        classification: 'feature_request',
        status: 'done',
        createdAt: DateTime(2026, 1, 2),
        prNumber: 42,
      ),
    ];
    await tester.pumpWidget(wrap(dummyService(), myReportsStreamOverride: Stream.value(reports)));
    await tester.pump();

    expect(find.text('カレンダーが表示されない'), findsOneWidget);
    expect(find.text('対応中'), findsOneWidget);
    expect(find.text('ダークモードが欲しい'), findsOneWidget);
    expect(find.text('対応済み'), findsOneWidget);
  });

  testWidgets('見送られた報告には大まかな理由を表示する', (tester) async {
    final reports = [
      BugReportRecord(
        id: 'r1',
        summary: '見送られた要望',
        classification: 'feature_request',
        status: 'rejected',
        rejectCategory: 'already_done',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
    await tester.pumpWidget(wrap(dummyService(), myReportsStreamOverride: Stream.value(reports)));
    await tester.pump();

    expect(find.text('見送り'), findsOneWidget);
    expect(find.text(describeBugReportRejectCategory('already_done')), findsOneWidget);
  });

  testWidgets('報告一覧の読み込みに失敗したら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<BugReportRecord>>();
    await tester.pumpWidget(wrap(dummyService(), myReportsStreamOverride: controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });
}
