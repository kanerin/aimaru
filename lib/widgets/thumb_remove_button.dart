import 'package:flutter/material.dart';

// 添付画像サムネイルの角に置く「外す」ボタン。
// 見た目は小さな丸のまま、タップ領域は48pxを確保する（20pxのGestureDetectorでは
// 押し損ねやすく、スクリーンリーダーにもラベル無しの存在しないボタンだった）。
// 親のサムネイル（72px）の右上に`Positioned(top: 0, right: 0)`で置くこと。
class ThumbRemoveButton extends StatelessWidget {
  const ThumbRemoveButton({
    super.key,
    required this.onTap,
    this.label = '画像を外す',
  });

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      // excludeSemanticsで子のタップ操作も消えるため、読み上げ操作用にここでも渡す。
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 48, height: 48,
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              width: 24, height: 24,
              margin: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}
