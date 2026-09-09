import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

// ── データエクスポート ────────────────────────────────
// カップルで共有しているデータ（予定・思い出＝写真付きの予定・チャット・
// やりたいことリスト・ふたりの質問への回答・ふたりの日記・家事分担・
// きょうの気分・ほしいものリスト）をJSONとして書き出す。
// AIMARUはカップル2人で作るデータなので、片方の視点だけを切り出すのではなく、
// カップル全体の共有データをそのまま対象にする。
//
// ゴミ箱（論理削除済み）の予定は含めない。保持期間中は復元されうる
// 「削除操作の取り消し可能な状態」であり、ユーザーが「自分のデータ」として
// 持ち出したいものではないという判断（trash_screen.dartでも通常の一覧からは
// 隠している）。
class DataExportService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore を差し込んでFirebaseに触れずに検証する。
  DataExportService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// coupleIdのデータを整形済みJSON文字列として返す。
  Future<String> exportAsJson(String coupleId) async {
    final coupleRef = _db.collection('couples').doc(coupleId);

    final results = await Future.wait([
      coupleRef.collection('events').get(),
      coupleRef.collection('chats').orderBy('timestamp').get(),
      coupleRef.collection('todos').get(),
      coupleRef.collection('questionAnswers').get(),
      coupleRef.collection('diaryEntries').get(),
      coupleRef.collection('chores').get(),
      coupleRef.collection('shoppingItems').get(),
      coupleRef.collection('moodEntries').get(),
      coupleRef.collection('wishlistItems').get(),
    ]);

    final events = results[0].docs
        .map(AimaruEvent.fromDoc)
        .where((e) => e.deletedAt == null)
        .map(_eventToJson)
        .toList();
    final chats = results[1].docs.map(ChatMessage.fromDoc).map(_chatToJson).toList();
    final todos = results[2].docs.map(TodoItem.fromDoc).map(_todoToJson).toList();
    final questionAnswers =
        results[3].docs.map(QuestionAnswer.fromDoc).map(_answerToJson).toList();
    final diaryEntries =
        results[4].docs.map(DiaryEntry.fromDoc).map(_diaryEntryToJson).toList();
    final chores = results[5].docs.map(ChoreItem.fromDoc).map(_choreToJson).toList();
    final shoppingItems =
        results[6].docs.map(ShoppingItem.fromDoc).map(_shoppingItemToJson).toList();
    final moodEntries =
        results[7].docs.map(MoodEntry.fromDoc).map(_moodEntryToJson).toList();
    // 予約状態（wishlistReservations）はサプライズを壊さないためあえて
    // 対象外にする。追加した本人がエクスポートすると相手の予約状況を
    // 読めてしまい、firestore.rulesで隠している意味が無くなるため。
    final wishlistItems =
        results[8].docs.map(WishlistItem.fromDoc).map(_wishlistItemToJson).toList();

    final data = {
      'exportedAt': DateTime.now().toIso8601String(),
      'coupleId': coupleId,
      'events': events,
      'chats': chats,
      'todos': todos,
      'questionAnswers': questionAnswers,
      'diaryEntries': diaryEntries,
      'chores': chores,
      'shoppingItems': shoppingItems,
      'moodEntries': moodEntries,
      'wishlistItems': wishlistItems,
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Map<String, dynamic> _eventToJson(AimaruEvent e) => {
    'id': e.id,
    'title': e.title,
    'date': e.date.toIso8601String(),
    'endDate': e.endDate?.toIso8601String(),
    'type': e.type.name,
    'location': e.location,
    'memo': e.memo,
    'imageUrls': e.imageUrls,
    'createdBy': e.createdBy,
    'recurring': e.recurring,
    'allDay': e.allDay,
  };

  Map<String, dynamic> _chatToJson(ChatMessage m) => {
    'id': m.id,
    'text': m.text,
    'imageUrl': m.imageUrl,
    'senderId': m.senderId,
    'timestamp': m.timestamp.toIso8601String(),
    'isAi': m.isAi,
  };

  Map<String, dynamic> _todoToJson(TodoItem t) => {
    'id': t.id,
    'text': t.text,
    'done': t.done,
    'createdBy': t.createdBy,
    'createdAt': t.createdAt.toIso8601String(),
  };

  Map<String, dynamic> _answerToJson(QuestionAnswer a) => {
    'id': a.id,
    'dateKey': a.dateKey,
    'uid': a.uid,
    'text': a.text,
    'createdAt': a.createdAt.toIso8601String(),
  };

  Map<String, dynamic> _diaryEntryToJson(DiaryEntry d) => {
    'id': d.id,
    'dateKey': d.dateKey,
    'uid': d.uid,
    'text': d.text,
    'createdAt': d.createdAt.toIso8601String(),
    'updatedAt': d.updatedAt.toIso8601String(),
  };

  Map<String, dynamic> _choreToJson(ChoreItem c) => {
    'id': c.id,
    'title': c.title,
    'assignedTo': c.assignedTo,
    'done': c.done,
    'createdBy': c.createdBy,
    'createdAt': c.createdAt.toIso8601String(),
  };

  Map<String, dynamic> _shoppingItemToJson(ShoppingItem s) => {
    'id': s.id,
    'title': s.title,
    'quantity': s.quantity,
    'done': s.done,
    'createdBy': s.createdBy,
    'createdAt': s.createdAt.toIso8601String(),
  };

  Map<String, dynamic> _moodEntryToJson(MoodEntry m) => {
    'id': m.id,
    'dateKey': m.dateKey,
    'uid': m.uid,
    'mood': m.mood,
    'createdAt': m.createdAt.toIso8601String(),
  };

  Map<String, dynamic> _wishlistItemToJson(WishlistItem w) => {
    'id': w.id,
    'text': w.text,
    'url': w.url,
    'addedBy': w.addedBy,
    'createdAt': w.createdAt.toIso8601String(),
  };
}
