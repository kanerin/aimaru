import 'package:cloud_functions/cloud_functions.dart';

// ── 設定画面の「バグ報告・機能要望」フォーム ─────────────────
// 送信内容はサーバー側（functions/src/index.ts の submitBugReport）で
// Geminiによる厳格な判定にかけられ、有効な内容だけがストックされる。
// クライアント側はここでは判定を行わず、結果を表示するだけ。

enum BugReportClassification { bug, featureRequest, invalid }

class BugReportResult {
  final bool accepted;
  final BugReportClassification classification;
  final String summary;
  const BugReportResult({
    required this.accepted,
    required this.classification,
    required this.summary,
  });
}

class BugReportSubmissionException implements Exception {
  final String message;
  const BugReportSubmissionException(this.message);
  @override
  String toString() => message;
}

const kBugReportEmptyMessage = '内容を5文字以上2000文字以内で入力してください';
const kBugReportQuotaMessage = '本日の送信回数の上限に達しました。日をあらためてお試しください';
const kBugReportAuthMessage = '送信できませんでした。時間をおいてもう一度お試しください';
const kBugReportNetworkMessage = '通信に失敗しました。電波状況を確認してもう一度お試しください';
const kBugReportUnknownMessage = '送信に失敗しました。もう一度お試しください';

class BugReportService {
  // 本番はFirebase Callable Functions（submitBugReport）を呼ぶ。
  // テストからは実際のFirebase呼び出しをせずに応答を差し込めるようにしてある。
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data) _invoke;

  BugReportService({Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? invoke})
      : _invoke = invoke ?? _defaultInvoke;

  static Future<Map<String, dynamic>> _defaultInvoke(Map<String, dynamic> data) async {
    final callable = FirebaseFunctions.instance.httpsCallable('submitBugReport');
    final result = await callable.call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<BugReportResult> submit(String text) async {
    final trimmed = text.trim();
    if (trimmed.length < 5 || trimmed.length > 2000) {
      throw const BugReportSubmissionException(kBugReportEmptyMessage);
    }

    try {
      final data = await _invoke({'text': trimmed});
      return BugReportResult(
        accepted: data['accepted'] == true,
        classification: _parseClassification(data['classification'] as String?),
        summary: data['summary'] as String? ?? '',
      );
    } catch (e) {
      throw BugReportSubmissionException(_describeFailure(e));
    }
  }

  BugReportClassification _parseClassification(String? value) {
    switch (value) {
      case 'bug':
        return BugReportClassification.bug;
      case 'feature_request':
        return BugReportClassification.featureRequest;
      default:
        return BugReportClassification.invalid;
    }
  }

  String _describeFailure(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'resource-exhausted':
          return kBugReportQuotaMessage;
        case 'invalid-argument':
          return kBugReportEmptyMessage;
        case 'unauthenticated':
        case 'permission-denied':
          return kBugReportAuthMessage;
        case 'unavailable':
        case 'deadline-exceeded':
          return kBugReportNetworkMessage;
      }
    }
    final s = error.toString().toLowerCase();
    if (s.contains('network') || s.contains('socket') || s.contains('timeout')) {
      return kBugReportNetworkMessage;
    }
    return kBugReportUnknownMessage;
  }
}
