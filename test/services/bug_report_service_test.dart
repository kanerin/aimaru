import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/bug_report_service.dart';

// BugReportServiceは実際のFirebase呼び出しを_invokeに差し込むことで
// バイパスできるようにしてある。ここではネットワーク・エミュレータの
// どちらにも触れず、以下を検証する:
// - 空・短すぎる・長すぎる入力はサーバーへ送らずに弾くこと
// - 呼び出しにtextが正しく渡ること
// - サーバーの応答（accepted/classification/summary）を正しく解釈すること
// - 失敗時、Cloud Functionsのエラーコードごとに適切な文言へ翻訳されること

/// テストからFirebaseFunctionsExceptionを組み立てるための最小限のサブクラス。
class _FakeFunctionsException extends FirebaseFunctionsException {
  _FakeFunctionsException(String code) : super(message: 'テスト用', code: code);
}

void main() {
  group('BugReportService.submit - 入力検証', () {
    test('空文字はサーバーへ送らずに例外を投げる', () async {
      var called = false;
      final service = BugReportService(invoke: (data) async {
        called = true;
        return {};
      });

      await expectLater(
        service.submit(''),
        throwsA(isA<BugReportSubmissionException>()),
      );
      expect(called, isFalse);
    });

    test('5文字未満はサーバーへ送らずに例外を投げる', () async {
      var called = false;
      final service = BugReportService(invoke: (data) async {
        called = true;
        return {};
      });

      await expectLater(
        service.submit('あああ'),
        throwsA(isA<BugReportSubmissionException>()),
      );
      expect(called, isFalse);
    });

    test('2000文字を超える入力はサーバーへ送らずに例外を投げる', () async {
      var called = false;
      final service = BugReportService(invoke: (data) async {
        called = true;
        return {};
      });

      await expectLater(
        service.submit('あ' * 2001),
        throwsA(isA<BugReportSubmissionException>()),
      );
      expect(called, isFalse);
    });

    test('前後の空白を取り除いた上で送信する', () async {
      Map<String, dynamic>? captured;
      final service = BugReportService(invoke: (data) async {
        captured = data;
        return {'accepted': true, 'classification': 'bug', 'summary': '要約'};
      });

      await service.submit('  カレンダーが表示されない  ');

      expect(captured!['text'], 'カレンダーが表示されない');
    });
  });

  group('BugReportService.submit - 成功時', () {
    test('bug分類の受理を正しく解釈する', () async {
      final service = BugReportService(invoke: (data) async {
        return {'accepted': true, 'classification': 'bug', 'summary': 'カレンダーが表示されない'};
      });

      final result = await service.submit('カレンダーが表示されないバグがあります');

      expect(result.accepted, isTrue);
      expect(result.classification, BugReportClassification.bug);
      expect(result.summary, 'カレンダーが表示されない');
    });

    test('feature_request分類の受理を正しく解釈する', () async {
      final service = BugReportService(invoke: (data) async {
        return {'accepted': true, 'classification': 'feature_request', 'summary': 'ダークモードが欲しい'};
      });

      final result = await service.submit('ダークモードを追加してほしいです');

      expect(result.accepted, isTrue);
      expect(result.classification, BugReportClassification.featureRequest);
    });

    test('invalid分類（拒否）を正しく解釈する', () async {
      final service = BugReportService(invoke: (data) async {
        return {'accepted': false, 'classification': 'invalid', 'summary': 'アプリと無関係な内容'};
      });

      final result = await service.submit('これはアプリと関係ない内容です');

      expect(result.accepted, isFalse);
      expect(result.classification, BugReportClassification.invalid);
    });

    test('未知のclassification値はinvalidとして扱う（サーバー応答の防御的解釈）', () async {
      final service = BugReportService(invoke: (data) async {
        return {'accepted': false, 'classification': 'something_else', 'summary': ''};
      });

      final result = await service.submit('テスト入力です');

      expect(result.classification, BugReportClassification.invalid);
    });

    test('受理された報告のidを保持する（画像添付にreportIdとして使う）', () async {
      final service = BugReportService(invoke: (data) async {
        return {'accepted': true, 'classification': 'bug', 'summary': '要約', 'id': 'report-123'};
      });

      final result = await service.submit('カレンダーが表示されないバグがあります');

      expect(result.id, 'report-123');
    });

    test('拒否された場合はidを持たない', () async {
      final service = BugReportService(invoke: (data) async {
        return {'accepted': false, 'classification': 'invalid', 'summary': ''};
      });

      final result = await service.submit('アプリと無関係な内容です');

      expect(result.id, isNull);
    });
  });

  group('BugReportService.attachImages', () {
    test('reportIdとimageUrlsをそのまま渡す', () async {
      Map<String, dynamic>? captured;
      final service = BugReportService(invokeAttachImages: (data) async {
        captured = data;
        return {'ok': true};
      });

      await service.attachImages('report-123', ['https://example.com/a.jpg', 'https://example.com/b.jpg']);

      expect(captured!['reportId'], 'report-123');
      expect(captured!['imageUrls'], ['https://example.com/a.jpg', 'https://example.com/b.jpg']);
    });

    test('submit用のinvokeとは別の呼び出し口を使う', () async {
      var submitInvokeCalled = false;
      var attachInvokeCalled = false;
      final service = BugReportService(
        invoke: (data) async {
          submitInvokeCalled = true;
          return {'accepted': true, 'classification': 'bug', 'summary': ''};
        },
        invokeAttachImages: (data) async {
          attachInvokeCalled = true;
          return {'ok': true};
        },
      );

      await service.attachImages('report-123', ['https://example.com/a.jpg']);

      expect(attachInvokeCalled, isTrue);
      expect(submitInvokeCalled, isFalse);
    });

    test('失敗時はsubmit()と同じくCloud Functionsのエラーコードを翻訳する', () async {
      final service = BugReportService(invokeAttachImages: (data) async {
        throw _FakeFunctionsException('permission-denied');
      });

      await expectLater(
        service.attachImages('report-123', ['https://example.com/a.jpg']),
        throwsA(predicate((e) =>
            e is BugReportSubmissionException && e.message == kBugReportAuthMessage)),
      );
    });
  });

  group('BugReportService.submit - 失敗時', () {
    test('resource-exhaustedは上限メッセージへ翻訳する', () async {
      final service = BugReportService(invoke: (data) async {
        throw _FakeFunctionsException('resource-exhausted');
      });

      await expectLater(
        service.submit('テスト入力です'),
        throwsA(predicate((e) =>
            e is BugReportSubmissionException && e.message == kBugReportQuotaMessage)),
      );
    });

    test('unauthenticatedは認証系メッセージへ翻訳する', () async {
      final service = BugReportService(invoke: (data) async {
        throw _FakeFunctionsException('unauthenticated');
      });

      await expectLater(
        service.submit('テスト入力です'),
        throwsA(predicate((e) =>
            e is BugReportSubmissionException && e.message == kBugReportAuthMessage)),
      );
    });

    test('unavailableは通信系メッセージへ翻訳する', () async {
      final service = BugReportService(invoke: (data) async {
        throw _FakeFunctionsException('unavailable');
      });

      await expectLater(
        service.submit('テスト入力です'),
        throwsA(predicate((e) =>
            e is BugReportSubmissionException && e.message == kBugReportNetworkMessage)),
      );
    });

    // Cloud Functionsは自動デプロイされないため、submitBugReportが本番に
    // 存在しないとnot-foundで落ちる。再試行しても直らないので、
    // 「もう一度お試しください」とは別の案内にする。
    test('関数が本番に無い場合(not-found/unimplemented)は復旧待ちの案内にする', () async {
      for (final code in ['not-found', 'unimplemented']) {
        final service = BugReportService(invoke: (data) async {
          throw _FakeFunctionsException(code);
        });

        await expectLater(
          service.submit('テスト入力です'),
          throwsA(predicate((e) =>
              e is BugReportSubmissionException && e.message == kBugReportUnavailableMessage)),
        );
      }
    });

    test('未分類の例外は汎用メッセージへ翻訳する', () async {
      final service = BugReportService(invoke: (data) async {
        throw Exception('何か知らないエラー');
      });

      await expectLater(
        service.submit('テスト入力です'),
        throwsA(predicate((e) =>
            e is BugReportSubmissionException && e.message == kBugReportUnknownMessage)),
      );
    });
  });

  group('BugReportService.watchMyReports', () {
    late FakeFirebaseFirestore db;
    const uid = 'user-a';

    setUp(() {
      db = FakeFirebaseFirestore();
    });

    test('自分の報告だけを新しい順に返す', () async {
      await db.collection('bugReports').doc('r1').set({
        'summary': '古い方',
        'classification': 'bug',
        'status': 'pending',
        'createdBy': uid,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await db.collection('bugReports').doc('r2').set({
        'summary': '新しい方',
        'classification': 'feature_request',
        'status': 'done',
        'createdBy': uid,
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 1)),
        'prNumber': 42,
      });
      await db.collection('bugReports').doc('r3').set({
        'summary': '他人の報告',
        'classification': 'bug',
        'status': 'pending',
        'createdBy': 'user-b',
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
      });

      final service = BugReportService(firestore: db, uid: uid);
      final reports = await service.watchMyReports().first;

      expect(reports, hasLength(2));
      expect(reports[0].summary, '新しい方');
      expect(reports[0].status, 'done');
      expect(reports[0].prNumber, 42);
      expect(reports[1].summary, '古い方');
    });

    test('rejectCategoryを保持する', () async {
      await db.collection('bugReports').doc('r1').set({
        'summary': '見送られた要望',
        'classification': 'feature_request',
        'status': 'rejected',
        'rejectCategory': 'already_done',
        'createdBy': uid,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      final service = BugReportService(firestore: db, uid: uid);
      final reports = await service.watchMyReports().first;

      expect(reports.single.rejectCategory, 'already_done');
    });

    test('imageUrlsを保持する', () async {
      await db.collection('bugReports').doc('r1').set({
        'summary': '画像付きの報告',
        'classification': 'bug',
        'status': 'pending',
        'createdBy': uid,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'imageUrls': ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
      });

      final service = BugReportService(firestore: db, uid: uid);
      final reports = await service.watchMyReports().first;

      expect(reports.single.imageUrls, ['https://example.com/a.jpg', 'https://example.com/b.jpg']);
    });

    test('imageUrlsが無い報告は空リストになる', () async {
      await db.collection('bugReports').doc('r1').set({
        'summary': '画像無しの報告',
        'classification': 'bug',
        'status': 'pending',
        'createdBy': uid,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      final service = BugReportService(firestore: db, uid: uid);
      final reports = await service.watchMyReports().first;

      expect(reports.single.imageUrls, isEmpty);
    });
  });
}
