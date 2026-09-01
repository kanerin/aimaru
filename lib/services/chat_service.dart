import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class ChatService {
  // Between・Pairyなど主要なカップルアプリはメッセージへのリアクション
  // （スタンプ的な絵文字反応）を持つが、AIMARUのトークはこれまで
  // テキストと画像を送るだけだった（2026年9月時点の競合調査）。
  static const List<String> quickReactionEmojis = ['❤️', '😂', '😮', '😢', '👍', '🙏'];

  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  ChatService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _chatsRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('chats');

  CollectionReference _readStatusRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('chatReadStatus');

  // ── メッセージを送信 ──────────────────────────────
  Future<void> sendMessage(String coupleId, {String? text, String? imageUrl}) async {
    final ref = _chatsRef(coupleId).doc();
    final message = ChatMessage(
      id:        ref.id,
      coupleId:  coupleId,
      text:      text ?? '',
      imageUrl:  imageUrl,
      senderId:  _uid,
      timestamp: DateTime.now(),
    );
    await ref.set(message.toMap());
  }

  // ── メッセージ一覧をリアルタイム取得 ──────────────
  Stream<List<ChatMessage>> watchMessages(String coupleId, {int limit = 100}) {
    return _chatsRef(coupleId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromDoc).toList().reversed.toList());
  }

  // ── 自分の最終既読時刻を更新 ───────────────────────
  Future<void> markAsRead(String coupleId) async {
    await _readStatusRef(coupleId).doc(_uid).set({
      'lastReadAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ── パートナーの最終既読時刻をリアルタイム取得 ─────
  Stream<DateTime?> watchPartnerLastReadAt(String coupleId, String partnerUid) {
    return _readStatusRef(coupleId).doc(partnerUid).snapshots().map((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      final ts = data?['lastReadAt'] as Timestamp?;
      return ts?.toDate();
    });
  }

  // ── 自分のリアクションを設定（同じ絵文字を選び直す場合はremoveReactionを使う）──
  Future<void> setReaction(String coupleId, String messageId, String emoji) async {
    await _chatsRef(coupleId).doc(messageId).update({'reactions.$_uid': emoji});
  }

  // ── 自分のリアクションを外す ──────────────────────
  Future<void> removeReaction(String coupleId, String messageId) async {
    await _chatsRef(coupleId).doc(messageId).update({'reactions.$_uid': FieldValue.delete()});
  }
}
