// ── 記念日（付き合い始めた日）から、経過日数・次の節目までの日数を計算する ──
// TimeTreeのような汎用カレンダーには無い、カップル向けアプリ特有の指標。
// 100日ごとの節目（100日・200日…）と、周年（1周年・2周年…）の両方を追う。

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// 記念日当日を1日目として数える（日本のカップルアプリでの一般的な数え方）。
// 記念日が未来の場合は0を返す。
int daysTogether(DateTime anniversary, DateTime today) {
  final diff = _dateOnly(today).difference(_dateOnly(anniversary)).inDays;
  return diff < 0 ? 0 : diff + 1;
}

class _Milestone {
  final int day;
  final int daysUntil;
  const _Milestone(this.day, this.daysUntil);
}

_Milestone _nextHundredDayMilestone(int daysTogetherCount) {
  final count = daysTogetherCount <= 0 ? 1 : daysTogetherCount;
  final day = ((count - 1) ~/ 100 + 1) * 100;
  return _Milestone(day, day - count);
}

// 2/29生まれの記念日を非うるう年の月/日に落とし込む（2/28扱い）。
// 記念日自体が実在した日付である以上、繰り上がるのはこのケースのみ。
DateTime _monthDayInYear(int year, int month, int day) {
  final d = DateTime(year, month, day);
  return d.month != month ? DateTime(year, month, day - 1) : d;
}

class AnniversarySummary {
  final int daysTogether;
  final int nextMilestoneDay;
  final int daysUntilNextMilestone;
  final int nextAnniversaryYearCount; // 次に迎えるのが何周年か
  final DateTime nextAnniversaryDate;
  final int daysUntilNextAnniversary;

  const AnniversarySummary({
    required this.daysTogether,
    required this.nextMilestoneDay,
    required this.daysUntilNextMilestone,
    required this.nextAnniversaryYearCount,
    required this.nextAnniversaryDate,
    required this.daysUntilNextAnniversary,
  });
}

AnniversarySummary summarizeAnniversary(DateTime anniversary, DateTime today) {
  final a = _dateOnly(anniversary);
  final t = _dateOnly(today);
  final together = daysTogether(a, t);
  final milestone = _nextHundredDayMilestone(together);

  var yearsSince = t.year - a.year;
  var candidate = _monthDayInYear(a.year + yearsSince, a.month, a.day);
  if (candidate.isBefore(t)) {
    yearsSince += 1;
    candidate = _monthDayInYear(a.year + yearsSince, a.month, a.day);
  }
  if (yearsSince <= 0) {
    yearsSince = 1;
    candidate = _monthDayInYear(a.year + 1, a.month, a.day);
  }

  return AnniversarySummary(
    daysTogether: together,
    nextMilestoneDay: milestone.day,
    daysUntilNextMilestone: milestone.daysUntil,
    nextAnniversaryYearCount: yearsSince,
    nextAnniversaryDate: candidate,
    daysUntilNextAnniversary: candidate.difference(t).inDays,
  );
}
