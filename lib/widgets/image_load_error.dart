import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

// ── 画像の読み込み失敗時の表示 ─────────────────────
// CachedNetworkImageのerrorWidgetに渡す。何も出さないと、通信エラーのときに
// 空白（またはプレースホルダのまま）になり、読み込み中なのか壊れたのか区別できない。
class ImageLoadError extends StatelessWidget {
  final double? width;
  final double? height;
  const ImageLoadError({super.key, this.width, this.height = 140});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '画像を読み込めませんでした',
    excludeSemantics: true,
    child: Container(
      width: width,
      height: height,
      color: AppColors.navySurface,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
    ),
  );
}
