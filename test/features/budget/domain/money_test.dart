import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/domain/money.dart';

void main() {
  test('3桁区切りで円をつける', () {
    expect(formatYen(0), '0円');
    expect(formatYen(999), '999円');
    expect(formatYen(1000), '1,000円');
    expect(formatYen(205000), '205,000円');
    expect(formatYen(8000000), '8,000,000円');
    expect(formatYen(-35000), '-35,000円');
  });

  test('差分は符号つきで表示する', () {
    expect(formatSignedYen(5000), '+5,000円');
    expect(formatSignedYen(-5000), '-5,000円');
    expect(formatSignedYen(0), '±0円');
  });

  test('入力欄の文字列から金額を読む（カンマ・円・全角数字を許す）', () {
    expect(parseAmount('120000'), 120000);
    expect(parseAmount('120,000'), 120000);
    expect(parseAmount('120,000円'), 120000);
    expect(parseAmount('１２００００'), 120000);
    expect(parseAmount('-5,000'), -5000);
    expect(parseAmount(''), isNull);
    expect(parseAmount('円'), isNull);
  });
}
