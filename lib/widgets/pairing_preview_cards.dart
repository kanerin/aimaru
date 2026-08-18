import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

// ── ペアリング画面に置く「ペアになるとできること」プレビュー ──
// ペアがまだ成立していない間は招待コードが表示されるだけで、相手の反応を
// 待つ間に離脱されやすい。何が使えるようになるかを先に見せることで、
// 招待を最後まで送ってもらう・相手に「入って」と説得する材料にする
// （旧Pairyからの移行検討ユーザーは他アプリと比較検討中であることが多く、
// この一押しが差別化になる）。
class PairingPreviewCards extends StatelessWidget {
  const PairingPreviewCards({super.key});

  static const _items = <_PreviewItem>[
    _PreviewItem(
      emoji: '🗓',
      title: '共有カレンダー',
      body: '2人の予定を1つに。Googleカレンダーとも同期できます',
    ),
    _PreviewItem(
      emoji: '✨',
      title: 'AIプランナー',
      body: 'チャットで話しかけるだけでAIが予定を登録します',
    ),
    _PreviewItem(
      emoji: '💬',
      title: 'カップルチャット',
      body: '2人だけのチャットルーム',
    ),
    _PreviewItem(
      emoji: '📸',
      title: '思い出',
      body: '写真や「n年前の今日」を振り返れます',
    ),
    _PreviewItem(
      emoji: '📝',
      title: 'やりたいこと・割り勘',
      body: '共有TODOと立て替えの精算をまとめて管理',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = _items[index];
          return Container(
            width: 168,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.navySurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    item.body,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                    overflow: TextOverflow.fade,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PreviewItem {
  final String emoji;
  final String title;
  final String body;
  const _PreviewItem({required this.emoji, required this.title, required this.body});
}
