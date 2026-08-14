import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/gemini_service.dart';

// GeminiServiceはAPIキー未設定（`flutter test`はGEMINI_API_KEYを渡さない、
// CIのci.yml参照）だと、respond/respondToImageのどちらもネットワークへ
// 到達する前に決定的なメッセージを返す。この経路だけは通信なしで検証できる。
//
// respondToImageの応答パース自体はrespond()と同じparseGeminiReplyを
// 再利用しているため、「解釈できない応答からは予定を作らない」という
// 安全性はgemini_reply_parser_test.dartのテストでカバー済み。
void main() {
  group('GeminiService - APIキー未設定', () {
    test('respondはAPIキー未設定メッセージを返す', () async {
      final service = GeminiService();
      final reply = await service.respond('来週の土曜デートしたい', const []);

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.text, kGeminiNoApiKeyMessage);
      expect(reply.events, isEmpty);
    });

    test('respondToImageはAPIキー未設定メッセージを返す', () async {
      final service = GeminiService();
      final reply = await service.respondToImage(
        Uint8List.fromList([1, 2, 3]),
        'image/jpeg',
      );

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.text, kGeminiNoApiKeyMessage);
      expect(reply.events, isEmpty);
    });
  });
}
