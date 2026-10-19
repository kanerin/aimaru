// ── ふたりの質問の毎日の出題（純粋関数のみ）─────────────────
// Firestore や Gemini API に触れないため、エミュレータ無しで単体テストできる。
// 読み書きは daily_question_generation.ts が受け持つ。
//
// 以前はアプリ側（lib/utils/daily_question_picker.dart）が手書きの90問から
// 日付で選んでいたため、3か月で一巡して同じ質問が出ていた。今は前の晩に
// Geminiで翌日の質問を1つ作り、これまでに出した質問とは被らないものだけを
// dailyQuestions/{dateKey} に保存する。

import { GeminiContent } from "./gemini_logic";

export const DAY_MS = 24 * 60 * 60 * 1000;

/** 1日ぶんの生成で、Geminiに作り直させる最大回数（被り・形式違反のとき）。 */
export const GENERATION_ATTEMPTS = 3;

/**
 * プロンプトに「これまでの質問」として並べる件数の上限。
 * 被りの最終判定は全件で行うので、ここはプロンプトが際限なく伸びない
 * ようにするためだけの上限（新しいものから並べる）。
 */
export const PROMPT_HISTORY_LIMIT = 400;

const MIN_QUESTION_LENGTH = 5;
const MAX_QUESTION_LENGTH = 60;

/**
 * 毎日のテーマ。テーマを指定しないとGeminiは「最近ハマっているものは？」の
 * ような無難な質問に寄りがちで、言い回しだけ違う似た質問が続く。
 */
export const QUESTION_THEMES: readonly string[] = [
  "2人の思い出",
  "これからの2人の夢や計画",
  "食べ物・料理",
  "旅行・おでかけ",
  "もしもの話（空想）",
  "子供の頃・学生時代",
  "日常のささいな出来事",
  "相手のこと",
  "自分のこと",
  "好みやこだわり（〇〇派？）",
  "季節や行事",
  "趣味・遊び",
  "感謝や嬉しかった気持ち",
  "音楽・映画・本",
  "家や暮らし",
  "ちょっとした価値観",
];

/**
 * 被り判定用に質問文を正規化する。全角・半角の違い、空白、文末の
 * 「？」「！」「。」の有無だけが違う質問は同じものとみなす。
 */
export function normalizeQuestion(text: string): string {
  return text
    .normalize("NFKC")
    .replace(/\s+/g, "")
    .replace(/[?!。．.]+$/u, "");
}

/** dateKey（とその日の試行回数）から決定的にテーマを選ぶ。 */
export function pickQuestionTheme(dateKey: string, attempt = 0): string {
  let hash = 0;
  for (const ch of dateKey) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  return QUESTION_THEMES[(hash + attempt) % QUESTION_THEMES.length];
}

/** 翌日の質問をGeminiに1つ作らせるプロンプト。 */
export function buildQuestionGenerationContents(
  pastQuestions: readonly string[],
  theme: string,
): GeminiContent[] {
  const history = pastQuestions.length > 0
    ? pastQuestions.map((q) => `- ${q}`).join("\n")
    : "（まだありません）";
  const prompt = `あなたはカップル向けアプリの「ふたりの質問」の出題係です。
カップルの2人が毎日それぞれ答えて、答えを見せ合う質問を1つだけ作ってください。

条件:
- 今日のテーマ: ${theme}
- 日本語の、親しみやすい話し言葉で、10〜35文字程度
- 1〜2文で気軽に答えられて、答えを見せ合うと会話が広がる質問
- 2人ともが答えられる質問にする（どちらか一方だけに向けた質問にしない）
- 重い話題・答えにくい話題は避ける（過去の恋人、お金の貸し借り、容姿や体型の評価、病気、宗教、政治、性的な話題、家族の不和など）
- 住所・電話番号・パスワードなどの個人情報を聞かない
- 下の「これまでの質問」と同じ質問や、言い回しを変えただけの似た質問は作らない

出力は次のJSONだけにしてください。
{"question": "質問文"}

これまでの質問:
${history}`;
  return [{ role: "user", parts: [{ text: prompt }] }];
}

/**
 * Geminiの応答から質問文を取り出す。JSONとして読めない、1行でない、
 * 短すぎる・長すぎる、問いかけで終わっていない場合はnullを返し、
 * 呼び出し側で作り直させる。
 */
export function parseGeneratedQuestion(text: string): string | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof parsed !== "object" || parsed === null) return null;
  const question = (parsed as Record<string, unknown>).question;
  if (typeof question !== "string") return null;
  const trimmed = question.trim();
  if (/[\r\n]/.test(trimmed)) return null;
  const length = [...trimmed].length;
  if (length < MIN_QUESTION_LENGTH || length > MAX_QUESTION_LENGTH) return null;
  if (!/[?？!！]$/u.test(trimmed)) return null;
  return trimmed;
}

/** 予備の質問のうち、まだ出していない最初の1つを返す。使い切っていればnull。 */
export function pickReserveQuestion(
  reserve: readonly string[],
  usedNormalized: ReadonlySet<string>,
): string | null {
  return reserve.find((q) => !usedNormalized.has(normalizeQuestion(q))) ?? null;
}
