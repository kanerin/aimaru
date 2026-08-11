import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'settings_service.dart';

// ── アプリ全体のテーマカラー（アクセント）を保持し、
//    設定画面での変更を即座に全画面へ反映するためのコントローラ。
class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  final _settingsService = SettingsService();

  String _accentName = SettingsService.defaultAccentName;
  String get accentName => _accentName;
  Color get accent => AppColors.accentPresets[_accentName] ?? AppColors.lavender;

  Future<void> load() async {
    _accentName = await _settingsService.getAccentName();
    notifyListeners();
  }

  Future<void> setAccentName(String name) async {
    if (!AppColors.accentPresets.containsKey(name)) return;
    _accentName = name;
    notifyListeners();
    await _settingsService.setAccentName(name);
  }
}
