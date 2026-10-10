import 'package:flutter/material.dart';

import '../services/home_tab_requests.dart';

// HomeTabRequestsに届いた「このタブを開いて」をホームへ反映する。
// 表示される前に頼まれていた分（通知からの起動など）は最初のフレームで、
// 表示中に頼まれた分はその場で反映する。設定・予定詳細などホームの上に
// 積んだ画面に隠れたままタブだけ切り替わらないよう、ホームまで戻してから
// onTabを呼ぶ。
class HomeTabRequestListener extends StatefulWidget {
  final HomeTabRequests requests;
  final ValueChanged<HomeTab> onTab;
  final Widget child;

  const HomeTabRequestListener({
    super.key,
    required this.requests,
    required this.onTab,
    required this.child,
  });

  @override
  State<HomeTabRequestListener> createState() => _HomeTabRequestListenerState();
}

class _HomeTabRequestListenerState extends State<HomeTabRequestListener> {
  @override
  void initState() {
    super.initState();
    widget.requests.addListener(_apply);
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  @override
  void didUpdateWidget(HomeTabRequestListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requests != widget.requests) {
      oldWidget.requests.removeListener(_apply);
      widget.requests.addListener(_apply);
    }
  }

  @override
  void dispose() {
    widget.requests.removeListener(_apply);
    super.dispose();
  }

  void _apply() {
    if (!mounted) return;
    final tab = widget.requests.take();
    if (tab == null) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onTab(tab);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
