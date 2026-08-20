import 'package:cloud_functions/cloud_functions.dart';
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
}
