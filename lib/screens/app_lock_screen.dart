import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_controller.dart';
import '../services/app_lock_service.dart';
import '../utils/app_theme.dart';

// ── アプリロック解除画面 ────────────────────────────
// AppLockController.locked が true の間、AimaruApp全体の代わりに表示される。
// PINが一致するとunlock()がAppLockController.lockedをfalseにし、
// 呼び出し側（_AppLockGate）がListenableBuilderで元の画面に戻す。
class AppLockScreen extends StatefulWidget {
  // テスト用の注入ポイント。未指定時はAppLockController.instance.unlockを使う。
  final Future<bool> Function(String pin)? unlockOverride;

  const AppLockScreen({super.key, this.unlockOverride});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _pinController = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
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
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
