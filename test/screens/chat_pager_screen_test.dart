import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/screens/chat_pager_screen.dart';

// チャットタブで、カップルチャット（1枚目）とAIチャット（2枚目）を
// 左右スワイプで切り替えられること、切り替えても各ページの入力内容が
// 失われないこと、表示中のページだけがisActiveになることを確かめる。
void main() {
  // 各ページの代わりに、isActiveと入力欄を持つだけの軽いページを差し込む。
  Widget fakePage(String title, String hint) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: TextField(decoration: InputDecoration(hintText: hint)),
    );
  }

  Future<(List<bool>, List<bool>)> pumpPager(WidgetTester tester, {bool isActive = true}) async {
    final chatActive = <bool>[];
    final aiActive = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: ChatPagerScreen(
        coupleId: 'c1',
        isActive: isActive,
        chatPageOverride: (active) {
          chatActive.add(active);
          return fakePage('カップルチャット', 'メッセージを入力...');
        },
        aiChatPageOverride: (active) {
          aiActive.add(active);
          return fakePage('AIMARU AI', '予定を追加...');
        },
      ),
    ));
    await tester.pumpAndSettle();
    return (chatActive, aiActive);
  }

  Finder field(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint);

  testWidgets('最初はカップルチャットが表示され、左へスワイプするとAIチャットに切り替わる',
      (tester) async {
    final (chatActive, aiActive) = await pumpPager(tester);

    expect(find.text('カップルチャット'), findsOneWidget);
    expect(find.text('AIMARU AI'), findsNothing);
    expect(chatActive.last, isTrue);
    expect(aiActive.last, isFalse);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('AIMARU AI'), findsOneWidget);
    expect(aiActive.last, isTrue);
    expect(chatActive.last, isFalse,
        reason: 'AIチャット表示中にカップルチャットの既読を付けてはいけない');

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('カップルチャット'), findsOneWidget);
    expect(chatActive.last, isTrue);
    expect(aiActive.last, isFalse);
  });

  testWidgets('ページの目印をタップしても切り替えられる', (tester) async {
    await pumpPager(tester);

    await tester.tap(find.bySemanticsLabel('AIチャットに切り替え'));
    await tester.pumpAndSettle();
    expect(find.text('AIMARU AI'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('チャットに切り替え'));
    await tester.pumpAndSettle();
    expect(find.text('カップルチャット'), findsOneWidget);
  });

  testWidgets('スワイプで往復しても各ページの入力内容が保持される', (tester) async {
    await pumpPager(tester);

    await tester.enterText(field('メッセージを入力...'), 'チャットの下書き');
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    await tester.enterText(field('予定を追加...'), 'AIへの下書き');
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('チャットの下書き'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('AIへの下書き'), findsOneWidget,
        reason: 'スワイプで離れるとAIチャットの画面が破棄され、入力内容が消えている');
  });

  testWidgets('トークの通知から開くよう頼まれたら、AIチャット表示中でも2人のトークに戻る', (tester) async {
    Widget pager(int showChatRequest) => MaterialApp(
          home: ChatPagerScreen(
            coupleId: 'c1',
            isActive: true,
            showChatRequest: showChatRequest,
            chatPageOverride: (_) => fakePage('カップルチャット', 'メッセージを入力...'),
            aiChatPageOverride: (_) => fakePage('AIMARU AI', '予定を追加...'),
          ),
        );
    await tester.pumpWidget(pager(0));
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('AIMARU AI'), findsOneWidget);

    await tester.pumpWidget(pager(1));
    await tester.pumpAndSettle();

    expect(find.text('カップルチャット'), findsOneWidget);
    expect(find.text('AIMARU AI'), findsNothing);
  });

  testWidgets('頼まれた回数が変わらなければ、開いているページはそのまま', (tester) async {
    Widget pager(bool isActive) => MaterialApp(
          home: ChatPagerScreen(
            coupleId: 'c1',
            isActive: isActive,
            showChatRequest: 1,
            chatPageOverride: (_) => fakePage('カップルチャット', 'メッセージを入力...'),
            aiChatPageOverride: (_) => fakePage('AIMARU AI', '予定を追加...'),
          ),
        );
    await tester.pumpWidget(pager(true));
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    // 別のタブへ移って戻ってきた（isActiveだけが変わった）
    await tester.pumpWidget(pager(false));
    await tester.pumpWidget(pager(true));
    await tester.pumpAndSettle();

    expect(find.text('AIMARU AI'), findsOneWidget);
  });

  testWidgets('チャットタブ自体が非表示のときはどのページもisActiveにならない', (tester) async {
    final (chatActive, _) = await pumpPager(tester, isActive: false);
    expect(chatActive.last, isFalse);
  });
}
