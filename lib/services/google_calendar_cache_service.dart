import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

// ── Googleカレンダーの予定を couples/{coupleId} 配下にキャッシュし、
//    自分とパートナーの端末間で共有するためのサービス。
//    各端末は「自分自身のGoogleカレンダー」だけを取得し、
//    ここに書き込む。相手の予定は相手の端末が書き込んだキャッシュを読むだけ
//    （Googleの認証情報を共有する必要はない）。
class GoogleCalendarCacheService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  GoogleCalendarCacheService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _cacheRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('googleCalendarCache');

  CollectionReference _visibilityRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('googleEventVisibility');

  // ── パートナーに見せたくないGoogle予定として指定/解除する ──
  // Googleカレンダー自体にこの概念が無いため、AIMARU側で別途持つ。
  // 次のpushMyEvents（自動同期、またはこの直後の呼び出し）で
  // googleCalendarCache側のvisibilityへ反映されるまでは、古い値のまま残る。
  Future<void> setEventPrivate(String coupleId, String eventId, bool private) async {
    final ref = _visibilityRef(coupleId).doc(_uid);
    await ref.set({
      'privateEventIds':
          private ? FieldValue.arrayUnion([eventId]) : FieldValue.arrayRemove([eventId]),
    }, SetOptions(merge: true));
  }

  Future<Set<String>> _myPrivateEventIds(String coupleId) async {
    final doc = await _visibilityRef(coupleId).doc(_uid).get();
    final data = doc.data() as Map<String, dynamic>?;
    return Set<String>.from(data?['privateEventIds'] as List? ?? []);
  }

  // ── 自分のGoogleカレンダーの予定をキャッシュに反映 ──
  // fetchEventsはGoogle側から毎回取り直した値（visibilityの概念を持たない）
  // なので、書き込む直前にgoogleEventVisibilityの指定をここで上書きする。
  Future<void> pushMyEvents(String coupleId, List<GCalEventSummary> events) async {
    final privateIds = await _myPrivateEventIds(coupleId);
    final stamped = events
        .map((e) => GCalEventSummary(
              id: e.id,
              title: e.title,
              start: e.start,
              end: e.end,
              allDay: e.allDay,
              location: e.location,
              memo: e.memo,
              visibility:
                  privateIds.contains(e.id) ? EventVisibility.private : EventVisibility.shared,
            ))
        .toList();

    await _cacheRef(coupleId).doc(_uid).set({
      'events':    stamped.map((e) => e.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Googleカレンダー連携をオフにした場合にキャッシュを消す ──
  Future<void> clearMyEvents(String coupleId) async {
    await _cacheRef(coupleId).doc(_uid).delete();
  }

  // ── カップル全員分（自分+パートナー）のキャッシュを購読 ──
  // key: uid, value: その人のGoogleカレンダー予定一覧
  Stream<Map<String, List<GCalEventSummary>>> watchAll(String coupleId) {
    return _cacheRef(coupleId).snapshots().map((snap) {
      final map = <String, List<GCalEventSummary>>{};
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final list = (data['events'] as List? ?? [])
            .map((e) => GCalEventSummary.fromMap(e as Map<String, dynamic>))
            .toList();
        map[doc.id] = list;
      }
      return map;
    });
  }
}
