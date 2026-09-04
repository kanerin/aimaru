import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/calendar_feed_service.dart';
import '../utils/app_theme.dart';

// ── 外部カレンダーで見る（iCalendar購読フィード）─────────────────
// TimeTreeは「設定 → カレンダー情報 → iCal URLをコピー」で、Googleカレンダーや
// Appleカレンダーへ読み取り専用でURL購読できるが、AIMARUはこれまでICSの取り込み
// （IcsImportScreen）しか持たず、外へ公開する方向（export/購読）が無かった
// （2026年9月時点の競合調査）。
class CalendarFeedScreen extends StatefulWidget {
  // テストから本番のFirebase呼び出しに触れずに検証するための注入ポイント。
  final CalendarFeedService? serviceOverride;
  const CalendarFeedScreen({super.key, this.serviceOverride});

  @override
  State<CalendarFeedScreen> createState() => _CalendarFeedScreenState();
}

class _CalendarFeedScreenState extends State<CalendarFeedScreen> {
  late final CalendarFeedService _service = widget.serviceOverride ?? CalendarFeedService();
  late Future<String> _urlFuture = _service.fetchUrl();
  bool _regenerating = false;

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('リンクをコピーしました')),
    );
  }

  Future<void> _regenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('リンクを作り直しますか？'),
        content: const Text(
          '今のリンクは使えなくなります。すでに外部カレンダーへ登録している場合は、'
          '新しいリンクで登録し直してください。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('作り直す'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _regenerating = true);
    try {
      final url = await _service.regenerateUrl();
      if (!mounted) return;
      setState(() {
        _urlFuture = Future.value(url);
        _regenerating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _regenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('作り直しに失敗しました。もう一度お試しください')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('外部カレンダーで見る')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<String>(
          future: _urlFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: appAccent(context)));
            }
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'リンクの取得に失敗しました。もう一度開き直してください',
                  style: TextStyle(color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                ),
              );
            }

            final url = snapshot.data!;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'このリンクをGoogleカレンダーやAppleカレンダーの「URLで登録（購読）」に追加すると、'
                    'AIMARUの予定を他のカレンダーアプリでも読み取り専用で確認できます。',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecond, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.navySurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: SelectableText(
                      url,
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _copy(url),
                        child: const Text('リンクをコピー'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _regenerating ? null : _regenerate,
                        child: Text(_regenerating ? '作り直し中…' : 'リンクを作り直す'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Text(
                    'このリンクを知っていれば誰でも予定を読み取れます。共有には注意し、'
                    '心当たりのない共有をしてしまった場合は「リンクを作り直す」で無効化してください。',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
