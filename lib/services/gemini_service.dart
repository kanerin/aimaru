import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

class GeminiService {
  // ビルド時に --dart-define=GEMINI_API_KEY=xxx で渡す（ソースにキーを書かない）。
  // 開発時は android/local.properties や ~/.gradle 等ではなく、
  // 下記のように起動コマンドへ直接渡すか .vscode/launch.json 等に設定する。
  // 詳細はREADMEの「Gemini APIキー取得」を参照。
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model:  'gemini-flash-latest',
      apiKey: _apiKey,
    );
  }

  // ── 自然言語 → 予定データに変換（複数件対応）──────
  // 「〇〇のメンバー全員の誕生日」のように複数の予定が該当する
  // 入力にも対応するため、常にJSON配列で返させる。
  Future<List<GeminiParsedEvent>?> parseEventFromText(String userInput) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final prompt = '''
あなたはカップルの予定管理AIです。
今日の日付は $today です。

ユーザーの入力から予定情報を抽出し、必ず以下のJSON配列形式のみを返してください。
余分なテキスト、マークダウン、コードブロックは一切不要です。
該当する予定が1件だけでも、必ず配列に1つだけ入れて返してください。
「〇〇のメンバー全員の誕生日」のように複数の人物・予定が該当する場合は、
配列に複数件のオブジェクトを含めてください。

有名人・アーティスト・スポーツ選手などの誕生日を聞かれた場合は、
あなたの知識から正確な日付を答えてください。

JSON配列形式:
[
  {
    "title": "予定のタイトル",
    "date": "YYYY-MM-DD",
    "type": "date" | "anniversary" | "celebrity" | "plan",
    "recurring": true | false,
    "location": "場所（任意）",
    "memo": "メモ（任意）"
  }
]

typeの使い分け:
- date: デートや外出の予定
- anniversary: 記念日（付き合った日、誕生日など）
- celebrity: 有名人の誕生日や記念日
- plan: まだ未確定のプラン

recurringは「毎年繰り返す」場合にtrue（誕生日・記念日など）

ユーザー入力に予定情報が含まれない場合（雑談など）は、空配列 [] を返してください。

ユーザー入力: "$userInput"
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) return null;

      // JSONのみ抽出（余分な文字を除去）
      final jsonStr = text
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final decoded = jsonDecode(jsonStr);
      final List list = decoded is List ? decoded : [decoded];
      if (list.isEmpty) return null;
      return list
          .map((e) => GeminiParsedEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return null;
    }
  }

  // ── 汎用チャット（プランナーとして会話）─────────
  Future<String> chat(String userMessage, List<Map<String, String>> history) async {
    final systemPrompt = '''
あなたは「AIMARU AI」というカップル専用のアシスタントです。
予定の追加、デートプランの提案、記念日の管理をサポートします。
返答は必ず日本語で、2〜3文以内の簡潔な文章にしてください。
予定を追加したい場合は「予定を追加する」ボタンを案内してください。
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
      return response.text ?? 'うまく聞き取れませんでした。もう一度試してください。';
    } catch (e) {
      return 'エラーが発生しました。もう一度試してください。';
    }
  }
}
