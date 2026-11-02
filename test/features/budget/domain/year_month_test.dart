import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/features/budget/domain/year_month.dart';

void main() {
  test('月の加算は年をまたいで繰り上がる・繰り下がる', () {
    expect(const YearMonth(2026, 11).addMonths(2), const YearMonth(2027, 1));
    expect(const YearMonth(2026, 1).addMonths(-1), const YearMonth(2025, 12));
    expect(const YearMonth(2026, 12).addMonths(12), const YearMonth(2027, 12));
  });

  test('月数の差（後ろなら正）', () {
    expect(const YearMonth(2026, 11).monthsUntil(const YearMonth(2028, 10)), 23);
    expect(const YearMonth(2026, 11).monthsUntil(const YearMonth(2026, 10)), -1);
  });

  test('DateTimeからは年と月だけを取る（日・時刻は捨てる）', () {
    expect(YearMonth.fromDate(DateTime(2026, 1, 31, 23, 59)), const YearMonth(2026, 1));
  });

  test('yyyy-MMで文字列化し、同じ形式から読み戻せる', () {
    expect(const YearMonth(2027, 3).toString(), '2027-03');
    expect(YearMonth.parse('2027-03'), const YearMonth(2027, 3));
    expect(() => YearMonth.parse('2027'), throwsFormatException);
  });

  test('前後の比較', () {
    const a = YearMonth(2026, 12);
    const b = YearMonth(2027, 1);
    expect(a.isBefore(b), isTrue);
    expect(b.isAfter(a), isTrue);
    expect(a.compareTo(b), lessThan(0));
    expect([b, a]..sort(), [a, b]);
  });
}
