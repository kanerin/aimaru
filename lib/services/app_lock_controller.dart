import 'package:flutter/foundation.dart';

import 'app_lock_service.dart';
import 'biometric_service.dart';

// ── アプリ全体のロック状態を保持するコントローラ ──────────────
// ThemeControllerと同じ「シングルトン + ChangeNotifier」の形。
// `enabled`はSharedPreferencesに永続化された設定、`locked`はプロセス内だけの
// ランタイム状態（アプリを閉じて開き直すたびlockedはfalseから再構築される）。
class AppLockController extends ChangeNotifier {
  static final AppLockController instance = AppLockController._();
  AppLockController._();

  final _service = AppLockService();

  // 生体認証の実体。local_authはプラットフォームチャネル越しの呼び出しで
  // 単体テストから実行できないため、テストからは差し替えられるようにしてある。
  @visibleForTesting
  BiometricAuthenticator biometrics = BiometricService();

  bool _enabled = false;
  bool get enabled => _enabled;

  bool _locked = false;
  bool get locked => _locked;

  // 生体認証での解除を使う設定にしているか（PINは常に併用できる）。
  bool _biometricEnabled = false;
  bool get biometricEnabled => _biometricEnabled;

  // 起動時に一度だけ呼ぶ。有効化済みなら起動直後からロック状態で始める。
  Future<void> load() async {
    _enabled = await _service.isEnabled();
    _biometricEnabled = _enabled && await _service.isBiometricEnabled();
    _locked = _enabled;
    notifyListeners();
  }

  // 有効化する場合はPINを渡す（設定画面でのPIN入力後に呼ばれる想定）。
  // 無効化する場合はPINを消し、ロックも即座に解除する。
  Future<void> setEnabled(bool value, {String? pin}) async {
    if (value) {
      if (pin == null || pin.length != AppLockService.pinLength) return;
      await _service.setPin(pin);
      _enabled = true;
    } else {
      await _service.disable();
      _enabled = false;
      _biometricEnabled = false;
      _locked = false;
    }
    notifyListeners();
  }

  // 生体認証での解除のON/OFF。アプリロック自体が無効なら受け付けない
  // （PINの無い状態で生体認証だけが残ると、認証に失敗したとき開く手段が無くなる）。
  Future<void> setBiometricEnabled(bool value) async {
    if (value && !_enabled) return;
    await _service.setBiometricEnabled(value);
    _biometricEnabled = value;
    notifyListeners();
  }

  // この端末が生体認証を使える状態か（対応端末で、指紋・顔が登録済みか）。
  // 設定画面でトグルを出すかどうかの判定に使う。
  Future<bool> isBiometricAvailableOnDevice() => biometrics.isAvailable();

  // 解除画面で生体認証を試してよいか。設定がOFFなら端末へ問い合わせない。
  Future<bool> canUseBiometrics() async {
    if (!_enabled || !_biometricEnabled) return false;
    return biometrics.isAvailable();
  }

  // バックグラウンドへ回ったタイミングなどで呼ぶ。無効化中は何もしない。
  void lock() {
    if (!_enabled || _locked) return;
    _locked = true;
    notifyListeners();
  }

  Future<bool> unlock(String pin) async {
    final ok = await _service.verifyPin(pin);
    if (ok) {
      _locked = false;
      notifyListeners();
    }
    return ok;
  }

  // 指紋・顔での解除。失敗・キャンセル時はロックしたままにして、
  // 呼び出し側（AppLockScreen）でPIN入力を続けられるようにする。
  Future<bool> unlockWithBiometrics() async {
    if (!_enabled || !_biometricEnabled) return false;
    final ok = await biometrics.authenticate();
    if (ok) {
      _locked = false;
      notifyListeners();
    }
    return ok;
  }
}
