import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/settings_screen.dart';
import 'package:aimaru/services/couple_service.dart';
import 'package:aimaru/services/notification_settings_service.dart';
import 'package:aimaru/services/settings_service.dart';
import 'package:aimaru/services/theme_controller.dart';
import 'package:aimaru/utils/app_theme.dart';

class _ThrowingCoupleService extends CoupleService {
  _ThrowingCoupleService() : super(firestore: FakeFirebaseFirestore(), uid: 'me');

  @override
  Future<CoupleModel?> getMyCouple() async => throw Exception('permission-denied');
}

class _ThrowingSettingsService extends SettingsService {
  bool shouldThrow = true;

  @override
  Future<bool> getShowGoogleCalendar() async {
    if (shouldThrow) throw Exception('read failed');
    return super.getShowGoogleCalendar();
  }
}

Widget _screen({CoupleService? couple, SettingsService? settings}) {
  final db = FakeFirebaseFirestore();
  return MaterialApp(
    home: SettingsScreen(
      coupleId: 'couple-1',
      coupleServiceOverride: couple ?? CoupleService(firestore: db, uid: 'me'),
      settingsServiceOverride: settings ?? SettingsService(),
      notificationSettingsServiceOverride: NotificationSettingsService(firestore: db, uid: 'me'),
      profileOverride: (displayName: 'わたし', email: 'me@example.com', photoUrl: null),
    ),
  );
}

// テーマ色ピッカーのアクセシビリティ（読み上げラベルとタップ領域）と、
// 設定画面の読み込み（ローディング・失敗・データ表示）を確かめる。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('読み込み', () {
    // ListViewは画面外を描画しないため、全セクションが見える縦長にする。
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(800, 6000);
      binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    });
    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });

    testWidgets('読み込み中はローディング、完了後は設定スイッチを表示する', (tester) async {
      await tester.pumpWidget(_screen());
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('祝日を表示'), findsOneWidget);
      expect(find.text('わたし'), findsOneWidget);
    });

    testWidgets('設定値の読み込みに失敗したら無限ローディングにせずエラーを出し、再読み込みで復帰できる',
        (tester) async {
      final settings = _ThrowingSettingsService();
      await tester.pumpWidget(_screen(settings: settings));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('設定を読み込めませんでした'), findsWidgets);

      settings.shouldThrow = false;
      await tester.tap(find.text('再読み込み').first);
      await tester.pumpAndSettle();

      expect(find.text('設定を読み込めませんでした'), findsNothing);
      expect(find.text('祝日を表示'), findsOneWidget);
    });

    testWidgets('パートナー情報の読み込みに失敗しても例外にならず、設定は使える', (tester) async {
      await tester.pumpWidget(_screen(couple: _ThrowingCoupleService()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('パートナー:'), findsNothing);
      expect(find.text('祝日を表示'), findsOneWidget);
    });
  });

  Widget wrap() => const MaterialApp(home: Scaffold(body: AccentColorPicker()));

  testWidgets('各テーマ色が色名付きのボタンとして読み上げられる', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap());

    for (final name in AppColors.accentPresets.keys) {
      expect(find.bySemanticsLabel('テーマ色 $name'), findsOneWidget);
    }
    handle.dispose();
  });

  testWidgets('タップ領域が48px以上あり、タップでテーマ色が切り替わる', (tester) async {
    await tester.pumpWidget(wrap());

    final size = tester.getSize(find.ancestor(
      of: find.text('ピンク'),
      matching: find.byType(ConstrainedBox),
    ).first);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    await tester.tap(find.text('ピンク'));
    await tester.pump();
    expect(ThemeController.instance.accentName, 'ピンク');
  });

  testWidgets('遷移行はタップに反応し、ボタンとして読み上げられる', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsNavigationRow(title: '共有アルバム', subtitle: '写真を置いておけます', onTap: () => taps++),
      ),
    ));

    expect(
      find.descendant(of: find.byType(SettingsNavigationRow), matching: find.byType(InkWell)),
      findsOneWidget,
    );
    final node = tester.getSemantics(find.byType(InkWell));
    expect(node.label, contains('共有アルバム'));
    expect(node.label, contains('写真を置いておけます'));
    expect(node.flagsCollection.isButton, isTrue);

    await tester.tap(find.text('共有アルバム'));
    await tester.pump();
    expect(taps, 1);
    handle.dispose();
  });
}
