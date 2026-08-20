import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/models.dart';

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
// submitBugReport関数そのものに到達できなかった場合（本番へ未デプロイなど）。
// 何度やり直しても成功しないので、再試行を促す文言とは分けている。
const kBugReportUnavailableMessage = 'ただいま送信を受け付けられません。復旧までしばらくお待ちください';

class BugReportService {
  // 本番はFirebase Callable Functions（submitBugReport）を呼ぶ。
  // テストからは実際のFirebase呼び出しをせずに応答を差し込めるようにしてある。
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data) _invoke;

  // 自分が送った報告一覧（watchMyReports）用。引数なしで生成すると本番の
  // Firebaseを使う（既存の呼び出しはそのまま）。テストからは firestore / uid を
  // 差し込んでFirebaseに触れずに検証する。_dbは実際にwatchMyReports()を呼ぶまで
  // FirebaseFirestore.instanceへ触れないよう遅延させる（submit()しか使わない
  // 既存のテスト・呼び出し側でFirebase初期化が要らないようにするため）。
  final FirebaseFirestore? _firestoreOverride;
  final String? _overrideUid;

  BugReportService({
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? invoke,
    FirebaseFirestore? firestore,
    String? uid,
  })  : _invoke = invoke ?? _defaultInvoke,
        _firestoreOverride = firestore,
        _overrideUid = uid;

  FirebaseFirestore get _db => _firestoreOverride ?? FirebaseFirestore.instance;
  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  static Future<Map<String, dynamic>> _defaultInvoke(Map<String, dynamic> data) async {
    final callable = FirebaseFunctions.instance.httpsCallable('submitBugReport');
    final result = await callable.call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ── 自分が送った報告の一覧（新しい順）─────────────────────
  // firestore.rulesで自分の報告（createdBy == 自分）だけが読める。
  Stream<List<BugReportRecord>> watchMyReports() {
    return _db
        .collection('bugReports')
        .where('createdBy', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(BugReportRecord.fromDoc).toList());
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
        // Cloud Functions側に submitBugReport が存在しない。
        // 関数は自動デプロイされないため、コードだけ入って本番へ
        // 反映されていないと必ずこれになる。
        case 'not-found':
        case 'unimplemented':
          return kBugReportUnavailableMessage;
      }
    }
    final s = error.toString().toLowerCase();
    if (s.contains('network') || s.contains('socket') || s.contains('timeout')) {
      return kBugReportNetworkMessage;
    }
    return kBugReportUnknownMessage;
  }
}
