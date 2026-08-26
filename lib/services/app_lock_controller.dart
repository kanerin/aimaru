import 'package:flutter/foundation.dart';

import 'app_lock_service.dart';

// ── アプリ全体のロック状態を保持するコントローラ ──────────────
// ThemeControllerと同じ「シングルトン + ChangeNotifier」の形。
// `enabled`はSharedPreferencesに永続化された設定、`locked`はプロセス内だけの
// ランタイム状態（アプリを閉じて開き直すたびlockedはfalseから再構築される）。
class AppLockController extends ChangeNotifier {
  static final AppLockController instance = AppLockController._();
  AppLockController._();

  final _service = AppLockService();

  bool _enabled = false;
  bool get enabled => _enabled;

  bool _locked = false;
  bool get locked => _locked;

  // 起動時に一度だけ呼ぶ。有効化済みなら起動直後からロック状態で始める。
  Future<void> load() async {
    _enabled = await _service.isEnabled();
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
      _locked = false;
    }
    notifyListeners();
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
}
