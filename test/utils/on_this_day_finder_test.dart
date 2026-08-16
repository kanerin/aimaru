import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/utils/on_this_day_finder.dart';

void main() {
  AimaruEvent buildEvent({
    required String id,
    required DateTime date,
    DateTime? deletedAt,
  }) =>
      AimaruEvent(
        id: id,
        coupleId: 'couple-1',
        title: 'イベント$id',
        date: date,
        type: EventType.date,
        createdBy: 'u1',
        deletedAt: deletedAt,
      );

  group('findOnThisDayMemories', () {
    test('月日が一致する過去の予定を拾う', () {
      final events = [
        buildEvent(id: 'a', date: DateTime(2024, 8, 16)),
        buildEvent(id: 'b', date: DateTime(2023, 8, 16)),
        buildEvent(id: 'c', date: DateTime(2024, 8, 17)), // 日が違う
      ];

      final result = findOnThisDayMemories(events, DateTime(2026, 8, 16));

      expect(result.map((m) => m.event.id), ['a', 'b']);
      expect(result.map((m) => m.yearsAgo), [2, 3]);
    });

    test('同じ年・未来の予定は含めない', () {
      final events = [
        buildEvent(id: 'today', date: DateTime(2026, 8, 16)),
        buildEvent(id: 'future', date: DateTime(2027, 8, 16)),
      ];

      final result = findOnThisDayMemories(events, DateTime(2026, 8, 16));

      expect(result, isEmpty);
    });

    test('ゴミ箱（論理削除済み）の予定は含めない', () {
      final events = [
        buildEvent(id: 'trashed', date: DateTime(2024, 8, 16), deletedAt: DateTime(2026, 1, 1)),
      ];

      final result = findOnThisDayMemories(events, DateTime(2026, 8, 16));

      expect(result, isEmpty);
    });

    test('一致する予定が無ければ空リスト', () {
      final events = [buildEvent(id: 'a', date: DateTime(2024, 1, 1))];

      final result = findOnThisDayMemories(events, DateTime(2026, 8, 16));

      expect(result, isEmpty);
    });

    test('年が近い順（yearsAgoが小さい順）に並ぶ', () {
      final events = [
        buildEvent(id: 'old', date: DateTime(2020, 8, 16)),
        buildEvent(id: 'recent', date: DateTime(2025, 8, 16)),
      ];

      final result = findOnThisDayMemories(events, DateTime(2026, 8, 16));

      expect(result.map((m) => m.event.id), ['recent', 'old']);
    });
  });
}
