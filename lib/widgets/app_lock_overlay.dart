import 'package:flutter/widgets.dart';

// ── ロック中に画面を隠すが、破棄はしないオーバーレイ ─────────────
// アプリロック中はロック画面だけを見せ、下のアプリ（ルーター以下の画面）は
// Offstageで描画・タップ・読み上げ・フォーカスの対象から外したまま保持する。
//
// 以前はロック中にロック画面へ丸ごと差し替えていたため、下の画面は毎回
// 破棄されて解除後に作り直されていた。通知をタップしてアプリへ戻ると、
// 通知のタブ切り替え（トークなら「チャット」、質問なら「質問」）は
// 破棄される直前のホームが受け取って消費してしまい、解除後に作り直された
// ホームは最初のタブ（カレンダー）のままになっていた。開いていたタブや
// 入力途中の文章がロックのたびに消えるのも同じ原因。
class AppLockOverlay extends StatelessWidget {
  final bool locked;
  final Widget lockScreen;
  final Widget child;

  const AppLockOverlay({
    super.key,
    required this.locked,
    required this.lockScreen,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 子の位置（Stackの1番目）を固定しておかないと、lockedの切り替えで
        // 要素が作り直されて状態が消える。
        Offstage(
          offstage: locked,
          child: TickerMode(
            enabled: !locked,
            child: ExcludeFocus(excluding: locked, child: child),
          ),
        ),
        if (locked) lockScreen,
      ],
    );
  }
}
