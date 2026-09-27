import 'package:flutter/material.dart';

// 「追加」「送信」のような円形のプライマリ操作ボタンの共有ウィジェット。
// 各画面はGestureDetector+Containerで見た目だけを揃えていたため、タップしても
// リップル等の視覚的な反応が無く、スクリーンリーダーからも存在しないボタンとして
// 扱われていた（Semanticsラベルが一切無いため）。この共有ウィジェットに置き換える
// ことで、タップフィードバックとボタンとしての読み上げを一貫して付与する。
class CircularActionButton extends StatelessWidget {
  const CircularActionButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    required this.decoration,
    this.size = 40,
    this.shape = const CircleBorder(),
    this.margin,
    this.tooltip,
  });

  final Widget icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final BoxDecoration decoration;
  final double size;
  final ShapeBorder shape;
  final EdgeInsetsGeometry? margin;
  // 長押し・マウスホバーで文言を出したい場合に指定する（未指定ならSemanticsの
  // ラベルのみで、見た目のツールチップ吹き出しは出さない）。
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget button = Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Container(
            width: size,
            height: size,
            decoration: decoration,
            child: Center(child: icon),
          ),
        ),
      ),
    );
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return Padding(padding: margin ?? EdgeInsets.zero, child: button);
  }
}
