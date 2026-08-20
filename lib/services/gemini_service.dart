import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

enum GeminiReplyKind { events, text }

// ── AIチャットへの応答。予定候補(events)か、通常の文章(text)のどちらか ──
class GeminiReply {
  final GeminiReplyKind kind;
  final List<GeminiParsedEvent> events;
  final String text;

  const GeminiReply.events(this.events) : kind = GeminiReplyKind.events, text = '';
  const GeminiReply.text(this.text) : kind = GeminiReplyKind.text, events = const [];
}

// ── AIの応答を解釈できなかったときの定型文 ──────────────
// 予定の取り違えは共有カレンダーだと相手にも通知が飛ぶため、
// 解釈できないときは「何も作らずに聞き返す」を貫く。
const kGeminiUnparseableMessage = 'うまく聞き取れませんでした。もう一度試してください。';
const kGeminiErrorMessage       = 'エラーが発生しました。もう一度試してください。';
const kGeminiQuotaMessage       = 'AIの利用上限に達しました。しばらく時間をおいてからお試しください。';
const kGeminiApiKeyMessage      = 'AIの認証に失敗しました。APIキーの設定を確認してください。';
const kGeminiNetworkMessage     = '通信に失敗しました。電波状況を確認してもう一度お試しください。';
const kGeminiNoApiKeyMessage    = 'AIのAPIキーが設定されていないため利用できません。';
// askGemini関数そのものに到達できなかった場合（本番へデプロイされていない、
// 関数名の変更で古いAPKから消えた関数を呼んでいる、など）。
// 「通信エラー」で一括りにすると、利用者からの報告だけでは
// 「サーバー側の未デプロイ」と「一時的な不調」を区別できない。
const kGeminiNotDeployedMessage = 'AI機能が現在ご利用いただけません。復旧までしばらくお待ちください。';
// 上のkGeminiErrorMessageは「応答をJSONとして読めなかった」場合に使う。
// 呼び出し自体が例外で落ちた場合と区別できるよう、文言を分けている。
const kGeminiUnknownErrorMessage = 'AIとの通信でエラーが発生しました。もう一度試してください。';

// ── AIの生の応答文字列を GeminiReply へ変換する ─────────
// Cloud Functions呼び出しに依存しない純粋関数なので単体テストできる。
// どの失敗経路でも例外を外へ出さず、予定は決して作らない。
GeminiReply parseGeminiReply(String rawResponse) {
  try {
    final jsonStr = rawResponse
        .trim()
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      return const GeminiReply.text(kGeminiUnparseableMessage);
    }

    if (decoded['kind'] == 'events') {
      final list = (decoded['events'] as List? ?? [])
          .map((e) => GeminiParsedEvent.fromJson(e as Map<String, dynamic>))
          .toList();
      // 空配列で返ってきた場合は予定として扱わず、通常の返答へ倒す
      if (list.isNotEmpty) return GeminiReply.events(list);
    }

    return GeminiReply.text(
      (decoded['text'] as String?) ?? kGeminiUnparseableMessage,
    );
  } catch (_) {
    // JSONとして壊れている / dateがパースできない / eventsの要素が
    // オブジェクトでない、などはすべてここに落ちる
    return const GeminiReply.text(kGeminiErrorMessage);
  }
}

// ── AIの応答形式の指示。テキスト応答・画像解析の両方で共通 ─────
// events/textのJSONスキーマがずれるとparseGeminiReplyが読めなくなるため、
// 両呼び出しで同じ文言を1箇所にまとめて共有する。
const _kResponseFormatInstructions = '''
## 応答形式
ユーザーの入力を解釈し、必ず次のいずれかのJSON形式のみを返してください。
マークダウンやコードブロックは不要です。

1. 具体的な予定を追加できる場合（会話の流れ全体から日付・内容が十分に読み取れる場合）:
{"kind":"events","events":[{"title":"予定のタイトル","date":"YYYY-MM-DD","type":"date|anniversary|celebrity|plan","recurring":true|false,"location":"場所や null","memo":"メモや null"}]}
「〇〇のメンバー全員の誕生日」のように複数件が該当する場合は配列に複数件含めてください。
有名人・アーティスト・スポーツ選手などの誕生日は、あなたの知識から正確な日付を答えてください。

2. それ以外（雑談、上記の「直近の予定」を使って答える質問、使い方の質問、
   予定を追加したそうだが日付や内容が曖昧で確定できない場合など）:
{"kind":"text","text":"日本語で2〜4文の簡潔な返答。予定が曖昧な場合は『いつ・何をするか』を具体的に聞き返す。実在しないUI要素の案内はしない"}

typeの使い分け: date=デートや外出、anniversary=記念日、celebrity=有名人の誕生日等、plan=未確定のプラン
recurringは「毎年繰り返す」場合にtrue（誕生日・記念日など）
''';

// ── Cloud Functions（askGemini）へ渡す contents/parts の組み立て ─────
// Gemini APIのcontents/parts JSON形式をそのまま踏襲している
// （functions/src/gemini_logic.ts の GeminiContent/GeminiPart と対応）。
Map<String, dynamic> _textPart(String text) => {'text': text};

Map<String, dynamic> _inlineDataPart(String mimeType, String base64Data) => {
  'inlineData': {'mimeType': mimeType, 'data': base64Data},
};

Map<String, dynamic> _content(String role, List<Map<String, dynamic>> parts) =>
    {'role': role, 'parts': parts};

List<Map<String, dynamic>> _historyContents(List<Map<String, String>> history) =>
    history
        .map((m) => _content(
              m['role'] == 'user' ? 'user' : 'model',
              [_textPart(m['text']!)],
            ))
        .toList();

class GeminiService {
  // どのカップルとしてAIを呼び出すか。Cloud Functions側でこのカップルの
  // メンバーであることを検証する（招待コードだけ知っている非メンバーからの
  // 呼び出しや、他カップルへのなりすましを防ぐ）。
  final String coupleId;

  // 本番はFirebase Callable Functions（askGemini）を呼ぶ。テストからは
  // 実際のFirebase呼び出しをせずに応答を差し込めるようにしてある。
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data) _invoke;

  GeminiService({
    required this.coupleId,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? invoke,
  }) : _invoke = invoke ?? _defaultInvoke;

  static Future<Map<String, dynamic>> _defaultInvoke(Map<String, dynamic> data) async {
    final callable = FirebaseFunctions.instance.httpsCallable('askGemini');
    final result = await callable.call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ── ユーザーの入力に対して、予定候補 or 通常の返答を1回のAI呼び出しで返す ──
  // 会話履歴を渡すことで「今日の予定を追加したい」→「デートの予定」のような
  // 複数ターンにまたがる予定追加にも対応する。
  // eventsContextを渡すと「来週の予定は？」のような参照質問にも答えられる
  // （このアプリの予定・Googleカレンダーの予定の両方を含められる。呼び出し側で整形する）。
  Future<GeminiReply> respond(
    String userMessage,
    List<Map<String, String>> history, {
    String eventsContext = 'なし',
  }) async {
    final today = DateFormat('yyyy-MM-dd(E)', 'ja').format(DateTime.now());

    final systemPrompt = '''
あなたは「AIMARU」というカップル向けスケジュール共有アプリ内のAIアシスタント「AIMARU AI」です。
今日の日付は $today です。

## AIMARUの機能（「使い方」を聞かれたら踏まえて案内する）
- カレンダー画面: 2人の予定を共有。月全体を見渡す表示と、1日ごとの詳細表示を日付タップで切り替えられる
- このAIチャット: 自然言語で予定を追加したり、今後の予定について質問したりできる
- カップルチャット: パートナーと直接メッセージ・写真をやり取りできる
- 設定画面: 通知のON/OFF・タイミング、テーマカラー、祝日表示、Googleカレンダー連携などを変更できる

## 直近の予定（参照質問に答えるための参考情報）
$eventsContext

$_kResponseFormatInstructions
''';

    final contents = [
      _content('user', [_textPart(systemPrompt)]),
      ..._historyContents(history),
      _content('user', [_textPart(userMessage)]),
    ];

    try {
      final data = await _invoke({'coupleId': coupleId, 'contents': contents});
      return parseGeminiReply(data['text'] as String? ?? '');
    } catch (e) {
      // 「エラーが発生しました」だけだと、上限切れなのか通信断なのか
      // 認証の問題なのかが画面から一切判別できないので切り分ける
      return GeminiReply.text(describeCallableFailure(e));
    }
  }

  // ── ユーザーが送った画像（他社カレンダーのスクショ、招待状、チラシなど）から
  // 予定候補を抽出する。応答はテキスト版と同じJSONスキーマで受け取り、
  // parseGeminiReplyをそのまま再利用する（「解釈できなければ予定を作らない」
  // という安全性がここでも保たれる）。
  Future<GeminiReply> respondToImage(
    Uint8List imageBytes,
    String mimeType, {
    List<Map<String, String>> history = const [],
    String eventsContext = 'なし',
  }) async {
    final today = DateFormat('yyyy-MM-dd(E)', 'ja').format(DateTime.now());

    final systemPrompt = '''
あなたは「AIMARU」というカップル向けスケジュール共有アプリ内のAIアシスタント「AIMARU AI」です。
今日の日付は $today です。

ユーザーが画像を送ってきました。他のカレンダーアプリのスクリーンショット、招待状、
チラシ、LINEやメールのやり取りなど、予定の情報が写っている可能性があります。
画像から読み取れる予定（日付・タイトルなど）があればすべて抽出してください。
複数の予定が写っていれば全件を配列に含めてください。
年が書かれていない場合は、今日（$today）以降で直近に来る年と推測してください。
予定らしき情報が読み取れない画像の場合は、その旨を伝える返答をしてください。

## 直近の予定（参照質問に答えるための参考情報）
$eventsContext

$_kResponseFormatInstructions
''';

    final contents = [
      _content('user', [_textPart(systemPrompt)]),
      ..._historyContents(history),
      _content('user', [
        _textPart('この画像から予定を抽出してください。'),
        _inlineDataPart(mimeType, base64Encode(imageBytes)),
      ]),
    ];

    try {
      final data = await _invoke({'coupleId': coupleId, 'contents': contents});
      return parseGeminiReply(data['text'] as String? ?? '');
    } catch (e) {
      return GeminiReply.text(describeCallableFailure(e));
    }
  }
}

// ── askGemini呼び出しが例外で落ちた理由を、利用者が次に取れる行動へ翻訳する ──
// サーバー側（functions/src/index.ts の askGemini）が投げるHttpsErrorの
// codeとここでの分岐を対応させている。FirebaseFunctionsException以外
// （Firebase未初期化など、Functions呼び出しにすら到達しない例外）は
// describeGeminiFailure の文字列判定にフォールバックする。
String describeCallableFailure(Object error) {
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'resource-exhausted':
        return kGeminiQuotaMessage;
      // サーバー側にGemini APIキーがまだ設定されていない場合。
      // 以前の「クライアント側のAPIキー未設定」と意味的に対応する。
      case 'failed-precondition':
        return kGeminiNoApiKeyMessage;
      case 'unauthenticated':
      case 'permission-denied':
        return kGeminiApiKeyMessage;
      case 'unavailable':
      case 'deadline-exceeded':
        return kGeminiNetworkMessage;
      // Cloud Functions側に askGemini が存在しない。関数は自動デプロイ
      // されないため、コードだけ入って本番へ反映されていないと必ずこれになる。
      case 'not-found':
      case 'unimplemented':
        return kGeminiNotDeployedMessage;
    }
  }
  return describeGeminiFailure(error);
}

// ── 呼び出しが例外で落ちた理由を、利用者が次に取れる行動へ翻訳する ──
// FirebaseFunctionsException以外の一般的な例外（Firebase未初期化、
// ソケットエラーなど）を文字列で判定する。describeCallableFailure から
// フォールバックとして使われる。
String describeGeminiFailure(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('429') || s.contains('quota') || s.contains('resource_exhausted') ||
      s.contains('rate limit')) {
    return kGeminiQuotaMessage;
  }
  if (s.contains('api key') || s.contains('api_key') || s.contains('unauthenticated') ||
      s.contains('permission_denied') || s.contains('401') || s.contains('403')) {
    return kGeminiApiKeyMessage;
  }
  if (s.contains('socket') || s.contains('timeout') || s.contains('timed out') ||
      s.contains('network') || s.contains('connection')) {
    return kGeminiNetworkMessage;
  }
  return kGeminiUnknownErrorMessage;
}
