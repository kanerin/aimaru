import 'package:flutter/material.dart';
import '../services/couple_service.dart';
import '../utils/app_theme.dart';
import 'questions_screen.dart';

// 「ふたりの質問」の通知をタップしたときに、ペア情報を読み込んでから
// QuestionsScreenを開くための入口。QuestionsScreenはcoupleId・memberIds・
// partnerNameを必要とするが、通知から開くときは設定画面のように手元に
// ペア情報が無いため、ここで取得する（`/home/questions`ルートから使う）。
class QuestionsRouteScreen extends StatefulWidget {
  // テストからFirestoreに触れずにペア情報を差し込むための注入ポイント。
  // 未指定時は本番のCoupleServiceから取得する。
  final Future<QuestionsRouteArgs?> Function()? loadOverride;

  const QuestionsRouteScreen({super.key, this.loadOverride});

  @override
  State<QuestionsRouteScreen> createState() => _QuestionsRouteScreenState();
}

// QuestionsScreenへ渡すペア情報。
class QuestionsRouteArgs {
  final String coupleId;
  final List<String> memberIds;
  final String partnerName;

  const QuestionsRouteArgs({
    required this.coupleId,
    required this.memberIds,
    required this.partnerName,
  });
}

class _QuestionsRouteScreenState extends State<QuestionsRouteScreen> {
  late Future<QuestionsRouteArgs?> _future = _load();

  Future<QuestionsRouteArgs?> _load() {
    final override = widget.loadOverride;
    if (override != null) return override();
    return _loadFromService();
  }

  static Future<QuestionsRouteArgs?> _loadFromService() async {
    final service = CoupleService();
    final couple = await service.getMyCouple();
    if (couple == null) return null;
    final partnerName = await service.getPartnerName(couple);
    return QuestionsRouteArgs(
      coupleId: couple.id,
      memberIds: couple.memberIds,
      partnerName: partnerName ?? 'パートナー',
    );
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuestionsRouteArgs?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done) {
          final args = snap.data;
          if (snap.hasError) {
            return _MessageScaffold(
              message: '読み込みに失敗しました\n通信状況を確認してもう一度お試しください',
              actionLabel: '再読み込み',
              onAction: _retry,
            );
          }
          if (args == null) {
            return const _MessageScaffold(
              message: 'ペアが見つかりませんでした',
            );
          }
          return QuestionsScreen(
            coupleId: args.coupleId,
            memberIds: args.memberIds,
            partnerName: args.partnerName,
          );
        }
        return Scaffold(
          backgroundColor: AppColors.navy,
          appBar: AppBar(title: const Text('ふたりの質問')),
          body: Center(child: CircularProgressIndicator(color: appAccent(context))),
        );
      },
    );
  }
}

class _MessageScaffold extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageScaffold({required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('ふたりの質問')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
