import 'package:cloud_firestore/cloud_firestore.dart';

// ── Couple（ペア情報）──────────────────────────────────
class CoupleModel {
  final String id;
  final List<String> memberIds;   // [userId1, userId2]
  final String inviteCode;
  final DateTime createdAt;
  final DateTime? anniversary;    // 付き合い始めた日
  final DateTime? nextMeetingDate; // 次に会う予定の日

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
    this.nextMeetingDate,
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
      nextMeetingDate: d['nextMeetingDate'] != null
          ? (d['nextMeetingDate'] as Timestamp).toDate()
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
    'nextMeetingDate':    nextMeetingDate != null ? Timestamp.fromDate(nextMeetingDate!) : null,
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

// ── EventVisibility ────────────────────────────────────
// 課題3（予定ごとの共有範囲）フェーズ1: スキーマにフィールドだけ用意する。
// Firestoreルールでの読み取り制限・クエリの分割・UIでの切り替えは
// まだ実装していない（既存の全予定取得クエリにvisibilityでの絞り込みを
// 加えると新しい複合索引が要るが、firestore.indexes.jsonの本番デプロイは
// IAM未付与で失敗し続けており（docs/open-issues.md 課題8）、
// カレンダーの主要クエリでそれをやると本番の全ユーザーの表示が壊れる。
// IAM解決後にフェーズ2でルール・クエリ・UIを実装する）。
// それまでは全予定がsharedと同じ扱い（両者に見える）のまま。
enum EventVisibility {
  shared,  // ふたりとも見える（既定）
  private, // 自分だけ見える（未enforced。フェーズ2で対応）
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
  final EventVisibility visibility;

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
    this.visibility = EventVisibility.shared,
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
      // 既存の予定にはこのフィールドが無いのでsharedへフォールバックする
      visibility:            EventVisibility.values.firstWhere(
          (v) => v.name == d['visibility'], orElse: () => EventVisibility.shared),
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
    'visibility':            visibility.name,
  };

  AimaruEvent copyWith({
    String? title, DateTime? date, DateTime? endDate, EventType? type,
    String? location, String? memo, List<String>? imageUrls,
    bool? recurring, bool? allDay, String? googleCalendarEventId,
    EventVisibility? visibility,
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
    visibility:            visibility ?? this.visibility,
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

// ── AnniversaryItem（複数記念日）────────────────────────
// CoupleModel.anniversary（付き合い始めた日）は1件しか持てないが、
// プロポーズ・入籍・初デートなど、カップルは複数の記念日を追いたいことが多い
// （TimeTreeにはこの概念自体が無く、Pairyの移行先として比較される
// Between・Twinest等が複数記念日の登録・カウントダウンを持つ）。
// 表示側はlib/utils/anniversary_calculator.dartのsummarizeAnniversaryを
// そのまま再利用し、日付ごとの経過日数・次の周年までの日数を計算する。
class AnniversaryItem {
  final String id;
  final String coupleId;
  final String title;
  final DateTime date;
  final String createdBy;
  final DateTime createdAt;

  AnniversaryItem({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.date,
    required this.createdBy,
    required this.createdAt,
  });

  factory AnniversaryItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AnniversaryItem(
      id:        doc.id,
      coupleId:  d['coupleId'] ?? '',
      title:     d['title'] ?? '',
      date:      (d['date'] as Timestamp).toDate(),
      createdBy: d['createdBy'] ?? '',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'coupleId':  coupleId,
    'title':     title,
    'date':      Timestamp.fromDate(date),
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

// ── BugReportRecord（自分が送ったバグ報告・機能要望の状況）────────
// submitBugReport（Cloud Functions）が書き込んだドキュメントを、
// 送信者本人だけがfirestore.rulesで読める（他人の報告は見えない）。
// statusは pending（未着手）/ in_progress（対応中）/ done（対応済み）/
// rejected（見送り）のいずれか。
class BugReportRecord {
  final String id;
  final String summary;
  final String classification; // 'bug' | 'feature_request'
  final String status; // 'pending' | 'in_progress' | 'done' | 'rejected'
  final DateTime createdAt;
  final int? prNumber;
  // statusが'rejected'のときだけ入る、大まかな見送り理由の分類。
  // 詳細な文章ではなく固定の分類（rejectCategoryLabelで日本語ラベルにする）。
  final String? rejectCategory;

  BugReportRecord({
    required this.id,
    required this.summary,
    required this.classification,
    required this.status,
    required this.createdAt,
    this.prNumber,
    this.rejectCategory,
  });

  factory BugReportRecord.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return BugReportRecord(
      id:             doc.id,
      summary:        d['summary'] ?? '',
      classification: d['classification'] ?? '',
      status:         d['status'] ?? 'pending',
      createdAt:      (d['createdAt'] as Timestamp).toDate(),
      prNumber:       d['prNumber'] as int?,
      rejectCategory: d['rejectCategory'] as String?,
    );
  }
}

// rejectCategoryの固定値と日本語ラベルの対応。
// functions/scripts/mark-bug-report-status.mjs / .claude/commands/fix-bug-reports.md
// と一致させること。
const Map<String, String> bugReportRejectCategoryLabels = {
  'already_done': 'すでに対応済みの内容でした',
  'unclear': '内容を具体化できませんでした',
  'out_of_scope': '自動実装の対象外の変更でした',
  'duplicate': '既存の報告と重複していました',
  'other': 'その他の理由で見送りました',
};

String describeBugReportRejectCategory(String? category) =>
    bugReportRejectCategoryLabels[category] ?? bugReportRejectCategoryLabels['other']!;
