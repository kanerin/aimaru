import 'package:flutter/material.dart';

import '../services/bug_report_service.dart';
import '../utils/app_theme.dart';
import '../widgets/section_label.dart';

// ── バグ報告・機能要望フォーム ─────────────────────────────
// 送信するとサーバー側でGeminiによる厳格な判定にかけられ、有効なバグ報告・
// 機能要望だけがストックされる。ストックされた内容は別の自動化ワークフロー
// （fix-bug-reports.yml）が定期的に読み取り、実装・PR作成・auto-mergeまで行う。
class BugReportScreen extends StatefulWidget {
  // テスト用の注入ポイント。未指定時は本番のBugReportServiceを使う。
  final BugReportService? serviceOverride;

  const BugReportScreen({super.key, this.serviceOverride});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  // BugReportService() は生成時にFirebaseFunctions.instanceへ触れるため、
  // serviceOverrideを使うテストではFirebase初期化なしに動けるよう
  // 実際に使うときまで生成を遅らせる。
  BugReportService? _serviceInstance;
  BugReportService get _service => widget.serviceOverride ?? (_serviceInstance ??= BugReportService());

  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final result = await _service.submit(_controller.text);
      if (!mounted) return;
      if (result.accepted) {
        _controller.clear();
        final label = result.classification == BugReportClassification.bug ? 'バグ報告' : '機能要望';
        _showMessage('$labelとして受け付けました。ありがとうございます');
      } else {
        _showMessage('バグ報告・機能要望として判定できませんでした。内容を具体的にして再度お試しください');
      }
    } on BugReportSubmissionException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage(kBugReportUnknownMessage);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('バグ報告・機能要望')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'アプリの不具合や、こんな機能が欲しいという要望を自由に書いてください。'
            '内容はAIが確認した上で、開発チームの対応キューに追加されます。',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.6),
          ),
          const SizedBox(height: 20),
          const SectionLabel('内容'),
          TextField(
            controller: _controller,
            maxLines: 8,
            maxLength: 2000,
            enabled: !_submitting,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: '例: カレンダーで複数日の予定を登録すると、2日目以降が表示されません',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('送信する'),
            ),
          ),
        ],
      ),
    );
  }
}
