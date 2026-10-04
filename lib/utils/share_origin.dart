import 'package:flutter/material.dart';

/// 共有シートの出現位置（iPadのポップオーバーの吹き出し元）に使う矩形を返す。
///
/// iPadでは`sharePositionOrigin`が無い、または幅・高さが0の矩形だと共有シートが
/// 例外で開かない（share_plusの仕様）。レイアウト前や描画対象が無い場合は
/// nullを返し、呼び出し側はそのまま共有を試みる（iPhone/Androidでは不要）。
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  if (rect.isEmpty) return null;
  return rect;
}
