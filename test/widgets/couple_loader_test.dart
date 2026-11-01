import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aimaru/models/models.dart';
import 'package:aimaru/widgets/couple_loader.dart';

CoupleModel _couple() => CoupleModel(
      id: 'c1',
      memberIds: const ['a', 'b'],
      inviteCode: 'ABC123',
      createdAt: DateTime(2026, 1, 1),
    );

Widget _app({
  required Future<CoupleModel?> Function() load,
  VoidCallback? onNoCouple,
}) =>
    MaterialApp(
      home: CoupleLoader(
        loadOverride: load,
        onNoCouple: onNoCouple ?? () {},
        builder: (_, id) => Scaffold(body: Text('home:$id')),
      ),
    );

void main() {
  testWidgets('読み込み中はローディングを表示する', (tester) async {
    await tester.pumpWidget(_app(load: () => Future.delayed(
        const Duration(seconds: 1), () => _couple())));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('読み込めたらbuilderにcoupleIdを渡す', (tester) async {
    await tester.pumpWidget(_app(load: () async => _couple()));
    await tester.pump();
    expect(find.text('home:c1'), findsOneWidget);
  });

  testWidgets('ペアが無ければonNoCoupleを呼ぶ', (tester) async {
    var called = 0;
    await tester.pumpWidget(_app(load: () async => null, onNoCouple: () => called++));
    await tester.pump();
    expect(called, 1);
  });

  testWidgets('失敗したらエラーと再読み込みを出し、再読み込みで復帰できる', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(load: () async {
      calls++;
      if (calls == 1) throw Exception('permission-denied');
      return _couple();
    }));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗しました'), findsOneWidget);

    await tester.tap(find.text('再読み込み'));
    await tester.pump();
    await tester.pump();
    expect(find.text('home:c1'), findsOneWidget);
    expect(calls, 2);
  });
}
