import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
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

// ── AIの生の応答文字列を GeminiReply へ変換する ─────────
// GenerativeModel に依存しない純粋関数なので単体テストできる。
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

class GeminiService {
  // ビルド時に --dart-define=GEMINI_API_KEY=xxx で渡す（ソースにキーを書かない）。
  // 開発時は android/local.properties や ~/.gradle 等ではなく、
  // 下記のように起動コマンドへ直接渡すか .vscode/launch.json 等に設定する。
  // 詳細はREADMEの「Gemini APIキー取得」を参照。
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      // gemini-flash-latestは無料枠が1日20リクエストしかなく枯渇しやすいため、
      // より余裕のあるgemini-flash-lite-latestを使う。
      model:  'gemini-flash-lite-latest',
      apiKey: _apiKey,
    );
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
    if (_apiKey.isEmpty) return const GeminiReply.text(kGeminiNoApiKeyMessage);

    final today = DateFormat('yyyy-MM-dd(E)', 'ja').format(DateTime.now());

    final systemPrompt = '''
あなたは「AIMARU」というカップル向けスケジュール共有アプリ内のAIアシスタント「AIMARU AI」です。
今日の日付は $today です。

## AIMARUの機能（「使い方」を聞かれたら踏まえて案内する）
- カレンダー画面: 2人の予定を共有。月全体を見渡す表示と、1日ごとの詳細表示を日付タップで切り替えられる
- このAIチャット: 自然言語で予定を追加したり、今後の予定について質問したりできる
- カップルチャット: パートナーと直接メッセージ・写真をやり取りできる
- 思い出アルバム: 予定に添付した写真が自動でまとまる
- 設定画面: 通知のON/OFF・タイミング、テーマカラー、祝日表示、Googleカレンダー連携などを変更できる

## 直近の予定（参照質問に答えるための参考情報）
$eventsContext

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

    final contents = [
      Content.text(systemPrompt),
      ...history.map((m) => m['role'] == 'user'
          ? Content.text(m['text']!)
          : Content.model([TextPart(m['text']!)])),
      Content.text(userMessage),
    ];

    try {
      final response = await _model.generateContent(contents);
      return parseGeminiReply(response.text ?? '');
    } catch (e) {
      // 「エラーが発生しました」だけだと、上限切れなのか通信断なのか
      // APIキーの問題なのかが画面から一切判別できないので切り分ける
      return GeminiReply.text(describeGeminiFailure(e));
    }
  }
}

// ── 呼び出しが例外で落ちた理由を、利用者が次に取れる行動へ翻訳する ──
// 例外の型は google_generative_ai の実装に依存するため、文字列で判定する。
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
  return kGeminiErrorMessage;
}
