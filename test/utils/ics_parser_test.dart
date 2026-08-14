import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/utils/ics_parser.dart';

void main() {
  test('日時指定のVEVENTを1件パースできる', () {
    const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:1@example.com
DTSTART:20260115T090000Z
DTEND:20260115T100000Z
SUMMARY:歯医者
LOCATION:駅前クリニック
END:VEVENT
END:VCALENDAR
''';

    final events = parseIcsEvents(ics);
    expect(events, hasLength(1));
    expect(events.first.title, '歯医者');
    expect(events.first.allDay, isFalse);
    expect(events.first.location, '駅前クリニック');
    expect(events.first.start.toUtc(), DateTime.utc(2026, 1, 15, 9, 0, 0));
    expect(events.first.end?.toUtc(), DateTime.utc(2026, 1, 15, 10, 0, 0));
  });

  test('VALUE=DATEの終日予定をパースできる', () {
    const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART;VALUE=DATE:20260220
DTEND;VALUE=DATE:20260221
SUMMARY:記念日
END:VEVENT
END:VCALENDAR
''';

    final events = parseIcsEvents(ics);
    expect(events, hasLength(1));
    expect(events.first.allDay, isTrue);
    expect(events.first.start, DateTime(2026, 2, 20));
  });

  test('複数のVEVENTをすべて拾う', () {
    const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART:20260101T000000Z
SUMMARY:予定A
END:VEVENT
BEGIN:VEVENT
DTSTART:20260102T000000Z
SUMMARY:予定B
END:VEVENT
END:VCALENDAR
''';

    final events = parseIcsEvents(ics);
    expect(events.map((e) => e.title), ['予定A', '予定B']);
  });

  test('折り返された行を結合してから読む', () {
    const ics = 'BEGIN:VCALENDAR\r\n'
        'BEGIN:VEVENT\r\n'
        'DTSTART:20260101T000000Z\r\n'
        'SUMMARY:とても長い\r\n'
        ' タイトル\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';

    final events = parseIcsEvents(ics);
    expect(events.single.title, 'とても長いタイトル');
  });

  test('エスケープされた特殊文字を復元する', () {
    const ics = r'''
BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART:20260101T000000Z
SUMMARY:カフェ\, パン屋\; 本屋
DESCRIPTION:1行目\n2行目
END:VEVENT
END:VCALENDAR
''';

    final events = parseIcsEvents(ics);
    expect(events.single.title, 'カフェ, パン屋; 本屋');
    expect(events.single.description, '1行目\n2行目');
  });

  test('SUMMARYが無い場合はタイトルなし扱いにする', () {
    const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART:20260101T000000Z
END:VEVENT
END:VCALENDAR
''';

    final events = parseIcsEvents(ics);
    expect(events.single.title, '(タイトルなし)');
  });

  test('DTSTARTが無いVEVENTは読み飛ばす', () {
    const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:日付なし
END:VEVENT
BEGIN:VEVENT
DTSTART:20260101T000000Z
SUMMARY:予定あり
END:VEVENT
END:VCALENDAR
''';

    final events = parseIcsEvents(ics);
    expect(events.map((e) => e.title), ['予定あり']);
  });

  test('VEVENTが1つも無ければ空リストを返す', () {
    const ics = 'BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n';
    expect(parseIcsEvents(ics), isEmpty);
  });
}
