import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/home_tab_requests.dart';
import 'package:aimaru/widgets/home_tab_request_listener.dart';

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
        child: Scaffold(
          body: Column(children: [
            Text('タブ: ${_tab.name}'),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('上の画面')),
                )),
                child: const Text('開く'),
              ),
            ),
          ]),
        ),
      );
}

void main() {
  late HomeTabRequests requests;

  setUp(() => requests = HomeTabRequests());
  tearDown(() => requests.dispose());

  testWidgets('表示される前に頼まれていたタブを最初に開く', (tester) async {
    requests.request(HomeTab.questions);

    await tester.pumpWidget(MaterialApp(home: _Home(requests)));
    await tester.pumpAndSettle();

    expect(find.text('タブ: questions'), findsOneWidget);
    expect(requests.take(), isNull);
  });

  testWidgets('何も頼まれていなければタブは変えない', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Home(requests)));
    await tester.pumpAndSettle();

    expect(find.text('タブ: calendar'), findsOneWidget);
  });

  testWidgets('表示中に頼まれたら、上に積んだ画面を閉じてタブを開く', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Home(requests)));
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(find.text('上の画面'), findsOneWidget);

    requests.request(HomeTab.questions);
    await tester.pumpAndSettle();

    expect(find.text('上の画面'), findsNothing);
    expect(find.text('タブ: questions'), findsOneWidget);
  });

  testWidgets('破棄した後に頼まれても例外にならず、次に表示したときに開く', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Home(requests)));
    await tester.pumpWidget(const MaterialApp(home: Text('ロック中')));

    requests.request(HomeTab.questions);
    await tester.pumpAndSettle();

    await tester.pumpWidget(MaterialApp(home: _Home(requests)));
    await tester.pumpAndSettle();
    expect(find.text('タブ: questions'), findsOneWidget);
  });
}
