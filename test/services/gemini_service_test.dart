import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/services/gemini_service.dart';

// GeminiServiceは実際のFirebase呼び出し（FirebaseFunctions.instance）を
// _invoke に差し込むことでバイパスできるようにしてある。ここではネットワーク・
// エミュレータのどちらにも触れず、以下を検証する:
// - コールにcoupleIdとcontents（system prompt・履歴・本文）が正しく渡ること
// - 成功時にparseGeminiReplyへ正しくつながること
// - 失敗時、Cloud Functionsのエラーコードごとに適切な文言へ翻訳されること
//
// respondToImageの応答パース自体はrespond()と同じparseGeminiReplyを
// 再利用しているため、「解釈できない応答からは予定を作らない」という
// 安全性はgemini_reply_parser_test.dartのテストでカバー済み。

/// テストからFirebaseFunctionsExceptionを組み立てるための最小限のサブクラス。
/// 本体のコンストラクタは@protectedだが、サブクラスからは呼べる。
class _FakeFunctionsException extends FirebaseFunctionsException {
  _FakeFunctionsException(String code) : super(message: 'テスト用', code: code);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  group('GeminiService.respond - 成功時', () {
    test('コールにcoupleIdとcontentsを渡し、応答をparseGeminiReplyで解釈する', () async {
      Map<String, dynamic>? captured;
      final service = GeminiService(
        coupleId: 'couple-1',
        invoke: (data) async {
          captured = data;
          return {'text': '{"kind":"text","text":"やあ"}'};
        },
      );

      final reply = await service.respond(
        'こんにちは',
        [
          {'role': 'user', 'text': '前回のメッセージ'},
          {'role': 'ai', 'text': '前回の返答'},
        ],
        eventsContext: '予定なし',
      );

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.text, 'やあ');

      expect(captured!['coupleId'], 'couple-1');
      final contents = captured!['contents'] as List;
      // [0]=システムプロンプト, [1][2]=履歴, [3]=本メッセージ
      expect(contents, hasLength(4));
      expect(contents[0]['role'], 'user');
      expect((contents[0]['parts'][0]['text'] as String).contains('AIMARU AI'), isTrue);
      expect(contents[1], {'role': 'user', 'parts': [{'text': '前回のメッセージ'}]});
      expect(contents[2], {'role': 'model', 'parts': [{'text': '前回の返答'}]});
      expect(contents[3], {'role': 'user', 'parts': [{'text': 'こんにちは'}]});
    });

    test('kind=eventsの応答から予定候補を作る', () async {
      final service = GeminiService(
        coupleId: 'couple-1',
        invoke: (_) async => {
          'text': '{"kind":"events","events":[{"title":"デート","date":"2026-09-01","type":"date","recurring":false}]}',
        },
      );

      final reply = await service.respond('来週デートしたい', const []);

      expect(reply.kind, GeminiReplyKind.events);
      expect(reply.events.single.title, 'デート');
    });
  });

  group('GeminiService.respondToImage - 成功時', () {
    test('画像をbase64にしてinlineDataとして渡す', () async {
      Map<String, dynamic>? captured;
      final service = GeminiService(
        coupleId: 'couple-1',
        invoke: (data) async {
          captured = data;
          return {'text': '{"kind":"text","text":"読み取れました"}'};
        },
      );

      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final reply = await service.respondToImage(bytes, 'image/png');

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.text, '読み取れました');

      final contents = captured!['contents'] as List;
      final lastParts = contents.last['parts'] as List;
      expect(lastParts[0], {'text': 'この画像から予定を抽出してください。'});
      expect(lastParts[1]['inlineData']['mimeType'], 'image/png');
      expect(lastParts[1]['inlineData']['data'], base64Encode(bytes));
    });
  });

  group('GeminiService - 呼び出しが失敗する場合', () {
    test('resource-exhaustedは利用上限メッセージ', () async {
      final service = GeminiService(
        coupleId: 'couple-1',
        invoke: (_) async => throw _FakeFunctionsException('resource-exhausted'),
      );

      final reply = await service.respond('x', const []);

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.text, kGeminiQuotaMessage);
    });

    test('failed-preconditionはAPIキー未設定メッセージ（サーバー側の鍵未設定）', () async {
      final service = GeminiService(
        coupleId: 'couple-1',
        invoke: (_) async => throw _FakeFunctionsException('failed-precondition'),
      );

      final reply = await service.respond('x', const []);

      expect(reply.text, kGeminiNoApiKeyMessage);
    });

    test('unauthenticated・permission-deniedは認証失敗メッセージ', () async {
      final serviceA = GeminiService(
        coupleId: 'couple-1',
        invoke: (_) async => throw _FakeFunctionsException('unauthenticated'),
      );
      final serviceB = GeminiService(
        coupleId: 'couple-1',
        invoke: (_) async => throw _FakeFunctionsException('permission-denied'),
      );

      expect((await serviceA.respond('x', const [])).text, kGeminiApiKeyMessage);
      expect((await serviceB.respond('x', const [])).text, kGeminiApiKeyMessage);
    });

    test('unavailable・deadline-exceededは通信エラーメッセージ', () async {
      final serviceA = GeminiService(
        coupleId: 'couple-1',
        invoke: (_) async => throw _FakeFunctionsException('unavailable'),
      );
      final serviceB = GeminiService(
        coupleId: 'couple-1',
        invoke: (_) async => throw _FakeFunctionsException('deadline-exceeded'),
      );

      expect((await serviceA.respond('x', const [])).text, kGeminiNetworkMessage);
      expect((await serviceB.respond('x', const [])).text, kGeminiNetworkMessage);
    });

    test('判別できないFunctionsのエラーコードは不明なエラーメッセージ', () async {
      final service = GeminiService(
        coupleId: 'couple-1',
        invoke: (_) async => throw _FakeFunctionsException('internal'),
      );

      final reply = await service.respond('x', const []);

      expect(reply.text, kGeminiUnknownErrorMessage);
    });

    test('FirebaseFunctionsException以外の例外はdescribeGeminiFailureにフォールバックする', () async {
      final service = GeminiService(
        coupleId: 'couple-1',
        invoke: (_) async => throw Exception('SocketException: Failed host lookup'),
      );

      final reply = await service.respond('x', const []);

      expect(reply.text, kGeminiNetworkMessage);
    });

    test('respondToImageでも同じ分岐で失敗を扱う', () async {
      final service = GeminiService(
        coupleId: 'couple-1',
        invoke: (_) async => throw _FakeFunctionsException('resource-exhausted'),
      );

      final reply = await service.respondToImage(Uint8List.fromList([1, 2, 3]), 'image/jpeg');

      expect(reply.text, kGeminiQuotaMessage);
    });
  });

  group('describeCallableFailure', () {
    test('FirebaseFunctionsExceptionの既知コードを分類する', () {
      expect(describeCallableFailure(_FakeFunctionsException('resource-exhausted')),
          kGeminiQuotaMessage);
      expect(describeCallableFailure(_FakeFunctionsException('failed-precondition')),
          kGeminiNoApiKeyMessage);
      expect(describeCallableFailure(_FakeFunctionsException('unauthenticated')),
          kGeminiApiKeyMessage);
      expect(describeCallableFailure(_FakeFunctionsException('permission-denied')),
          kGeminiApiKeyMessage);
      expect(describeCallableFailure(_FakeFunctionsException('unavailable')),
          kGeminiNetworkMessage);
    });

    // Cloud Functionsは自動デプロイされないため、コードだけ入って本番へ
    // 反映されていないと呼び出しがnot-foundで落ちる。これを「通信エラー」で
    // 一括りにすると、利用者からの報告だけでは原因を切り分けられない。
    test('関数が本番に無い場合(not-found/unimplemented)は復旧待ちの案内にする', () {
      expect(describeCallableFailure(_FakeFunctionsException('not-found')),
          kGeminiNotDeployedMessage);
      expect(describeCallableFailure(_FakeFunctionsException('unimplemented')),
          kGeminiNotDeployedMessage);
    });

    test('一般的な例外はdescribeGeminiFailureへフォールバックする', () {
      expect(describeCallableFailure(Exception('Connection timed out')), kGeminiNetworkMessage);
    });
  });
}
