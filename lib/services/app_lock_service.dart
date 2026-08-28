import 'package:shared_preferences/shared_preferences.dart';

// ── 端末ローカルのアプリロック（4桁PIN）設定 ──────────────
// スマホを相手に見せる・貸す場面でトーク・カレンダーを覗かれないための
// プライバシー機能。カップル間で共有するFirestoreデータではなく、
// 端末ごとのSharedPreferencesにのみPINを保持する。
class AppLockService {
  static const _keyEnabled = 'app_lock_enabled';
  static const _keyPin = 'app_lock_pin';
  static const _keyBiometric = 'app_lock_biometric';

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

  // ── 生体認証（指紋・顔）での解除を使うかどうか ──────────────
  // PINの代わりではなく上乗せの解除手段。生体認証をONにしていても
  // PINは必ず残す（指紋が濡れて反応しない・怪我をしたといった場面で
  // アプリを開けなくなるのを避けるため）。
  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometric) ?? false;
  }

  Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometric, value);
  }

  // ロックを無効化し、保存済みのPINも消す（再度有効化するときは必ず新しいPINを設定させるため）。
  // 生体認証の設定もアプリロックに紐づくものなので一緒に消す。
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPin);
    await prefs.remove(_keyBiometric);
    await prefs.setBool(_keyEnabled, false);
  }
}
