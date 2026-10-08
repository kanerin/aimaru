import 'dart:async';

import 'package:flutter/widgets.dart';

// ── 日付が変わったら子を作り直すラッパー ─────────────────
// ホームのIndexedStackはタブを離れても画面を保持し続けるため、「今日」を
// 生成時に固定する画面（ふたりの質問など）は、アプリをバックグラウンドに
// 置いたまま日付をまたぐと前日の内容のまま残る。前日の質問と自分の回答が
// 出ていると「今日はもう答えた」と見えて回答を逃し、連続回答日数が途切れる。
//
// アプリが前面に戻ったとき・日付が変わる瞬間に今日の日付を確かめ、
// 変わっていればキーを替えて子を作り直す。
class DailyRefresh extends StatefulWidget {
  final WidgetBuilder builder;
  // テストから「今」を差し替えるための注入ポイント。未指定時はDateTime.now。
  final DateTime Function()? clock;

  const DailyRefresh({super.key, required this.builder, this.clock});

  @override
  State<DailyRefresh> createState() => _DailyRefreshState();
}

class _DailyRefreshState extends State<DailyRefresh> with WidgetsBindingObserver {
  late String _dayKey = _currentDayKey();
  Timer? _midnightTimer;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  String _currentDayKey() {
    final now = _now();
    return '${now.year}-${now.month}-${now.day}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      // バックグラウンド中はタイマーが止まったり遅れたりするので張り直す。
      _scheduleMidnight();
    }
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = _now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    // ちょうど0時に発火すると端末の時計の誤差で前日と判定されうるので少し遅らせる。
    _midnightTimer = Timer(nextMidnight.difference(now) + const Duration(seconds: 1), () {
      _refresh();
      _scheduleMidnight();
    });
  }

  void _refresh() {
    if (!mounted) return;
    final key = _currentDayKey();
    if (key != _dayKey) setState(() => _dayKey = key);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey(_dayKey),
      child: Builder(builder: widget.builder),
    );
  }
}
