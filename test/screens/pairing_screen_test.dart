import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/pairing_screen.dart';

// ペアリング画面: 招待コードの取得（読み込み/失敗/表示）と、コード入力での参加。
// Firebaseには触れず、画面に差し込んだ経路だけで状態を作る。
void main() {
  CoupleModel couple(int members) => CoupleModel(
        id: 'c1',
        memberIds: List.generate(members, (i) => 'u$i'),
        inviteCode: 'ABC123',
        createdAt: DateTime(2026, 10, 1),
      );

  Widget wrap({
    Future<String> Function()? create,
    Future<CoupleModel?> Function(String)? join,
    Stream<CoupleModel?>? stream,
  }) {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => PairingScreen(
          createInviteCodeOverride: create ?? () async => 'ABC123',
          joinWithCodeOverride: join ?? (_) async => null,
          coupleStreamOverride: stream ?? const Stream<CoupleModel?>.empty(),
        ),
      ),
      GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('HOME'))),
    ]);
    return MaterialApp.router(routerConfig: router);
  }

  Future<void> openJoinTab(WidgetTester tester) async {
    await tester.tap(find.text('参加する'));
    await tester.pumpAndSettle();
  }

  testWidgets('コード取得中はローディング表示でコピーできない', (tester) async {
    final completer = Completer<String>();
    await tester.pumpWidget(wrap(create: () => completer.future));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    final copy = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'コード'));
    expect(copy.onPressed, isNull);

    completer.complete('ABC123');
    await tester.pump();
  });

  testWidgets('コードが取得できたら間隔を空けて表示する', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('A B C 1 2 3'), findsOneWidget);
  });

  testWidgets('コード取得に失敗したら例外文字列を出さず再試行できる', (tester) async {
    var calls = 0;
    await tester.pumpWidget(wrap(create: () async {
      calls++;
      if (calls == 1) throw Exception('PERMISSION_DENIED secret-detail');
      return 'XYZ789';
    }));
    await tester.pump();

    expect(find.textContaining('招待コードを取得できませんでした'), findsOneWidget);
    expect(find.textContaining('PERMISSION_DENIED'), findsNothing);

    await tester.tap(find.text('再試行'));
    await tester.pump();

    expect(find.text('X Y Z 7 8 9'), findsOneWidget);
  });

  testWidgets('ペア状態の監視ストリームがエラーでも例外にならない', (tester) async {
    final controller = StreamController<CoupleModel?>();
    await tester.pumpWidget(wrap(stream: controller.stream));
    await tester.pump();

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // リスナーがいるストリームのclose()はFakeAsync下ではawaitすると終わらない
    unawaited(controller.close());
  });

  testWidgets('相手が参加してペアが成立したらホームへ遷移する', (tester) async {
    final controller = StreamController<CoupleModel?>();
    await tester.pumpWidget(wrap(stream: controller.stream));
    await tester.pump();

    controller.add(couple(1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('HOME'), findsNothing);

    controller.add(couple(2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('HOME'), findsOneWidget);
    unawaited(controller.close());
  });

  testWidgets('6文字未満のコードは通信せずに案内する', (tester) async {
    var joined = false;
    await tester.pumpWidget(wrap(join: (_) async {
      joined = true;
      return null;
    }));
    await tester.pump();
    await openJoinTab(tester);

    await tester.enterText(find.byType(TextField), 'AB1');
    await tester.tap(find.text('つながる'));
    await tester.pump();

    expect(find.text('6文字のコードを入力してください'), findsOneWidget);
    expect(joined, isFalse);
  });

  testWidgets('存在しないコードは見つからない旨を表示する', (tester) async {
    await tester.pumpWidget(wrap(join: (_) async => null));
    await tester.pump();
    await openJoinTab(tester);

    await tester.enterText(find.byType(TextField), 'ZZZZZZ');
    await tester.tap(find.text('つながる'));
    await tester.pumpAndSettle();

    expect(find.textContaining('コードが見つかりません'), findsOneWidget);
  });

  testWidgets('通信エラーは握って案内し、例外にしない', (tester) async {
    await tester.pumpWidget(wrap(join: (_) async => throw Exception('network')));
    await tester.pump();
    await openJoinTab(tester);

    await tester.enterText(find.byType(TextField), 'ABC123');
    await tester.tap(find.text('つながる'));
    await tester.pumpAndSettle();

    expect(find.textContaining('通信エラーが発生しました'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('キーボードの完了キーでも参加でき、成功したらホームへ遷移する', (tester) async {
    String? joinedCode;
    await tester.pumpWidget(wrap(join: (code) async {
      joinedCode = code;
      return couple(2);
    }));
    await tester.pump();
    await openJoinTab(tester);

    await tester.enterText(find.byType(TextField), 'ABC123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(joinedCode, 'ABC123');
    expect(find.text('HOME'), findsOneWidget);
  });
}
