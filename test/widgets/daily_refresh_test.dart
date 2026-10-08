import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/widgets/daily_refresh.dart';

// ホームのタブに置いた「ふたりの質問」が、日付をまたいでも前日の質問のまま
// 残らないこと（アプリ復帰時・0時に子が作り直されること）を確かめる。
void main() {
  // 作り直されたかどうかを、Stateが新しく作られた回数で見る。
  late int created;
  late DateTime now;

  Widget build() => MaterialApp(
        home: DailyRefresh(
          clock: () => now,
          builder: (_) => _CountsCreation(onCreate: () => created++),
        ),
      );

  setUp(() {
    created = 0;
  });

  testWidgets('アプリ復帰時に日付が変わっていれば作り直す', (tester) async {
    now = DateTime(2026, 10, 6, 22);
    await tester.pumpWidget(build());
    expect(created, 1);

    now = DateTime(2026, 10, 7, 8);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(created, 2, reason: '日付をまたいで復帰しても前日の画面のまま残っている');
  });

  testWidgets('同じ日のうちに復帰しただけなら作り直さない（入力途中の回答を消さない）',
      (tester) async {
    now = DateTime(2026, 10, 6, 9);
    await tester.pumpWidget(build());

    now = DateTime(2026, 10, 6, 21);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(created, 1);
  });

  testWidgets('アプリを開いたまま0時を過ぎたら作り直す', (tester) async {
    now = DateTime(2026, 10, 6, 23, 59);
    await tester.pumpWidget(build());
    expect(created, 1);

    now = DateTime(2026, 10, 7, 0, 0, 2);
    await tester.pump(const Duration(minutes: 1, seconds: 2));

    expect(created, 2, reason: '0時を過ぎても前日の画面のまま残っている');
  });
}

class _CountsCreation extends StatefulWidget {
  final VoidCallback onCreate;
  const _CountsCreation({required this.onCreate});

  @override
  State<_CountsCreation> createState() => _CountsCreationState();
}

class _CountsCreationState extends State<_CountsCreation> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
