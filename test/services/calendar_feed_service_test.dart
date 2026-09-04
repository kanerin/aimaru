import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/calendar_feed_service.dart';

// CalendarFeedServiceは実際のFirebase呼び出しをinvokeGet/invokeRegenerateに
// 差し込むことでバイパスできるようにしてある。ここではネットワーク・
// エミュレータのどちらにも触れず、サーバーの応答（url）を正しく取り出せることと、
// 取得・作り直しでそれぞれ正しいCallable呼び出しに対応することを検証する。
void main() {
  group('CalendarFeedService.fetchUrl', () {
    test('サーバーが返したurlをそのまま返す', () async {
      var called = false;
      final service = CalendarFeedService(
        invokeGet: () async {
          called = true;
          return {'url': 'https://us-central1-aimaru-7eb2e.cloudfunctions.net/calendarFeed?uid=u1&token=t1'};
        },
        invokeRegenerate: () async => throw StateError('呼ばれないはず'),
      );

      final url = await service.fetchUrl();

      expect(called, isTrue);
      expect(url, 'https://us-central1-aimaru-7eb2e.cloudfunctions.net/calendarFeed?uid=u1&token=t1');
    });

    test('サーバー呼び出しが失敗したら例外がそのまま伝播する', () async {
      final service = CalendarFeedService(
        invokeGet: () async => throw Exception('network error'),
        invokeRegenerate: () async => throw StateError('呼ばれないはず'),
      );

      await expectLater(service.fetchUrl(), throwsException);
    });
  });

  group('CalendarFeedService.regenerateUrl', () {
    test('取得とは別のCallableを呼び、新しいurlを返す', () async {
      var getCalled = false;
      var regenerateCalled = false;
      final service = CalendarFeedService(
        invokeGet: () async {
          getCalled = true;
          return {'url': 'https://example.com/old'};
        },
        invokeRegenerate: () async {
          regenerateCalled = true;
          return {'url': 'https://us-central1-aimaru-7eb2e.cloudfunctions.net/calendarFeed?uid=u1&token=t2'};
        },
      );

      final url = await service.regenerateUrl();

      expect(regenerateCalled, isTrue);
      expect(getCalled, isFalse);
      expect(url, 'https://us-central1-aimaru-7eb2e.cloudfunctions.net/calendarFeed?uid=u1&token=t2');
    });
  });
}
