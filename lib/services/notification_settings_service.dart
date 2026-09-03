import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ── 通知設定（Cloud Functions側から参照するため users/{uid} に保存）──
class NotificationSettings {
  final bool notifyOnNewEvent;
  final bool notifyOnNewChatMessage;
  final bool remindersEnabled;
  final int  reminderMinutesBefore;

  const NotificationSettings({
    this.notifyOnNewEvent = true,
    this.notifyOnNewChatMessage = true,
    this.remindersEnabled = true,
    this.reminderMinutesBefore = 60,
  });

  factory NotificationSettings.fromMap(Map<String, dynamic>? d) => NotificationSettings(
    notifyOnNewEvent:       d?['notifyOnNewEvent'] ?? true,
    notifyOnNewChatMessage: d?['notifyOnNewChatMessage'] ?? true,
    remindersEnabled:       d?['remindersEnabled'] ?? true,
    reminderMinutesBefore:  d?['reminderMinutesBefore'] ?? 60,
  );
}

class NotificationSettingsService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  NotificationSettingsService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  Future<NotificationSettings> get() async {
    final doc = await _db.collection('users').doc(_uid).get();
    return NotificationSettings.fromMap(doc.data());
  }

  Future<void> setNotifyOnNewEvent(bool value) async {
    await _db.collection('users').doc(_uid).set(
      {'notifyOnNewEvent': value}, SetOptions(merge: true),
    );
  }

  Future<void> setNotifyOnNewChatMessage(bool value) async {
    await _db.collection('users').doc(_uid).set(
      {'notifyOnNewChatMessage': value}, SetOptions(merge: true),
    );
  }

  Future<void> setRemindersEnabled(bool value) async {
    await _db.collection('users').doc(_uid).set(
      {'remindersEnabled': value}, SetOptions(merge: true),
    );
  }

  Future<void> setReminderMinutesBefore(int minutes) async {
    await _db.collection('users').doc(_uid).set(
      {'reminderMinutesBefore': minutes}, SetOptions(merge: true),
    );
  }
}
