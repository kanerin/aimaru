// ── iCalendar (.ics) パーサー ──────────────────────────
// TimeTree・Googleカレンダーなど他社アプリはiCalendar形式(RFC5545)で
// 予定をエクスポートできる。Pairyのようにサービス終了するアプリからの
// 移行者を含め、他社カレンダーからAIMARUへ予定を持ち込む導線として使う
// （docs/open-issues.md 課題12）。VEVENTのうちアプリで使う項目だけを
// 拾う簡易パーサーで、対応外のプロパティは無視する。

class IcsParsedEvent {
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String? location;
  final String? description;

  const IcsParsedEvent({
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.location,
    this.description,
  });
}

List<IcsParsedEvent> parseIcsEvents(String icsText) {
  final lines = _unfold(icsText);
  final events = <IcsParsedEvent>[];

  Map<String, _IcsLine>? current;
  for (final rawLine in lines) {
    final line = _parseLine(rawLine);
    if (line == null) continue;

    if (line.name == 'BEGIN' && line.value.trim().toUpperCase() == 'VEVENT') {
      current = {};
      continue;
    }
    if (line.name == 'END' && line.value.trim().toUpperCase() == 'VEVENT') {
      if (current != null) {
        final event = _buildEvent(current);
        if (event != null) events.add(event);
      }
      current = null;
      continue;
    }
    // 同じ名前のプロパティが複数回出た場合は最初の1つを使う
    current?.putIfAbsent(line.name, () => line);
  }
  return events;
}

// RFC5545の行折り返し（次行が半角スペース/タブで始まる継続行）を1行にまとめる
List<String> _unfold(String text) {
  final rawLines = text.replaceAll('\r\n', '\n').split('\n');
  final result = <String>[];
  for (final line in rawLines) {
    if ((line.startsWith(' ') || line.startsWith('\t')) && result.isNotEmpty) {
      result[result.length - 1] += line.substring(1);
    } else {
      result.add(line);
    }
  }
  return result;
}

class _IcsLine {
  final String name;
  final Map<String, String> params;
  final String value;
  _IcsLine(this.name, this.params, this.value);
}

_IcsLine? _parseLine(String line) {
  final colonIdx = line.indexOf(':');
  if (colonIdx == -1) return null;
  final head = line.substring(0, colonIdx);
  final value = line.substring(colonIdx + 1);

  final parts = head.split(';');
  final name = parts.first.trim().toUpperCase();
  if (name.isEmpty) return null;

  final params = <String, String>{};
  for (final p in parts.skip(1)) {
    final eq = p.indexOf('=');
    if (eq == -1) continue;
    params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1);
  }
  return _IcsLine(name, params, value);
}

IcsParsedEvent? _buildEvent(Map<String, _IcsLine> fields) {
  final dtStart = fields['DTSTART'];
  if (dtStart == null) return null;
  final start = _parseDate(dtStart);
  if (start == null) return null;

  final dtEnd = fields['DTEND'];
  final end = dtEnd != null ? _parseDate(dtEnd) : null;

  final title = fields['SUMMARY'] != null
      ? _unescapeText(fields['SUMMARY']!.value.trim())
      : '(タイトルなし)';
  final location = _unescapeOrNull(fields['LOCATION']);
  final description = _unescapeOrNull(fields['DESCRIPTION']);

  return IcsParsedEvent(
    title: title.isEmpty ? '(タイトルなし)' : title,
    start: start,
    end: end,
    allDay: dtStart.params['VALUE']?.toUpperCase() == 'DATE',
    location: location,
    description: description,
  );
}

String? _unescapeOrNull(_IcsLine? line) {
  if (line == null) return null;
  final v = _unescapeText(line.value.trim());
  return v.isEmpty ? null : v;
}

final _dateOnlyPattern = RegExp(r'^\d{8}$');
final _dateTimePattern = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$');

DateTime? _parseDate(_IcsLine line) {
  final v = line.value.trim();
  if (v.isEmpty) return null;

  final isDateOnly = line.params['VALUE']?.toUpperCase() == 'DATE' || _dateOnlyPattern.hasMatch(v);
  if (isDateOnly) {
    if (!_dateOnlyPattern.hasMatch(v)) return null;
    return DateTime(int.parse(v.substring(0, 4)), int.parse(v.substring(4, 6)), int.parse(v.substring(6, 8)));
  }

  final match = _dateTimePattern.firstMatch(v);
  if (match == null) return null;
  final y  = int.parse(match.group(1)!);
  final mo = int.parse(match.group(2)!);
  final d  = int.parse(match.group(3)!);
  final h  = int.parse(match.group(4)!);
  final mi = int.parse(match.group(5)!);
  final s  = int.parse(match.group(6)!);
  final isUtc = match.group(7) == 'Z';
  // TZIDによるタイムゾーン変換までは対応せず、UTC(Z)以外は端末のローカル時刻として扱う
  return isUtc ? DateTime.utc(y, mo, d, h, mi, s).toLocal() : DateTime(y, mo, d, h, mi, s);
}

String _unescapeText(String v) {
  final buf = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    final c = v[i];
    if (c == r'\' && i + 1 < v.length) {
      final next = v[i + 1];
      switch (next) {
        case 'n':
        case 'N':
          buf.write('\n');
          i++;
        case ';':
          buf.write(';');
          i++;
        case ',':
          buf.write(',');
          i++;
        case r'\':
          buf.write(r'\');
          i++;
        default:
          buf.write(c);
      }
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}
