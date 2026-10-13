import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/home_tab_requests.dart';

void main() {
  group('HomeTabRequests', () {
    test('頼まれたタブは一度だけ取り出せる', () {
      final requests = HomeTabRequests();
      expect(requests.take(), isNull);

      requests.request(HomeTab.questions);
      expect(requests.take(), HomeTab.questions);
      expect(requests.take(), isNull);
    });

    test('同じタブを続けて頼んでも、そのたびに通知する', () {
      final requests = HomeTabRequests();
      var notified = 0;
      requests.addListener(() => notified++);

      requests.request(HomeTab.questions);
      requests.request(HomeTab.questions);

      expect(notified, 2);
    });

    test('タブの並びはホームの下部ナビと同じ', () {
      expect(HomeTab.values.map((t) => t.index), [0, 1, 2, 3]);
      expect(HomeTab.questions.index, 3);
    });
  });
}
