import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

// 一覧の読み込みに失敗したときの表示。文言だけだと「開き直す」しか手が無く、
// 一時的な通信エラーでも画面を閉じて入り直す必要があったため、
// その場でストリームを張り直せる「再読み込み」ボタンを添える。
class LoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const LoadErrorView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('読み込みに失敗しました\n通信状況を確認してもう一度お試しください',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('再読み込み')),
        ],
      ),
    );
  }
}
