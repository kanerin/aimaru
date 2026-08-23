import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class EventCommentService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  EventCommentService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _commentsRef(String coupleId, String eventId) => _db
      .collection('couples').doc(coupleId)
      .collection('events').doc(eventId)
      .collection('comments');

  // ── コメントを追加 ────────────────────────────────
  Future<void> addComment(String coupleId, String eventId, String text) async {
    final ref = _commentsRef(coupleId, eventId).doc();
    final comment = EventComment(
      id:        ref.id,
      coupleId:  coupleId,
      eventId:   eventId,
      text:      text,
      senderId:  _uid,
      createdAt: DateTime.now(),
    );
    await ref.set(comment.toMap());
  }

  // ── コメント一覧をリアルタイム取得（古い順）───────
  Stream<List<EventComment>> watchComments(String coupleId, String eventId) {
    return _commentsRef(coupleId, eventId)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map(EventComment.fromDoc).toList());
  }
}
