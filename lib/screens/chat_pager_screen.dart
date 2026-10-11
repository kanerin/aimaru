import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'ai_chat_screen.dart';
import 'chat_screen.dart';

// ── チャットタブ（カップルチャット ⇄ AIチャット）──────────
// ホームの下部ナビを4つに絞るため、AIチャットは独立したタブではなく
// チャットタブの中で左右スワイプして切り替える。1枚目が2人のチャット、
// 右へ送った2枚目がAIチャット。
class ChatPagerScreen extends StatefulWidget {
  final String coupleId;
  // ホーム画面のIndexedStackで「チャット」タブが表示中かどうか。
  // ChatScreenの既読更新は、このタブが表示中かつ1枚目を見ているときだけ行う。
  final bool isActive;
  // テストからFirebaseに触れずに各ページを差し込むための注入ポイント。
  // 引数はそのページが表示中かどうか。未指定時は本番の画面を使う。
  final Widget Function(bool isActive)? chatPageOverride;
  final Widget Function(bool isActive)? aiChatPageOverride;

  const ChatPagerScreen({
    super.key,
    required this.coupleId,
    required this.isActive,
    this.chatPageOverride,
    this.aiChatPageOverride,
  });

  @override
  State<ChatPagerScreen> createState() => _ChatPagerScreenState();
}

class _ChatPagerScreenState extends State<ChatPagerScreen> {
  static const _chatPage = 0;
  static const _aiPage = 1;
  static const _labels = ['チャット', 'AIチャット'];

  final _pageController = PageController();
  int _page = _chatPage;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (page == _page) return;
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatActive = widget.isActive && _page == _chatPage;
    final aiActive = widget.isActive && _page == _aiPage;
    final topInset = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        PageView(
          controller: _pageController,
          onPageChanged: (i) {
            // 入力中のキーボードを残したまま隣の画面へ移ると、見えていない
            // 入力欄にフォーカスが残ってしまうので外しておく。
            FocusScope.of(context).unfocus();
            setState(() => _page = i);
          },
          children: [
            // PageViewは画面外のページを破棄するため、そのままだとAIチャットの
            // 会話や入力途中の文章がスワイプのたびに消える。KeepAliveで保持する。
            _KeepAlivePage(
              child: widget.chatPageOverride?.call(chatActive) ??
                  ChatScreen(coupleId: widget.coupleId, isActive: chatActive),
            ),
            _KeepAlivePage(
              child: widget.aiChatPageOverride?.call(aiActive) ??
                  AiChatScreen(coupleId: widget.coupleId),
            ),
          ],
        ),
        // 左右にスワイプできることが分かるよう、AppBarの下端にページの目印を置く。
        // タップでも切り替えられる（スワイプが苦手な人・読み上げ利用者向け）。
        Positioned(
          top: topInset + kToolbarHeight - 18,
          left: 0,
          right: 0,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _labels.length; i++)
                  _PageDot(
                    selected: i == _page,
                    label: '${_labels[i]}に切り替え',
                    onTap: () => _goTo(i),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PageDot extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _PageDot({required this.selected, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // 見た目は小さな点のまま、タップ領域だけ広げる。
        child: SizedBox(
          width: 24,
          height: 20,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: selected ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: selected ? appAccent(context) : AppColors.textMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
