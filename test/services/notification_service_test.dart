import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/notification_service.dart';

// 通知タップ時の遷移先の振り分け。ふたりの質問の通知だけ質問画面へ飛び、
// それ以外（予定・チャット・リマインダーなど）は従来どおりホームへ飛ぶ。
void main() {
  group('routeForNotificationData', () {
    test('ふたりの質問の通知は質問画面へ', () {
      expect(
        routeForNotificationData({'type': 'question', 'coupleId': 'couple-1'}),
        '/home/questions',
      );
    });

    test('予定・チャット・リマインダー・記念日の通知はホームへ', () {
      for (final type in ['new_event', 'new_chat_message', 'reminder', 'anniversary']) {
        expect(routeForNotificationData({'type': type}), '/home', reason: type);
      }
    });

    test('typeが無い・未知の通知もホームへ', () {
      expect(routeForNotificationData({}), '/home');
      expect(routeForNotificationData({'type': 'unknown'}), '/home');
    });
  });
}
