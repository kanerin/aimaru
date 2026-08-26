import 'package:shared_preferences/shared_preferences.dart';

// ── 端末ローカルのアプリロック（4桁PIN）設定 ──────────────
// スマホを相手に見せる・貸す場面でトーク・カレンダーを覗かれないための
// プライバシー機能。カップル間で共有するFirestoreデータではなく、
// 端末ごとのSharedPreferencesにのみPINを保持する。
class AppLockService {
  static const _keyEnabled = 'app_lock_enabled';
  static const _keyPin = 'app_lock_pin';

  static const pinLength = 4;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  // PINを保存し、ロックを有効化する。
  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPin, pin);
    await prefs.setBool(_keyEnabled, true);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPin) == pin;
  }

  // ロックを無効化し、保存済みのPINも消す（再度有効化するときは必ず新しいPINを設定させるため）。
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPin);
    await prefs.setBool(_keyEnabled, false);
  }
}
