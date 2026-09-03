import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/notification_settings_service.dart';

// 通知設定（users/{uid}）の読み書きを、Firebaseに接続せず検証する。
void main() {
  late FakeFirebaseFirestore db;
  late NotificationSettingsService service;

  const meUid = 'user-me';

  setUp(() {
    db = FakeFirebaseFirestore();
    service = NotificationSettingsService(firestore: db, uid: meUid);
  });

  group('get', () {
    test('未設定の場合は全てデフォルト値（有効・60分前）', () async {
      final settings = await service.get();

      expect(settings.notifyOnNewEvent, isTrue);
      expect(settings.notifyOnNewChatMessage, isTrue);
      expect(settings.notifyOnDailyQuestion, isTrue);
      expect(settings.remindersEnabled, isTrue);
      expect(settings.reminderMinutesBefore, 60);
    });
  });

  group('setNotifyOnNewEvent', () {
    test('falseにするとgetでも反映される', () async {
      await service.setNotifyOnNewEvent(false);

      expect((await service.get()).notifyOnNewEvent, isFalse);
    });
  });

  group('setNotifyOnNewChatMessage', () {
    test('falseにするとgetでも反映される', () async {
      await service.setNotifyOnNewChatMessage(false);

      final settings = await service.get();
      expect(settings.notifyOnNewChatMessage, isFalse);
      // 他の設定には影響しない
      expect(settings.notifyOnNewEvent, isTrue);
    });
  });

  group('setNotifyOnDailyQuestion', () {
    test('falseにするとgetでも反映される', () async {
      await service.setNotifyOnDailyQuestion(false);

      final settings = await service.get();
      expect(settings.notifyOnDailyQuestion, isFalse);
      // 他の設定には影響しない
      expect(settings.notifyOnNewEvent, isTrue);
    });
  });

  group('setRemindersEnabled', () {
    test('falseにするとgetでも反映される', () async {
      await service.setRemindersEnabled(false);

      expect((await service.get()).remindersEnabled, isFalse);
    });
  });

  group('setReminderMinutesBefore', () {
    test('指定した分数がgetでも反映される', () async {
      await service.setReminderMinutesBefore(15);

      expect((await service.get()).reminderMinutesBefore, 15);
    });
  });
}
