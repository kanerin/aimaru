import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_controller.dart';
import '../services/app_lock_service.dart';
import '../utils/app_theme.dart';

// ── アプリロック解除画面 ────────────────────────────
// AppLockController.locked が true の間、AimaruApp全体の代わりに表示される。
// PINが一致するとunlock()がAppLockController.lockedをfalseにし、
// 呼び出し側（_AppLockGate）がListenableBuilderで元の画面に戻す。
//
// 生体認証（指紋・顔）を有効にしている場合は、開いた直後に一度だけ自動で
// 認証を求める。失敗・キャンセルしてもPIN入力欄は常に残しておく
// （指紋が反応しない場面でアプリを開けなくなることが無いように）。
class AppLockScreen extends StatefulWidget {
  // テスト用の注入ポイント。未指定時はAppLockController.instance.unlockを使う。
  final Future<bool> Function(String pin)? unlockOverride;
  // テスト用の注入ポイント。未指定時はAppLockController.instance.canUseBiometricsを使う。
  final Future<bool> Function()? canUseBiometricsOverride;
  // テスト用の注入ポイント。未指定時はAppLockController.instance.unlockWithBiometricsを使う。
  final Future<bool> Function()? biometricUnlockOverride;

  const AppLockScreen({
    super.key,
    this.unlockOverride,
    this.canUseBiometricsOverride,
    this.biometricUnlockOverride,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _pinController = TextEditingController();
  String? _error;
  bool _checking = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _initBiometrics();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  // 生体認証が使えるなら、開いた直後に一度だけ自動で求める。
  // 使えない設定・端末では端末への問い合わせ自体が起きない。
  Future<void> _initBiometrics() async {
    final canUse = widget.canUseBiometricsOverride ?? AppLockController.instance.canUseBiometrics;
    final available = await canUse();
    if (!mounted || !available) return;
    setState(() => _biometricAvailable = true);
    await _authenticateWithBiometrics();
  }

  Future<void> _authenticateWithBiometrics() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    final unlock = widget.biometricUnlockOverride ?? AppLockController.instance.unlockWithBiometrics;
    await unlock();

    // 成功時はlocked=falseの通知で親が画面を差し替えるため、このウィジェットは
    // 破棄される。失敗・キャンセルはエラー扱いにしない（PINで開ける導線が
    // 残っているのに赤字を出すと「開けない」と誤解させるだけになる）。
    if (!mounted) return;
    setState(() => _checking = false);
  }

  Future<void> _submit() async {
    final pin = _pinController.text;
    if (pin.length != AppLockService.pinLength) return;

    setState(() {
      _checking = true;
      _error = null;
    });

    final unlock = widget.unlockOverride ?? AppLockController.instance.unlock;
    final ok = await unlock(pin);

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _checking = false;
        _error = 'パスコードが違います';
        _pinController.clear();
      });
    }
    // 成功時はAppLockController.locked=falseへの通知で親が画面を差し替えるため、
    // ここでは特に何もしない（このウィジェット自体が破棄される）。
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: AppColors.navySurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: const Center(
                  child: Icon(Icons.lock_outline, color: AppColors.cream, size: 28),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'パスコードを入力',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.cream),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pinController,
                autofocus: true,
                enabled: !_checking,
                obscureText: true,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(AppLockService.pinLength),
                ],
                style: const TextStyle(fontSize: 24, letterSpacing: 12, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••',
                  hintStyle: const TextStyle(color: AppColors.textMuted, letterSpacing: 12),
                  filled: true,
                  fillColor: AppColors.navySurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.hairline),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_checking || _pinController.text.length != AppLockService.pinLength)
                      ? null
                      : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: appAccent(context),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _checking
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('解除'),
                ),
              ),
              // 自動で出した認証をキャンセルした後でも、やり直せる導線を残す。
              if (_biometricAvailable) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _checking ? null : _authenticateWithBiometrics,
                  icon: const Icon(Icons.fingerprint, size: 20),
                  label: const Text('指紋・顔認証で解除'),
                ),
              ],
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
