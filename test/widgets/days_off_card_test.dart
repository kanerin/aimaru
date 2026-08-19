import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/services/couple_service.dart';
import 'package:aimaru/widgets/days_off_card.dart';

// 基本の休日の設定が保存され、失敗しても黙って握りつぶさないことを確かめる。
class _FakeCoupleService implements CoupleService {
  _FakeCoupleService({this.shouldFail = false});

  final bool shouldFail;
  List<int>? savedDaysOff;
  bool? savedHolidays;

  @override
  Future<void> setDaysOff(
    String coupleId, {
    required List<int> daysOff,
    required bool holidaysAreDaysOff,
  }) async {
    if (shouldFail) throw Exception('PERMISSION_DENIED');
    savedDaysOff = daysOff;
    savedHolidays = holidaysAreDaysOff;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget wrap(CoupleService service, {List<int>? initial}) => MaterialApp(
        home: Scaffold(
          body: DaysOffCard(
            coupleId: 'couple-1',
            initialDaysOff: initial ?? CoupleModel.defaultDaysOff,
            coupleServiceOverride: service,
          ),
        ),
      );

  // プルダウン（MenuAnchor）を開き、指定した曜日のCheckboxMenuButtonをタップする
  Future<void> tapDay(WidgetTester tester, String dayLabel) async {
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxMenuButton, '$dayLabel曜日'));
    await tester.pumpAndSettle();
  }

  testWidgets('既定では土日が選ばれている', (tester) async {
    await tester.pumpWidget(wrap(_FakeCoupleService()));

    // 閉じた状態のプルダウンには選択中の曜日だけがサマリーとして出る
    expect(find.text('土・日'), findsOneWidget);
  });

  testWidgets('曜日をタップすると休みとして保存される', (tester) async {
    final service = _FakeCoupleService();
    await tester.pumpWidget(wrap(service));

    // 平日休みの職種を想定して水曜を追加する
    await tapDay(tester, '水');

    expect(service.savedDaysOff, containsAll(<int>[
      DateTime.wednesday,
      DateTime.saturday,
      DateTime.sunday,
    ]));
    expect(service.savedHolidays, isTrue);
  });

  testWidgets('選択済みの曜日をタップすると休みから外れる', (tester) async {
    final service = _FakeCoupleService();
    await tester.pumpWidget(wrap(service));

    await tapDay(tester, '土');

    expect(service.savedDaysOff, isNot(contains(DateTime.saturday)));
    expect(service.savedDaysOff, contains(DateTime.sunday));
  });

  testWidgets('祝日の扱いを切り替えると保存される', (tester) async {
    final service = _FakeCoupleService();
    await tester.pumpWidget(wrap(service));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(service.savedHolidays, isFalse);
  });

  testWidgets('保存に失敗したら黙って進まずメッセージを出す', (tester) async {
    await tester.pumpWidget(wrap(_FakeCoupleService(shouldFail: true)));

    await tapDay(tester, '水');

    expect(find.text('休みの設定を保存できませんでした'), findsOneWidget);
    // 保存中インジケータが出たままにならないこと
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
