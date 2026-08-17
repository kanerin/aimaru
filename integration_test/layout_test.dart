// 結合テスト: レイアウト崩れの自動検出。
//
// 「時刻ピッカーの数字が重なる」「FABがボタンに被る」「小さい端末で下がはみ出す」
// といった見た目の不具合は、これまで人間が実機で見るまで気づけなかった。
// Flutterははみ出しをFlutterErrorとして報告するので、それをテストで拾えば
// CIで自動的に検出できる。
//
// 端末サイズと文字サイズの組み合わせで検査するのがポイント。
// 端末が小さいほど、文字が大きいほど崩れやすい。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/calendar_screen.dart';
import 'package:aimaru/screens/event_form_screen.dart';
import 'package:aimaru/services/event_service.dart';

import 'helpers/e2e.dart';

// 検査する画面サイズ（論理ピクセル）
const _smallPhone = Size(360, 640); // 小さめのAndroid端末
const _tallPhone = Size(390, 844); // iPhone 14相当

// 端末の文字サイズ設定を大きくしている利用者は珍しくない
const _textScales = <double>[1.0, 1.3];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initE2E();
  });

  setUp(() async {
    await signInAndSeedCouple();
  });

  // サインアウトはファイル全体の最後に1回だけ行う。テストごとに行うと、
  // 画面が投げた非同期のFirestore取得がテスト終了後に着地したときに
  // 未認証となり、権限エラーが「完了済みのテストの失敗」として計上される。
  tearDownAll(() async {
    await signOutTestUser();
  });

  // ── カレンダー画面: 予定が詰まった日でも崩れないか ──
  for (final size in <Size>[_smallPhone, _tallPhone]) {
    for (final scale in _textScales) {
      final label = '${size.width.toInt()}x${size.height.toInt()}・文字$scale倍';

      testWidgets('カレンダー画面が崩れない ($label)', (tester) async {
        // 1日に複数件入れて、セルが最も詰まった状態を作る
        final today = DateTime.now();
        for (var i = 0; i < 4; i++) {
          await EventService().addEvent(
            testCoupleId,
            AimaruEvent(
              id: '',
              coupleId: testCoupleId,
              title: 'とても長いタイトルの予定その$i',
              date: DateTime(today.year, today.month, today.day, 10 + i),
              type: EventType.values[i % EventType.values.length],
              createdBy: '',
            ),
          );
        }

        await pumpScreen(
          tester,
          CalendarScreen(coupleId: testCoupleId),
          surfaceSize: size,
          textScale: scale,
        );
        await pumpUntil(
          tester,
          () => find.textContaining('とても長いタイトル').evaluate().isNotEmpty,
          reason: '予定がカレンダーに表示されない',
        );

        expectNoLayoutOverflow(tester, context: 'カレンダー画面 $label');
      });
    }
  }

  // ── 予定フォーム: 入力欄・チップ・スイッチが重ならないか ──
  for (final size in <Size>[_smallPhone, _tallPhone]) {
    for (final scale in _textScales) {
      final label = '${size.width.toInt()}x${size.height.toInt()}・文字$scale倍';

      testWidgets('予定フォームが崩れない ($label)', (tester) async {
        await pumpScreen(
          tester,
          EventFormScreen(coupleId: testCoupleId),
          surfaceSize: size,
          textScale: scale,
        );

        expect(find.text('新しい予定'), findsOneWidget);
        expectNoLayoutOverflow(tester, context: '予定フォーム $label');
      });
    }
  }

  // ── 時刻ピッカー: ダイヤル表示で数字と選択円が重なっていないか ──
  // 以前ここが読めなくなる不具合があり、入力式に逃がしてから
  // timePickerThemeで色を与えてダイヤルへ戻した経緯がある。
  testWidgets('時刻ピッカーを開いても表示が崩れない', (tester) async {
    await pumpScreen(
      tester,
      EventFormScreen(coupleId: testCoupleId),
      surfaceSize: _smallPhone,
      textScale: 1.3,
    );

    await tester.tap(find.byIcon(Icons.access_time).first);
    await settle(tester);

    expect(find.byType(Dialog), findsWidgets,
        reason: '時刻ピッカーが開いていない');
    expectNoLayoutOverflow(tester, context: '時刻ピッカー');
  });

  // ── FABが画面外へはみ出していないか ──
  testWidgets('FABが画面内に収まっている', (tester) async {
    await pumpScreen(
      tester,
      CalendarScreen(coupleId: testCoupleId),
      surfaceSize: _smallPhone,
    );

    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);

    final fabRect = tester.getRect(fab);
    final screenRect = tester.getRect(find.byType(CalendarScreen));
    expect(fabRect.bottom, lessThanOrEqualTo(screenRect.bottom),
        reason: 'FABが画面下端からはみ出している');
    expect(fabRect.right, lessThanOrEqualTo(screenRect.right),
        reason: 'FABが画面右端からはみ出している');

    expectNoLayoutOverflow(tester, context: 'FAB配置');
  });
}
