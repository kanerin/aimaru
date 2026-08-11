import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class ChatService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  CollectionReference _chatsRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('chats');

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
}
