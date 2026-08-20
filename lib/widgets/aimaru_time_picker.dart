import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'time_dial.dart';

// ── このアプリの時刻ピッカー ────────────────────────────
//
// Flutter標準のshowTimePickerは、ダイヤルの選択円が48dp固定で
// テーマからは変えられない（_TimePickerDefaultsM3.dotRadius）。
// 円が数字より大きく隣の目盛りに被って読みにくかったため、
// 見た目を決められるよう自前で持っている。
//
// 呼び出し口はshowTimePickerと同じ形（initialTimeを渡し、
// 選ばれたTimeOfDay、キャンセルならnullが返る）。

Future<TimeOfDay?> showAimaruTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) =>
    showDialog<TimeOfDay>(
      context: context,
      builder: (_) => _AimaruTimePickerDialog(initialTime: initialTime),
    );

class _AimaruTimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;

  const _AimaruTimePickerDialog({required this.initialTime});

  @override
  State<_AimaruTimePickerDialog> createState() => _AimaruTimePickerDialogState();
}

class _AimaruTimePickerDialogState extends State<_AimaruTimePickerDialog> {
  late TimeOfDay _value = widget.initialTime;
  TimeDialMode _mode = TimeDialMode.hour;

  @override
  Widget build(BuildContext context) {
    // AlertDialogは左右40dpずつ内側に置かれ、さらにcontentPaddingを引いた幅しか
    // 使えない。狭い端末でダイヤルがはみ出さないよう、画面幅から決める。
    final available = MediaQuery.sizeOf(context).width - 40 * 2 - 16 * 2;
    final dialSize = available < 240 ? available : 240.0;

    return AlertDialog(
      backgroundColor: AppColors.navyCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        '時刻を選択',
        style: TextStyle(fontSize: 14, color: AppColors.textSecond),
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: dialSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _unit(
                  _value.hour.toString().padLeft(2, '0'),
                  selected: _mode == TimeDialMode.hour,
                  onTap: () => setState(() => _mode = TimeDialMode.hour),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(':',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecond)),
                ),
                _unit(
                  _value.minute.toString().padLeft(2, '0'),
                  selected: _mode == TimeDialMode.minute,
                  onTap: () => setState(() => _mode = TimeDialMode.minute),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TimeDial(
              size: dialSize,
              value: _value,
              mode: _mode,
              onChanged: (v) => setState(() => _value = v),
              // 時を決めたら分へ進む。分を触っているときは何もしない
              // （進める先が無いのに切り替わると選び直しづらい）。
              onSettled: () {
                if (_mode == TimeDialMode.hour) {
                  setState(() => _mode = TimeDialMode.minute);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _unit(String text, {required bool selected, required VoidCallback onTap}) {
    final accent = appAccent(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.18)
              : AppColors.navySurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: selected ? accent : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
