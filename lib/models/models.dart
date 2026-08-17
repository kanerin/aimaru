import 'package:cloud_firestore/cloud_firestore.dart';

// ── Couple（ペア情報）──────────────────────────────────
class CoupleModel {
  final String id;
  final List<String> memberIds;   // [userId1, userId2]
  final String inviteCode;
  final DateTime createdAt;
  final DateTime? anniversary;    // 付き合い始めた日

  // 基本の休日（DateTime.monday=1 〜 DateTime.sunday=7）。
  // 「2人の空き時間」はこの曜日だけを探索対象にする。
  // 平日休みの職種もあるため曜日は自由に選べるようにしてある。
  final List<int> daysOff;
  // 祝日も休みとして扱うか
  final bool holidaysAreDaysOff;

  // 未設定のカップルは土日休みとして扱う
  static const defaultDaysOff = <int>[DateTime.saturday, DateTime.sunday];

  CoupleModel({
    required this.id,
    required this.memberIds,
    required this.inviteCode,
    required this.createdAt,
    this.anniversary,
    this.daysOff = defaultDaysOff,
    this.holidaysAreDaysOff = true,
  });

  factory CoupleModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CoupleModel(
      id:          doc.id,
      memberIds:   List<String>.from(d['memberIds'] ?? []),
      inviteCode:  d['inviteCode'] ?? '',
      createdAt:   (d['createdAt'] as Timestamp).toDate(),
      anniversary: d['anniversary'] != null
          ? (d['anniversary'] as Timestamp).toDate()
          : null,
      // 既存のカップルにはこのフィールドが無いので既定値へフォールバックする
      daysOff: d['daysOff'] != null
          ? List<int>.from(d['daysOff'])
          : defaultDaysOff,
      holidaysAreDaysOff: d['holidaysAreDaysOff'] ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'memberIds':          memberIds,
    'inviteCode':         inviteCode,
    'createdAt':          Timestamp.fromDate(createdAt),
    'anniversary':        anniversary != null ? Timestamp.fromDate(anniversary!) : null,
    'daysOff':            daysOff,
    'holidaysAreDaysOff': holidaysAreDaysOff,
  };
}

// ── EventType ──────────────────────────────────────────
enum EventType {
  date,         // デート
  anniversary,  // 記念日
  celebrity,    // 有名人の誕生日（AI追加）
  plan,         // 未確定プラン
}

extension EventTypeExt on EventType {
  String get label => switch (this) {
    EventType.date        => 'デート',
    EventType.anniversary => '記念日',
    EventType.celebrity   => 'AI追加',
    EventType.plan        => 'プラン',
  };
  String get emoji => switch (this) {
    EventType.date        => '💕',
    EventType.anniversary => '🥂',
    EventType.celebrity   => '🌟',
    EventType.plan        => '📌',
  };
}

// ── AimaruEvent（予定）────────────────────────────────
class AimaruEvent {
  final String id;
  final String coupleId;
  final String title;
  final DateTime date;
  final DateTime? endDate;
  final EventType type;
  final String? location;
  final String? memo;
  final List<String> imageUrls;
  final String createdBy;         // userId
  final bool recurring;           // 毎年繰り返し
  final bool allDay;              // 終日（時刻を持たない）
  final String? googleCalendarEventId;
  // null以外なら論理削除済み（ゴミ箱）。deleteEvent/restoreEvent/
  // permanentlyDeleteEvent以外の経路（add/update）では触らない。
  final DateTime? deletedAt;

  AimaruEvent({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.date,
    this.endDate,
    required this.type,
    this.location,
    this.memo,
    this.imageUrls = const [],
    required this.createdBy,
    this.recurring = false,
    this.allDay = false,
    this.googleCalendarEventId,
    this.deletedAt,
  });

  factory AimaruEvent.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AimaruEvent(
      id:                    doc.id,
      coupleId:              d['coupleId'] ?? '',
      title:                 d['title'] ?? '',
      date:                  (d['date'] as Timestamp).toDate(),
      endDate:               d['endDate'] != null
          ? (d['endDate'] as Timestamp).toDate()
          : null,
      type:                  EventType.values.firstWhere(
          (e) => e.name == d['type'], orElse: () => EventType.plan),
      location:              d['location'],
      memo:                  d['memo'],
      imageUrls:             List<String>.from(d['imageUrls'] ?? []),
      createdBy:             d['createdBy'] ?? '',
      recurring:             d['recurring'] ?? false,
      // 既存の予定にはこのフィールドが無い。記念日・有名人の誕生日・毎年繰り返しは
      // 以前から終日としてGoogleへ送っていたので、その扱いを引き継ぐ。
      allDay:                d['allDay'] ??
          (d['recurring'] ?? false) ||
          d['type'] == 'anniversary' ||
          d['type'] == 'celebrity',
      googleCalendarEventId: d['googleCalendarEventId'],
      deletedAt:             d['deletedAt'] != null
          ? (d['deletedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'coupleId':              coupleId,
    'title':                 title,
    'date':                  Timestamp.fromDate(date),
    'endDate':               endDate != null ? Timestamp.fromDate(endDate!) : null,
    'type':                  type.name,
    'location':              location,
    'memo':                  memo,
    'imageUrls':             imageUrls,
    'createdBy':             createdBy,
    'recurring':             recurring,
    'allDay':                allDay,
    'googleCalendarEventId': googleCalendarEventId,
  };

  AimaruEvent copyWith({
    String? title, DateTime? date, DateTime? endDate, EventType? type,
    String? location, String? memo, List<String>? imageUrls,
    bool? recurring, bool? allDay, String? googleCalendarEventId,
  }) => AimaruEvent(
    id:                    id,
    coupleId:              coupleId,
    title:                 title ?? this.title,
    date:                  date ?? this.date,
    // endDateを引き継がないと、画像アップロードやGoogle同期のcopyWithを
    // 経由するたびに終了日時が消える
    endDate:               endDate ?? this.endDate,
    type:                  type ?? this.type,
    location:              location ?? this.location,
    memo:                  memo ?? this.memo,
    imageUrls:             imageUrls ?? this.imageUrls,
    createdBy:             createdBy,
    recurring:             recurring ?? this.recurring,
    allDay:                allDay ?? this.allDay,
    googleCalendarEventId: googleCalendarEventId ?? this.googleCalendarEventId,
  );
}

// ── ChatMessage ────────────────────────────────────────
class ChatMessage {
  final String id;
  final String coupleId;
  final String text;
  final String? imageUrl;
  final String senderId;
  final DateTime timestamp;
  final bool isAi;

  ChatMessage({
    required this.id,
    required this.coupleId,
    required this.text,
    this.imageUrl,
    required this.senderId,
    required this.timestamp,
    this.isAi = false,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id:        doc.id,
      coupleId:  d['coupleId'] ?? '',
      text:      d['text'] ?? '',
      imageUrl:  d['imageUrl'],
      senderId:  d['senderId'] ?? '',
      timestamp: (d['timestamp'] as Timestamp).toDate(),
      isAi:      d['isAi'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'coupleId':  coupleId,
    'text':      text,
    'imageUrl':  imageUrl,
    'senderId':  senderId,
    'timestamp': Timestamp.fromDate(timestamp),
    'isAi':      isAi,
  };
}

// ── GeminiParsedEvent（AI解析結果）────────────────────
class GeminiParsedEvent {
  final String title;
  final DateTime date;
  final EventType type;
  final bool recurring;
  final String? location;
  final String? memo;

  GeminiParsedEvent({
    required this.title,
    required this.date,
    required this.type,
    this.recurring = false,
    this.location,
    this.memo,
  });

  factory GeminiParsedEvent.fromJson(Map<String, dynamic> json) {
    return GeminiParsedEvent(
      title:     json['title'] ?? '',
      date:      DateTime.parse(json['date']),
      type:      EventType.values.firstWhere(
          (e) => e.name == json['type'], orElse: () => EventType.plan),
      recurring: json['recurring'] ?? false,
      location:  json['location'],
      memo:      json['memo'],
    );
  }
}

// ── TodoItem（共有TODO・やりたいことリスト）───────────
// 日付が決まっていないアイデアの置き場。予定に確定したら
// 別途カレンダーへ登録してもらう想定で、日付フィールドは持たない。
class TodoItem {
  final String id;
  final String coupleId;
  final String text;
  final bool done;
  final String createdBy;
  final DateTime createdAt;

  TodoItem({
    required this.id,
    required this.coupleId,
    required this.text,
    this.done = false,
    required this.createdBy,
    required this.createdAt,
  });

  factory TodoItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return TodoItem(
      id:        doc.id,
      coupleId:  d['coupleId'] ?? '',
      text:      d['text'] ?? '',
      done:      d['done'] ?? false,
      createdBy: d['createdBy'] ?? '',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'coupleId':  coupleId,
    'text':      text,
    'done':      done,
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

// ── GCalEventSummary（Googleカレンダーの予定の要約）───
// 自分/パートナーのGoogleカレンダーをカレンダー画面に重ねて
// 表示するための軽量なキャッシュ用モデル。
class GCalEventSummary {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  // Googleカレンダー側の場所・メモ。このアプリで作った予定と同じ項目を
  // Google由来の予定でも編集できるようにするために持つ
  // （AimaruEvent.location / memo に対応する）。
  final String? location;
  final String? memo;

  GCalEventSummary({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.memo,
  });

  Map<String, dynamic> toMap() => {
    'id':       id,
    'title':    title,
    'start':    Timestamp.fromDate(start),
    'end':      Timestamp.fromDate(end),
    'allDay':   allDay,
    'location': location,
    'memo':     memo,
  };

  factory GCalEventSummary.fromMap(Map<String, dynamic> map) => GCalEventSummary(
    id:     map['id'] ?? '',
    title:  map['title'] ?? '',
    start:  (map['start'] as Timestamp).toDate(),
    end:    (map['end'] as Timestamp).toDate(),
    allDay: map['allDay'] ?? false,
    // 以前のキャッシュにはこのフィールドが無いのでnull許容で読む
    location: map['location'] as String?,
    memo:     map['memo'] as String?,
  );
}

// ── ExpenseItem（割り勘・立て替えの記録）───────────────
// デート代や買い物の立て替えを記録し、どちらがいくら多く払っているかを
// 精算額として計算するための元データ。amountは円単位の整数。
class ExpenseItem {
  final String id;
  final String coupleId;
  final String title;
  final int amount;
  final String paidBy;
  final String createdBy;
  final DateTime createdAt;

  ExpenseItem({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.createdBy,
    required this.createdAt,
  });

  factory ExpenseItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ExpenseItem(
      id:        doc.id,
      coupleId:  d['coupleId'] ?? '',
      title:     d['title'] ?? '',
      amount:    (d['amount'] as num?)?.toInt() ?? 0,
      paidBy:    d['paidBy'] ?? '',
      createdBy: d['createdBy'] ?? '',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'coupleId':  coupleId,
    'title':     title,
    'amount':    amount,
    'paidBy':    paidBy,
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

// ── QuestionAnswer（デイリー質問への回答）───────────────
// TimeTreeには無い「お互いを知る」体験。日付ごとに固定の質問
// （lib/utils/daily_question_picker.dart）を出し、2人とも回答するまでは
// 相手の回答を伏せる（lib/screens/questions_screen.dart側の判定）ことで、
// 相手の回答に引っ張られない素直な回答を引き出す。
// idは'${dateKey}_$uid'（1人1日1件、上書き不可）。
class QuestionAnswer {
  final String id;
  final String coupleId;
  final String dateKey; // 'yyyy-MM-dd'
  final String uid;
  final String text;
  final DateTime createdAt;

  QuestionAnswer({
    required this.id,
    required this.coupleId,
    required this.dateKey,
    required this.uid,
    required this.text,
    required this.createdAt,
  });

  factory QuestionAnswer.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return QuestionAnswer(
      id:        doc.id,
      coupleId:  d['coupleId'] ?? '',
      dateKey:   d['dateKey'] ?? '',
      uid:       d['uid'] ?? '',
      text:      d['text'] ?? '',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'coupleId':  coupleId,
    'dateKey':   dateKey,
    'uid':       uid,
    'text':      text,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}
