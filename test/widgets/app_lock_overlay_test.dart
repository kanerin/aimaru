import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/home_tab_requests.dart';
import 'package:aimaru/widgets/app_lock_overlay.dart';
import 'package:aimaru/widgets/home_tab_request_listener.dart';

// ホーム（_HomeContent）の代わり。タブの依頼を受けて表示を切り替える。
class _Home extends StatefulWidget {
  final HomeTabRequests requests;
  const _Home(this.requests);

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  HomeTab _tab = HomeTab.calendar;

  @override
  Widget build(BuildContext context) => HomeTabRequestListener(
        requests: widget.requests,
        onTab: (tab) => setState(() => _tab = tab),
        child: Scaffold(body: Text('タブ: ${_tab.name}')),
      );
}

void main() {
  late HomeTabRequests requests;

  setUp(() => requests = HomeTabRequests());
  tearDown(() => requests.dispose());

  Widget app({required bool locked}) => MaterialApp(
        home: AppLockOverlay(
          locked: locked,
          lockScreen: const Scaffold(body: Text('ロック中')),
          child: _Home(requests),
        ),
      );

  testWidgets('ロック中はロック画面だけを見せ、下の画面は見せない', (tester) async {
    await tester.pumpWidget(app(locked: true));

    expect(find.text('ロック中'), findsOneWidget);
    expect(find.text('タブ: calendar'), findsNothing);
  });

  // 通知をタップしてアプリへ戻ると、タブの依頼はロック画面が描かれる前の
  // ホームが受け取る。以前はロックで下の画面を破棄していたため、解除後に
  // 作り直されたホームはカレンダーのままで、トークの通知からトークへ飛べなかった。
  testWidgets('ロック中に受けた通知のタブ切り替えが、解除後も残っている', (tester) async {
    await tester.pumpWidget(app(locked: false));
    expect(find.text('タブ: calendar'), findsOneWidget);

    // バックグラウンドから通知タップで復帰：依頼が先に届き、その後ロック画面になる
    requests.request(HomeTab.chat);
    await tester.pumpWidget(app(locked: true));
    await tester.pumpAndSettle();
    expect(find.text('ロック中'), findsOneWidget);

    await tester.pumpWidget(app(locked: false));
    await tester.pumpAndSettle();

    expect(find.text('ロック中'), findsNothing);
    expect(find.text('タブ: chat'), findsOneWidget);
  });

  testWidgets('ロックしてから受けた依頼も、解除後に反映される', (tester) async {
    await tester.pumpWidget(app(locked: false));
    await tester.pumpWidget(app(locked: true));

    requests.request(HomeTab.questions);
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(locked: false));
    await tester.pumpAndSettle();

    expect(find.text('タブ: questions'), findsOneWidget);
  });
}
