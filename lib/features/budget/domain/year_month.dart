// ── 年月（家計の計算は月単位で行うため、日を持たない値型）────────
// DateTimeで月を表すと「日」と「時刻」がついて回り、月の加算で
// 1/31 + 1ヶ月 = 3/3 のような繰り上がりも起きる。貯金推移は月ごとに
// 1点ずつ積み上げるだけなので、年と月だけを持つ値型にしておく。
class YearMonth implements Comparable<YearMonth> {
  final int year;
  final int month; // 1〜12

  const YearMonth(this.year, this.month) : assert(month >= 1 && month <= 12);

  factory YearMonth.fromDate(DateTime date) => YearMonth(date.year, date.month);

  // 'yyyy-MM' 形式（Firestoreや履歴の表示用）
  factory YearMonth.parse(String value) {
    final parts = value.split('-');
    if (parts.length != 2) throw FormatException('YearMonthの形式が不正です: $value');
    return YearMonth(int.parse(parts[0]), int.parse(parts[1]));
  }

  // 西暦0年1月を0とした通し番号。月の加算・差分をこれで計算する。
  int get _index => year * 12 + (month - 1);

  YearMonth addMonths(int months) {
    final index = _index + months;
    return YearMonth(index ~/ 12, index % 12 + 1);
  }

  // thisからotherまでの月数（other が後なら正）。
  int monthsUntil(YearMonth other) => other._index - _index;

  bool isBefore(YearMonth other) => _index < other._index;
  bool isAfter(YearMonth other) => _index > other._index;

  // その月の1日（DateTimeが必要な画面・カレンダー連携用）
  DateTime get firstDay => DateTime(year, month, 1);

  @override
  int compareTo(YearMonth other) => _index.compareTo(other._index);

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}
