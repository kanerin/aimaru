import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/utils/chat_date_divider.dart';

// トーク画面のセンターラインに日付区切りを出すかどうかの判定（#68）。
void main() {
  group('shouldShowDateDivider', () {
    test('直前のメッセージが無ければ常に出す（一覧の先頭）', () {
      expect(shouldShowDateDivider(null, DateTime(2026, 8, 22, 9, 0)), isTrue);
    });

    test('同じ日なら出さない', () {
      final previous = DateTime(2026, 8, 22, 9, 0);
      final current  = DateTime(2026, 8, 22, 23, 59);

      expect(shouldShowDateDivider(previous, current), isFalse);
    });

    test('日をまたいだら出す', () {
      final previous = DateTime(2026, 8, 22, 23, 59);
      final current  = DateTime(2026, 8, 23, 0, 0);

      expect(shouldShowDateDivider(previous, current), isTrue);
    });

    test('月をまたいでも日付として比較する', () {
      final previous = DateTime(2026, 8, 31, 23, 0);
      final current  = DateTime(2026, 9, 1, 1, 0);

      expect(shouldShowDateDivider(previous, current), isTrue);
    });

    test('年をまたいでも日付として比較する', () {
      final previous = DateTime(2026, 12, 31, 23, 0);
      final current  = DateTime(2027, 1, 1, 1, 0);

      expect(shouldShowDateDivider(previous, current), isTrue);
    });
  });
}
