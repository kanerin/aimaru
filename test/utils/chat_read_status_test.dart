import 'package:flutter_test/flutter_test.dart';
import 'package:aimaru/utils/chat_read_status.dart';

void main() {
  group('isReadByPartner', () {
    final sent = DateTime(2026, 8, 24, 12, 0, 0);

    test('パートナーが未読（既読時刻が無い）なら既読ではない', () {
      expect(isReadByPartner(sent, null), isFalse);
    });

    test('パートナーの既読時刻が送信時刻より前なら既読ではない', () {
      final before = sent.subtract(const Duration(minutes: 1));
      expect(isReadByPartner(sent, before), isFalse);
    });

    test('パートナーの既読時刻が送信時刻と同じなら既読', () {
      expect(isReadByPartner(sent, sent), isTrue);
    });

    test('パートナーの既読時刻が送信時刻より後なら既読', () {
      final after = sent.add(const Duration(minutes: 1));
      expect(isReadByPartner(sent, after), isTrue);
    });
  });
}
