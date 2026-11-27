import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'settings_service.dart';

// ── アプリ全体のテーマカラー（アクセント）を保持し、
//    設定画面での変更を即座に全画面へ反映するためのコントローラ。
class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  @visibleForTesting
  SettingsService settingsService = SettingsService();

  String _accentName = SettingsService.defaultAccentName;
  String get accentName => _accentName;
  Color get accent => AppColors.accentPresets[_accentName] ?? AppColors.lavender;

  Future<void> load() async {
    // main()から待たれるため、端末ストレージの読み出しが失敗しても例外にしない
    // （runAppに到達できず起動できなくなるため）。既定の色のまま起動する。
    try {
      _accentName = await settingsService.getAccentName();
    } catch (e) {
      debugPrint('テーマ色の読み込みに失敗しました: $e');
      _accentName = SettingsService.defaultAccentName;
    }
    notifyListeners();
  }

  Future<void> setAccentName(String name) async {
    if (!AppColors.accentPresets.containsKey(name)) return;
    _accentName = name;
    notifyListeners();
    await settingsService.setAccentName(name);
  }
}
