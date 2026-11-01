import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/couple_service.dart';
import '../utils/app_theme.dart';

// ホームを開く前に自分のペア情報を読み込む入口。
// 読み込みに失敗（権限・通信エラー）したときに、例外が拾われないまま
// 無限ローディングで固まらないよう、エラー表示と「再読み込み」を出す。
class CoupleLoader extends StatefulWidget {
  // テストからFirestoreに触れずにペア情報を差し込むための注入ポイント。
  final Future<CoupleModel?> Function()? loadOverride;

  // ペアが無かったときに呼ばれる（迷子にならないようペアリング画面へ送る）。
  final VoidCallback onNoCouple;

  final Widget Function(BuildContext context, String coupleId) builder;

  const CoupleLoader({
    super.key,
    this.loadOverride,
    required this.onNoCouple,
    required this.builder,
  });

  @override
  State<CoupleLoader> createState() => _CoupleLoaderState();
}

class _CoupleLoaderState extends State<CoupleLoader> {
  String? _coupleId;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final couple = await (widget.loadOverride ?? CoupleService().getMyCouple)();
      if (!mounted) return;
      if (couple == null) {
        widget.onNoCouple();
        return;
      }
      setState(() {
        _coupleId = couple.id;
        _failed = false;
      });
    } catch (e, st) {
      debugPrint('[ペア情報の読み込みに失敗] $e\n$st');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final coupleId = _coupleId;
    if (coupleId != null) return widget.builder(context, coupleId);
    if (_failed) {
      return Scaffold(
        backgroundColor: AppColors.navy,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('読み込みに失敗しました\n通信状況を確認してもう一度お試しください',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
              const SizedBox(height: 12),
              TextButton(onPressed: _retry, child: const Text('再読み込み')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: Center(child: CircularProgressIndicator(color: appAccent(context))),
    );
  }
}
