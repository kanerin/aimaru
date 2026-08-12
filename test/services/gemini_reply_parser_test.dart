import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/services/gemini_service.dart';

// AIの応答文字列の解釈だけを対象にしたテスト。
// GenerativeModelには触れないので通信もAPIキーも不要。
//
// このテスト群が守っている性質はひとつ:
// 「解釈できない応答からは、決して予定を作らない」
// 共有カレンダーでは誤った予定がパートナーにも通知されるため、
// 黙って何かを作るくらいなら聞き返す方が安全という判断。
void main() {
  group('parseGeminiReply - 予定として解釈できる場合', () {
    test('kind=events の応答を予定候補へ変換できる', () {
      final reply = parseGeminiReply('''
{"kind":"events","events":[{"title":"映画デート","date":"2026-08-22","type":"date","recurring":false,"location":"渋谷","memo":"19時集合"}]}
''');

      expect(reply.kind, GeminiReplyKind.events);
      expect(reply.events, hasLength(1));

      final e = reply.events.single;
      expect(e.title, '映画デート');
      expect(e.date, DateTime(2026, 8, 22));
      expect(e.type, EventType.date);
      expect(e.recurring, isFalse);
      expect(e.location, '渋谷');
      expect(e.memo, '19時集合');
    });

    test('コードブロック囲い付きのJSONでもパースできる', () {
      final reply = parseGeminiReply('''
```json
{"kind":"events","events":[{"title":"記念日","date":"2026-09-01","type":"anniversary","recurring":true}]}
```
''');

      expect(reply.kind, GeminiReplyKind.events);
      expect(reply.events.single.title, '記念日');
      expect(reply.events.single.recurring, isTrue);
    });

    test('複数件のevents配列をすべて返す', () {
      final reply = parseGeminiReply(
        '{"kind":"events","events":['
        '{"title":"Aの誕生日","date":"2026-03-01","type":"celebrity","recurring":true},'
        '{"title":"Bの誕生日","date":"2026-04-02","type":"celebrity","recurring":true},'
        '{"title":"Cの誕生日","date":"2026-05-03","type":"celebrity","recurring":true}'
        ']}',
      );

      expect(reply.kind, GeminiReplyKind.events);
      expect(reply.events.map((e) => e.title),
          ['Aの誕生日', 'Bの誕生日', 'Cの誕生日']);
    });

    test('location と memo は省略できる', () {
      final reply = parseGeminiReply(
        '{"kind":"events","events":['
        '{"title":"予定","date":"2026-08-22","type":"plan","recurring":false}]}',
      );

      expect(reply.events.single.location, isNull);
      expect(reply.events.single.memo, isNull);
    });
  });

  group('parseGeminiReply - 通常の返答として扱う場合', () {
    test('kind=text の応答をそのまま返す', () {
      final reply = parseGeminiReply('{"kind":"text","text":"こんにちは"}');

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.text, 'こんにちは');
      expect(reply.events, isEmpty);
    });

    test('eventsが空配列なら予定を作らずtextへ倒す', () {
      final reply = parseGeminiReply('{"kind":"events","events":[]}');

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.events, isEmpty);
      expect(reply.text, kGeminiUnparseableMessage);
    });
  });

  group('parseGeminiReply - 壊れた応答', () {
    test('JSONとして不正な応答では予定を作らない', () {
      final reply = parseGeminiReply('これはJSONではない文章です');

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.events, isEmpty);
      expect(reply.text, kGeminiErrorMessage);
    });

    test('空文字列でも例外にならない', () {
      final reply = parseGeminiReply('');

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.events, isEmpty);
    });

    test('JSONがオブジェクトでない場合は聞き返す', () {
      for (final raw in ['[1,2,3]', '"文字列"', '42', 'null']) {
        final reply = parseGeminiReply(raw);

        expect(reply.kind, GeminiReplyKind.text, reason: 'raw=$raw');
        expect(reply.events, isEmpty, reason: 'raw=$raw');
        expect(reply.text, kGeminiUnparseableMessage, reason: 'raw=$raw');
      }
    });

    test('dateがパースできない値でも予定を作らない', () {
      final reply = parseGeminiReply(
        '{"kind":"events","events":['
        '{"title":"映画","date":"来週の土曜","type":"date","recurring":false}]}',
      );

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.events, isEmpty);
      expect(reply.text, kGeminiErrorMessage);
    });

    test('eventsの要素がオブジェクトでなくても落ちない', () {
      final reply = parseGeminiReply('{"kind":"events","events":["ただの文字列"]}');

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.events, isEmpty);
    });

    test('未知のtype値は plan にフォールバックする', () {
      final reply = parseGeminiReply(
        '{"kind":"events","events":['
        '{"title":"何か","date":"2026-08-22","type":"unknown_type","recurring":false}]}',
      );

      expect(reply.kind, GeminiReplyKind.events);
      expect(reply.events.single.type, EventType.plan);
    });

    test('kindが欠けていてもtextとして扱う', () {
      final reply = parseGeminiReply('{"text":"返答だけ"}');

      expect(reply.kind, GeminiReplyKind.text);
      expect(reply.text, '返答だけ');
    });
  });
}
