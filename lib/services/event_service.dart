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
      allDay:     event.allDay,
      visibility: event.visibility,
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
      // 記念日・有名人の誕生日・毎年繰り返しは時刻に意味が無いので終日扱い。
      // 従来Googleへ送るときに適用していた判定をここへ移した。
      allDay:    parsed.recurring ||
          parsed.type == EventType.anniversary ||
          parsed.type == EventType.celebrity,
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

  // ── 予定を削除（ゴミ箱へ）───────────────────────
  // 誤削除しても30日以内ならrestoreEventで戻せるよう、即座に消さず
  // deletedAtを立てるだけにする。実体はpurgeTrash（Cloud Functions）が
  // 保持期限を過ぎたものだけ完全に削除する。
  Future<void> deleteEvent(AimaruEvent event) async {
    await _eventsRef(event.coupleId).doc(event.id)
        .update({'deletedAt': FieldValue.serverTimestamp()});
  }

  // ── ゴミ箱から元に戻す ──────────────────────────
  Future<void> restoreEvent(AimaruEvent event) async {
    await _eventsRef(event.coupleId).doc(event.id).update({'deletedAt': null});
  }

  // ── ゴミ箱から完全に削除 ────────────────────────
  Future<void> permanentlyDeleteEvent(AimaruEvent event) async {
    await _eventsRef(event.coupleId).doc(event.id).delete();
  }

  // 論理削除済み（ゴミ箱）の予定を通常の一覧から取り除く。
  // deletedAtでのクエリ側フィルタは本番用の複合インデックスを別途
  // 用意する必要が出るため使わず、取得後にアプリ側で除く。
  List<AimaruEvent> _excludeDeleted(Iterable<AimaruEvent> events) =>
      events.where((e) => e.deletedAt == null).toList();

  // ── 月の予定を取得（リアルタイム）───────────────
  Stream<List<AimaruEvent>> watchMonthEvents(String coupleId, DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end   = DateTime(month.year, month.month + 1, 0, 23, 59);

    return _eventsRef(coupleId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('date')
        .snapshots()
        .map((snap) => _excludeDeleted(snap.docs.map(AimaruEvent.fromDoc)));
  }

  // ── 今後の予定を取得（リアルタイム）─────────────
  Stream<List<AimaruEvent>> watchUpcomingEvents(String coupleId, {int limit = 10}) {
    final now = DateTime.now();
    return _eventsRef(coupleId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('date')
        .limit(limit)
        .snapshots()
        .map((snap) => _excludeDeleted(snap.docs.map(AimaruEvent.fromDoc)));
  }

  // ── 毎年繰り返す予定（リアルタイム）─────────────
  // 誕生日や記念日は生年月日など過去の日付で登録されるため、
  // watchUpcomingEvents の「date >= now」では拾えない。発生日の算出は
  // 呼び出し側（utils/recurring_events.dart）で行う。
  Stream<List<AimaruEvent>> watchRecurringEvents(String coupleId) {
    return _eventsRef(coupleId)
        .where('recurring', isEqualTo: true)
        .snapshots()
        .map((snap) => _excludeDeleted(snap.docs.map(AimaruEvent.fromDoc)));
  }

  // ── 全予定をMapで取得（カレンダー用）────────────
  Stream<Map<DateTime, List<AimaruEvent>>> watchEventsAsMap(String coupleId) {
    return _eventsRef(coupleId)
        .orderBy('date')
        .snapshots()
        .map((snap) {
          final events = _excludeDeleted(snap.docs.map(AimaruEvent.fromDoc));
          final Map<DateTime, List<AimaruEvent>> map = {};
          for (final e in events) {
            final key = DateTime(e.date.year, e.date.month, e.date.day);
            map.putIfAbsent(key, () => []).add(e);
          }
          return map;
        });
  }

  // ── ゴミ箱の一覧（リアルタイム）─────────────────
  // 削除日時の新しい順。件数が多くなりにくい画面のため、
  // ここもアプリ側フィルタで揃える。
  Stream<List<AimaruEvent>> watchDeletedEvents(String coupleId) {
    return _eventsRef(coupleId)
        .snapshots()
        .map((snap) {
          final events = snap.docs
              .map(AimaruEvent.fromDoc)
              .where((e) => e.deletedAt != null)
              .toList()
            ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
          return events;
        });
  }
}
