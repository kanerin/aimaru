import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

// ── Googleカレンダーの予定を couples/{coupleId} 配下にキャッシュし、
//    自分とパートナーの端末間で共有するためのサービス。
//    各端末は「自分自身のGoogleカレンダー」だけを取得し、
//    ここに書き込む。相手の予定は相手の端末が書き込んだキャッシュを読むだけ
//    （Googleの認証情報を共有する必要はない）。
class GoogleCalendarCacheService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  CollectionReference _cacheRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('googleCalendarCache');

  // ── 自分のGoogleカレンダーの予定をキャッシュに反映 ──
  Future<void> pushMyEvents(String coupleId, List<GCalEventSummary> events) async {
    await _cacheRef(coupleId).doc(_uid).set({
      'events':    events.map((e) => e.toMap()).toList(),
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
