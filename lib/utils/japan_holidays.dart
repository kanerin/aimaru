// ── 日本の祝日を計算するユーティリティ ──────────────────
// 外部パッケージ・通信に依存せず、法律で定められたルールから算出する。
// 春分・秋分の日は天文計算の近似式（実用上おおよそ1980〜2099年で誤差1日以内）を使用。
// 「国民の休日」（祝日に挟まれた平日が休日になる制度）は発生頻度が低いため未対応。
class JapanHolidays {
  static final Map<int, Map<DateTime, String>> _cache = {};

  static String? nameFor(DateTime date) {
    final key = DateTime(date.year, date.month, date.day);
    return _holidaysForYear(date.year)[key];
  }

  static bool isHoliday(DateTime date) => nameFor(date) != null;

  static Map<DateTime, String> _holidaysForYear(int year) {
    return _cache.putIfAbsent(year, () => _computeYear(year));
  }

  static Map<DateTime, String> _computeYear(int year) {
    final holidays = <DateTime, String>{};
    void add(DateTime d, String name) => holidays[DateTime(d.year, d.month, d.day)] = name;

    add(DateTime(year, 1, 1), '元日');
    add(_nthWeekdayOfMonth(year, 1, DateTime.monday, 2), '成人の日');
    add(DateTime(year, 2, 11), '建国記念の日');
    if (year >= 2020) add(DateTime(year, 2, 23), '天皇誕生日');
    add(_springEquinox(year), '春分の日');
    add(DateTime(year, 4, 29), '昭和の日');
    add(DateTime(year, 5, 3), '憲法記念日');
    add(DateTime(year, 5, 4), 'みどりの日');
    add(DateTime(year, 5, 5), 'こどもの日');
    add(_nthWeekdayOfMonth(year, 7, DateTime.monday, 3), '海の日');
    add(DateTime(year, 8, 11), '山の日');
    add(_nthWeekdayOfMonth(year, 9, DateTime.monday, 3), '敬老の日');
    add(_autumnEquinox(year), '秋分の日');
    add(_nthWeekdayOfMonth(year, 10, DateTime.monday, 2), 'スポーツの日');
    add(DateTime(year, 11, 3), '文化の日');
    add(DateTime(year, 11, 23), '勤労感謝の日');

    // 振替休日: 祝日が日曜なら、その後の最初の非祝日を休日にする
    final substitutes = <DateTime, String>{};
    for (final entry in holidays.entries) {
      if (entry.key.weekday == DateTime.sunday) {
        var next = entry.key.add(const Duration(days: 1));
        while (holidays.containsKey(next) || substitutes.containsKey(next)) {
          next = next.add(const Duration(days: 1));
        }
        substitutes[next] = '振替休日';
      }
    }
    holidays.addAll(substitutes);

    return holidays;
  }

  // 月の第N ○曜日（weekday: DateTime.monday など）
  static DateTime _nthWeekdayOfMonth(int year, int month, int weekday, int n) {
    var date = DateTime(year, month, 1);
    var count = 0;
    while (true) {
      if (date.weekday == weekday) {
        count++;
        if (count == n) return date;
      }
      date = date.add(const Duration(days: 1));
    }
  }

  // 春分の日（近似式。国立天文台が発表する実際の日と実用上ほぼ一致する範囲: 1980〜2099年）
  static DateTime _springEquinox(int year) {
    final day = (20.8431 + 0.242194 * (year - 1980) - ((year - 1980) / 4).floor()).floor();
    return DateTime(year, 3, day);
  }

  // 秋分の日（近似式。同上）
  static DateTime _autumnEquinox(int year) {
    final day = (23.2488 + 0.242194 * (year - 1980) - ((year - 1980) / 4).floor()).floor();
    return DateTime(year, 9, day);
  }
}
