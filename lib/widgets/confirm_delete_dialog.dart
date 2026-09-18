import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

// 削除確認ダイアログ。元に戻せない削除（ゴミ箱を持たないコレクション）を
// 複数の画面（やりたいことリスト・家事分担・買い物リスト・ほしいものリスト等）
// で共通の文言・ボタン配置にするための共有ヘルパー。
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.navyCard,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('削除', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
