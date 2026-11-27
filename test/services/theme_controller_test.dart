import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aimaru/services/theme_controller.dart';
import 'package:aimaru/services/settings_service.dart';
import 'package:aimaru/utils/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('デフォルトはラベンダー', () async {
    final controller = ThemeController.instance;
    await controller.load();
    expect(controller.accentName, SettingsService.defaultAccentName);
    expect(controller.accent, AppColors.accentPresets[SettingsService.defaultAccentName]);
  });

  test('setAccentNameで色が変わり、リスナーに通知される', () async {
    final controller = ThemeController.instance;
    await controller.load();

    var notified = false;
    controller.addListener(() => notified = true);

    await controller.setAccentName('ミント');

    expect(notified, isTrue);
    expect(controller.accentName, 'ミント');
    expect(controller.accent, AppColors.accentPresets['ミント']);
  });

  test('保存した値が次回loadで復元される', () async {
    await ThemeController.instance.setAccentName('スカイ');

    // 同じSharedPreferencesバックエンドから新しいインスタンス相当で再読込
    final settings = SettingsService();
    final savedName = await settings.getAccentName();
    expect(savedName, 'スカイ');
  });

  test('存在しないアクセント名は無視される', () async {
    final controller = ThemeController.instance;
    await controller.load();
    final before = controller.accentName;

    await controller.setAccentName('存在しない色');

    expect(controller.accentName, before);
  });

  test('設定の読み出しが失敗しても例外にせず既定の色で起動できる', () async {
    final controller = ThemeController.instance;
    final original = controller.settingsService;
    addTearDown(() => controller.settingsService = original);
    controller.settingsService = _ThrowingSettingsService();

    await controller.load();

    expect(controller.accentName, SettingsService.defaultAccentName);
  });
}

class _ThrowingSettingsService extends SettingsService {
  @override
  Future<String> getAccentName() async => throw Exception('prefs unavailable');
}
