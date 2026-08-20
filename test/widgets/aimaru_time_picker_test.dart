import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/utils/app_theme.dart';
import 'package:aimaru/widgets/aimaru_time_picker.dart';
import 'package:aimaru/widgets/time_dial.dart';

// 自前の時刻ピッカー。
//
// Flutter標準のshowTimePickerは選択円が48dp固定でテーマから変えられず、
// 円が数字より大きく隣の目盛りに被って読みにくかったため置き換えた。
// 標準ピッカーと同じ呼び出し口（TimeOfDayを返す／キャンセルでnull）を
// 保っていること、ダイヤルの操作で値が変わることを確かめる。
void main() {
  Widget host(void Function(TimeOfDay?) onResult, TimeOfDay initial) =>
      MaterialApp(
        theme: AppTheme.light(AppColors.lavender),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  onResult(await showAimaruTimePicker(
                    context: context,
                    initialTime: initial,
                  ));
                },
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
  }

  testWidgets('初期値が時・分の欄に表示される', (tester) async {
    await tester.pumpWidget(host((_) {}, const TimeOfDay(hour: 9, minute: 5)));
    await open(tester);

    expect(find.text('時刻を選択'), findsOneWidget);
    // 時・分の欄はゼロ埋めして桁を揃える
    expect(find.text('09'), findsOneWidget);
    expect(find.text('05'), findsOneWidget);
  });

  testWidgets('OKで選んだ時刻が返る', (tester) async {
    TimeOfDay? result;
    await tester.pumpWidget(
        host((v) => result = v, const TimeOfDay(hour: 9, minute: 5)));
    await open(tester);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result, const TimeOfDay(hour: 9, minute: 5));
  });

  testWidgets('キャンセルするとnullが返り、値は捨てられる', (tester) async {
    TimeOfDay? result = const TimeOfDay(hour: 0, minute: 0);
    await tester.pumpWidget(
        host((v) => result = v, const TimeOfDay(hour: 9, minute: 5)));
    await open(tester);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('ダイヤルの真上をタップすると0時になり、続けて分の選択へ進む', (tester) async {
    TimeOfDay? result;
    await tester.pumpWidget(
        host((v) => result = v, const TimeOfDay(hour: 9, minute: 30)));
    await open(tester);

    // 最初は「時」を選んでいる
    expect(tester.widget<TimeDial>(find.byType(TimeDial)).mode,
        TimeDialMode.hour);

    final dial = tester.getRect(find.byType(TimeDial));
    // 外側リングの真上 = 0時
    await tester.tapAt(Offset(dial.center.dx, dial.top + 12));
    await tester.pumpAndSettle();

    expect(find.text('00'), findsOneWidget, reason: '時の欄が00になる');
    // 時を決めたら分へ進む
    expect(tester.widget<TimeDial>(find.byType(TimeDial)).mode,
        TimeDialMode.minute);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result!.hour, 0);
    expect(result!.minute, 30, reason: '分は触っていないので初期値のまま');
  });

  testWidgets('内側リングをタップすると12〜23時が選べる', (tester) async {
    TimeOfDay? result;
    await tester.pumpWidget(
        host((v) => result = v, const TimeOfDay(hour: 9, minute: 0)));
    await open(tester);

    final dial = tester.getRect(find.byType(TimeDial));
    // 内側リングの真上 = 12時（外側より中心寄りを突く）
    await tester.tapAt(Offset(dial.center.dx, dial.top + 62));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result!.hour, 12);
  });

  testWidgets('時の欄をタップすると時の選択へ戻れる', (tester) async {
    await tester.pumpWidget(
        host((_) {}, const TimeOfDay(hour: 9, minute: 0)));
    await open(tester);

    final dial = tester.getRect(find.byType(TimeDial));
    await tester.tapAt(Offset(dial.center.dx, dial.top + 12));
    await tester.pumpAndSettle();
    expect(tester.widget<TimeDial>(find.byType(TimeDial)).mode,
        TimeDialMode.minute);

    // 時の欄（00）をタップして選び直す
    await tester.tap(find.text('00'));
    await tester.pumpAndSettle();

    expect(tester.widget<TimeDial>(find.byType(TimeDial)).mode,
        TimeDialMode.hour);
  });

  testWidgets('選択円は標準の48dpより小さい', (tester) async {
    await tester.pumpWidget(
        host((_) {}, const TimeOfDay(hour: 9, minute: 0)));
    await open(tester);

    // 置き換えた目的そのものなので、定数が戻されたら落ちるようにしておく。
    expect(kTimeDialSelectorRadius * 2, lessThan(48));
  });
}
