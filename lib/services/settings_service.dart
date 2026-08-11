import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_theme.dart';

// ── 端末ローカルの設定値（表示・Googleカレンダー関連）─────
class SettingsService {
  static const _keyShowGoogleCalendar = 'show_google_calendar';
  static const _keyDefaultSyncGoogleCalendar = 'default_sync_google_calendar';
  static const _keyAccentName = 'accent_color_name';
  static const _keyShowHolidays = 'show_holidays';
  static const _keyWeekStartsMonday = 'week_starts_monday';

  static const defaultAccentName = 'ラベンダー';

  Future<bool> getShowGoogleCalendar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowGoogleCalendar) ?? false;
  }

  Future<void> setShowGoogleCalendar(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowGoogleCalendar, value);
  }

  Future<bool> getDefaultSyncGoogleCalendar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDefaultSyncGoogleCalendar) ?? false;
  }

  Future<void> setDefaultSyncGoogleCalendar(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDefaultSyncGoogleCalendar, value);
  }

  // ── テーマカラー（AppColors.accentPresetsのキー） ──
  Future<String> getAccentName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyAccentName);
    return (name != null && AppColors.accentPresets.containsKey(name)) ? name : defaultAccentName;
  }

  Future<void> setAccentName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccentName, name);
  }

  // ── 祝日表示 ──
  Future<bool> getShowHolidays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowHolidays) ?? true;
  }

  Future<void> setShowHolidays(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowHolidays, value);
  }

  // ── 週の開始曜日（true: 月曜始まり / false: 日曜始まり） ──
  Future<bool> getWeekStartsMonday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyWeekStartsMonday) ?? false;
  }

  Future<void> setWeekStartsMonday(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWeekStartsMonday, value);
  }
}
