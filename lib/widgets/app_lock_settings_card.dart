import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_controller.dart';
import '../services/app_lock_service.dart';
import '../utils/app_theme.dart';

// ── 設定画面に置く「アプリロック」カード ──────────────────
// スマホを相手に見せる・貸す場面でトーク・カレンダーを覗かれないための
// プライバシー機能。TimeTreeには無く、カップルアプリ全般で定番の機能
// （docs/open-issues.md参照）。ThemeControllerと同じくシングルトンの
// AppLockController.instanceをListenableBuilderで直接見る。
class AppLockSettingsCard extends StatelessWidget {
  const AppLockSettingsCard({super.key});

  Future<void> _onToggle(BuildContext context, bool value) async {
    if (value) {
      final pin = await _showSetPinDialog(context);
      if (pin == null) return; // キャンセル
      await AppLockController.instance.setEnabled(true, pin: pin);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('アプリロックを解除しますか？'),
        content: const Text('次回起動時からパスコードなしでアプリを開けるようになります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解除する', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AppLockController.instance.setEnabled(false);
    }
  }

  Future<void> _onChangePin(BuildContext context) async {
    final pin = await _showSetPinDialog(context);
    if (pin == null) return;
    await AppLockController.instance.setEnabled(true, pin: pin);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLockController.instance,
      builder: (context, _) {
        final enabled = AppLockController.instance.enabled;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.navySurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('アプリロック', style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                      )),
                      SizedBox(height: 4),
                      Text(
                        'スマホを渡すときも、4桁のパスコードでトーク・カレンダーを守れます',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5),
                      ),
                    ],
                  ),
                ),
                Switch(value: enabled, onChanged: (v) => _onToggle(context, v)),
              ]),
              if (enabled) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _onChangePin(context),
                    child: const Text('パスコードを変更'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// 新しいPINを2回入力させ、一致した場合だけ確定するダイアログ。
// キャンセル、または不一致のまま閉じた場合はnullを返す。
Future<String?> _showSetPinDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => const _SetPinDialog(),
  );
}

class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog();

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinController.text;
    final confirm = _confirmController.text;
    if (pin.length != AppLockService.pinLength || confirm.length != AppLockService.pinLength) {
      setState(() => _error = '4桁の数字を入力してください');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = '入力が一致しません');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    final formatters = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(AppLockService.pinLength),
    ];
    return AlertDialog(
      backgroundColor: AppColors.navyCard,
      title: const Text('パスコードを設定'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pinController,
            obscureText: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: const InputDecoration(labelText: '新しいパスコード（4桁）', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: const InputDecoration(labelText: '確認のため再入力', counterText: ''),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        TextButton(onPressed: _submit, child: const Text('設定する')),
      ],
    );
  }
}
