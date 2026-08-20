// ── 日本の祝日を計算するユーティリティ ──────────────────
// 外部パッケージ・通信に依存せず、法律で定められたルールから算出する。
// 春分・秋分の日は天文計算の近似式（実用上おおよそ1980〜2099年で誤差1日以内）を使用。
//
// 休日は3種類あり、算出する順番に意味がある:
//   1. 国民の祝日（祝日法第2条）… 元日・敬老の日など、日付や曜日で決まるもの
//   2. 振替休日（同第3条第2項）… 祝日が日曜のとき、その後の最初の非祝日
//   3. 国民の休日（同第3条第3項）… 前日と翌日が「国民の祝日」である平日
// 2と3の判定はどちらも1だけを見る。振替休日や国民の休日は「国民の祝日」ではないので、
// これらを足したあとの集合で挟まれ判定をすると、休日が芋づる式に増えてしまう。
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
    // 国民の祝日（祝日法第2条）。振替休日・国民の休日の判定はこれだけを見る。
    final national = <DateTime, String>{};
    void add(DateTime d, String name) => national[DateTime(d.year, d.month, d.day)] = name;

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

    final holidays = Map<DateTime, String>.from(national);

    // 振替休日: 祝日が日曜なら、その後の最初の非祝日を休日にする
    final substitutes = <DateTime, String>{};
    for (final entry in national.entries) {
      if (entry.key.weekday == DateTime.sunday) {
        var next = _nextDay(entry.key);
        while (national.containsKey(next) || substitutes.containsKey(next)) {
          next = _nextDay(next);
        }
        substitutes[next] = '振替休日';
      }
    }
    holidays.addAll(substitutes);

    // 国民の休日: 前日と翌日がどちらも「国民の祝日」である日を休日にする。
    // 実際に起きるのは敬老の日（9月第3月曜）と秋分の日が1日空くとき
    // （2009・2015・2026・2032年など。いわゆるシルバーウィーク）。
    for (final day in national.keys) {
      final middle = _nextDay(day);
      // 前後が祝日でなければ挟まれていない。5/3〜5/5のように祝日が続く場合も、
      // 真ん中が祝日なので対象外（みどりの日のまま）。
      if (national.containsKey(middle) || !national.containsKey(_nextDay(middle))) {
        continue;
      }
      // 法の但し書きで、日曜と振替休日は国民の休日にしない。
      if (middle.weekday == DateTime.sunday || holidays.containsKey(middle)) continue;
      holidays[middle] = '国民の休日';
    }

    return holidays;
  }

  // 翌日。DateTimeの加算ではなく日付の繰り上げで求める
  // （Durationの加算はサマータイムのある地域で1日ちょうどにならない）。
  static DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

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
