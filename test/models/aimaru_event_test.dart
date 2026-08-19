import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';

// AimaruEvent の copyWith と allDay の既定値を検証する。
//
// copyWith は保存経路の途中（画像アップロード後・Googleカレンダー同期後）で
// 呼ばれるため、ここでフィールドを落とすと「入力したのに保存されない」に
// 直結する。実際に endDate がそうなっていた。
void main() {
  AimaruEvent build({
    DateTime? endDate,
    bool allDay = false,
    bool recurring = false,
  }) =>
      AimaruEvent(
        id: 'e1',
        coupleId: 'couple-1',
        title: 'デート',
        date: DateTime(2026, 8, 14, 22, 0),
        endDate: endDate,
        type: EventType.date,
        createdBy: 'user-me',
        recurring: recurring,
        allDay: allDay,
      );

  group('copyWith', () {
    test('imageUrlsだけを差し替えても終了日時が残る', () {
      final e = build(endDate: DateTime(2026, 8, 15, 2, 0));

      final copied = e.copyWith(imageUrls: ['https://example.com/a.jpg']);

      expect(copied.endDate, DateTime(2026, 8, 15, 2, 0));
      expect(copied.imageUrls, ['https://example.com/a.jpg']);
    });

    test('googleCalendarEventIdだけを差し替えても終了日時が残る', () {
      final e = build(endDate: DateTime(2026, 8, 15, 2, 0));

      final copied = e.copyWith(googleCalendarEventId: 'gcal-1');

      expect(copied.endDate, DateTime(2026, 8, 15, 2, 0));
      expect(copied.googleCalendarEventId, 'gcal-1');
    });

    test('終日フラグも引き継がれる', () {
      final e = build(allDay: true);

      expect(e.copyWith(imageUrls: const []).allDay, isTrue);
    });

    test('endDateを明示すれば上書きできる', () {
      final e = build(endDate: DateTime(2026, 8, 15, 2, 0));

      final copied = e.copyWith(endDate: DateTime(2026, 8, 16, 3, 0));

      expect(copied.endDate, DateTime(2026, 8, 16, 3, 0));
    });

    test('visibilityを指定しなければsharedのまま引き継がれる', () {
      final e = build();

      expect(e.copyWith(title: '別の予定').visibility, EventVisibility.shared);
    });

    test('visibilityを明示すれば上書きできる', () {
      final e = build();

      final copied = e.copyWith(visibility: EventVisibility.private);

      expect(copied.visibility, EventVisibility.private);
    });
  });

  group('visibilityの既定値', () {
    // 課題3フェーズ1: フィールドを追加しただけでまだ enforce していないため、
    // 未指定ならsharedへ倒れることだけを確認する。
    test('未指定ならsharedになる', () {
      expect(build().visibility, EventVisibility.shared);
    });
  });

  group('allDay の後方互換', () {
    // allDay を持たない既存ドキュメントは、以前Googleへ送るときに使っていた
    // 判定（毎年繰り返し / 記念日 / 有名人の誕生日）を引き継ぐ。
    Map<String, dynamic> doc({
      required String type,
      bool recurring = false,
      bool? allDay,
    }) => {
      'coupleId': 'couple-1',
      'title': 'x',
      'date': DateTime(2026, 8, 14, 22, 0),
      'type': type,
      'createdBy': 'user-me',
      'recurring': recurring,
      if (allDay != null) 'allDay': allDay,
    };

    // fromDoc は DocumentSnapshot を取るため、判定式そのものを同じ形で確認する。
    bool legacyAllDay(Map<String, dynamic> d) =>
        d['allDay'] ??
        (d['recurring'] ?? false) ||
            d['type'] == 'anniversary' ||
            d['type'] == 'celebrity';

    test('記念日と有名人の誕生日、毎年繰り返しは終日として扱う', () {
      expect(legacyAllDay(doc(type: 'anniversary')), isTrue);
      expect(legacyAllDay(doc(type: 'celebrity')), isTrue);
      expect(legacyAllDay(doc(type: 'date', recurring: true)), isTrue);
    });

    test('通常のデートは終日にしない', () {
      expect(legacyAllDay(doc(type: 'date')), isFalse);
      expect(legacyAllDay(doc(type: 'plan')), isFalse);
    });

    test('allDayが保存されていればそちらを優先する', () {
      expect(legacyAllDay(doc(type: 'anniversary', allDay: false)), isFalse);
      expect(legacyAllDay(doc(type: 'date', allDay: true)), isTrue);
    });
  });
}
