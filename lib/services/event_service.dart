import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class EventService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  EventService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _eventsRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('events');

  // 新規作成時にセットするリマインダー管理用フィールド。
  // reminded: 単発の予定用（送信後にCloud Functions側でtrueにする）
  // remindedYear: recurring（毎年繰り返し）の予定用。送信済みの年を記録する
  static const _freshReminderFields = {'reminded': false, 'remindedYear': null};

  // ── 予定を追加 ────────────────────────────────────
  Future<AimaruEvent> addEvent(String coupleId, AimaruEvent event) async {
    final ref = _eventsRef(coupleId).doc();
    final newEvent = AimaruEvent(
      id:         ref.id,
      coupleId:   coupleId,
      title:      event.title,
      date:       event.date,
      endDate:    event.endDate,
      type:       event.type,
      location:   event.location,
      memo:       event.memo,
      imageUrls:  event.imageUrls,
      createdBy:  _uid,
      recurring:  event.recurring,
    );
    await ref.set({...newEvent.toMap(), ..._freshReminderFields});
    return newEvent;
  }

  // ── GeminiParsedEvent から追加 ────────────────────
  Future<AimaruEvent> addFromGemini(String coupleId, GeminiParsedEvent parsed) async {
    final ref = _eventsRef(coupleId).doc();
    final event = AimaruEvent(
      id:        ref.id,
      coupleId:  coupleId,
      title:     parsed.title,
      date:      parsed.date,
      type:      parsed.type,
      location:  parsed.location,
      memo:      parsed.memo,
      createdBy: _uid,
      recurring: parsed.recurring,
    );
    await ref.set({...event.toMap(), ..._freshReminderFields});
    return event;
  }

  // ── 予定を更新 ────────────────────────────────────
  Future<void> updateEvent(AimaruEvent event) async {
    // 日時が変わった場合に古いリマインダー状態が残らないよう、
    // 更新のたびにリマインダー管理用フィールドをリセットする
    await _eventsRef(event.coupleId).doc(event.id)
        .update({...event.toMap(), ..._freshReminderFields});
  }

  // ── 予定を削除 ────────────────────────────────────
  Future<void> deleteEvent(AimaruEvent event) async {
    await _eventsRef(event.coupleId).doc(event.id).delete();
  }

  // ── 月の予定を取得（リアルタイム）───────────────
  Stream<List<AimaruEvent>> watchMonthEvents(String coupleId, DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end   = DateTime(month.year, month.month + 1, 0, 23, 59);

    return _eventsRef(coupleId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs.map(AimaruEvent.fromDoc).toList());
  }

  // ── 今後の予定を取得（リアルタイム）─────────────
  Stream<List<AimaruEvent>> watchUpcomingEvents(String coupleId, {int limit = 10}) {
    final now = DateTime.now();
    return _eventsRef(coupleId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('date')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(AimaruEvent.fromDoc).toList());
  }

  // ── 全予定をMapで取得（カレンダー用）────────────
  Stream<Map<DateTime, List<AimaruEvent>>> watchEventsAsMap(String coupleId) {
    return _eventsRef(coupleId)
        .orderBy('date')
        .snapshots()
        .map((snap) {
          final events = snap.docs.map(AimaruEvent.fromDoc).toList();
          final Map<DateTime, List<AimaruEvent>> map = {};
          for (final e in events) {
            final key = DateTime(e.date.year, e.date.month, e.date.day);
            map.putIfAbsent(key, () => []).add(e);
          }
          return map;
        });
  }
}
