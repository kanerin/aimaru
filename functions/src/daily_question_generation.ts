// ── ふたりの質問: 翌日の質問を用意して dailyQuestions/{dateKey} に保存する ──
// 判定や文面は daily_question_logic.ts の純粋関数に寄せ、ここは Firestore の
// 読み書きと Gemini 呼び出しの組み合わせだけを受け持つ。Firestore と
// Gemini の呼び出しを引数で受け取るので、結合テストからエミュレータと
// 偽のGeminiを渡して、本番と同じ関数をそのまま検証できる。

import { FieldValue, Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

import {
  buildQuestionGenerationContents,
  DAY_MS,
  GENERATION_ATTEMPTS,
  normalizeQuestion,
  parseGeneratedQuestion,
  pickQuestionTheme,
  pickReserveQuestion,
  PROMPT_HISTORY_LIMIT,
} from "./daily_question_logic";
import {
  GeminiCallError,
  GeminiCallResult,
  GeminiContent,
  truncateForLog,
} from "./gemini_logic";
import { LEGACY_QUESTIONS, RESERVE_QUESTIONS } from "./question_bank";
import { tokyoDateKey } from "./question_reminder_logic";

export const DAILY_QUESTIONS_COLLECTION = "dailyQuestions";

// gRPCのステータスコード。ドキュメントが既にあるときに create が返す。
const ALREADY_EXISTS = 6;

export type GenerateQuestion = (
  contents: GeminiContent[],
) => Promise<GeminiCallResult | GeminiCallError>;

export interface DailyQuestionDoc {
  dateKey: string;
  text: string;
  /** "gemini"（生成）か "reserve"（手書きの予備） */
  source: "gemini" | "reserve";
}

/**
 * nowMs の翌日（Asia/Tokyo）の質問を用意して保存する。
 * すでにその日の質問があれば何もしない（1日に何度走っても質問は変わらない）。
 *
 * その日の途中で質問が変わると、先に答えた人と後から答えた人で質問が
 * 食い違うので、作るのは必ず翌日の分だけにする。generate が null（APIキー
 * 未設定）や生成の失敗が続いたときは、手書きの予備から出す。
 *
 * @returns 新しく保存した質問。既にあった・用意できなかった場合はnull。
 */
export async function prepareDailyQuestion(
  db: Firestore,
  nowMs: number,
  generate: GenerateQuestion | null,
): Promise<DailyQuestionDoc | null> {
  const dateKey = tokyoDateKey(nowMs + DAY_MS);
  const ref = db.collection(DAILY_QUESTIONS_COLLECTION).doc(dateKey);
  if ((await ref.get()).exists) return null;

  // ドキュメントIDが'yyyy-MM-dd'なので、取得順＝日付順になる。
  const pastSnap = await db.collection(DAILY_QUESTIONS_COLLECTION).get();
  const pastQuestions = pastSnap.docs
    .map((doc) => doc.data().text)
    .filter((text): text is string => typeof text === "string");
  const used = new Set([...LEGACY_QUESTIONS, ...pastQuestions].map(normalizeQuestion));
  const promptHistory = [
    ...pastQuestions.slice(-PROMPT_HISTORY_LIMIT).reverse(),
    ...LEGACY_QUESTIONS,
  ];

  let question: DailyQuestionDoc | null = null;
  for (let attempt = 0; generate && attempt < GENERATION_ATTEMPTS; attempt++) {
    const theme = pickQuestionTheme(dateKey, attempt);
    const result = await generate(buildQuestionGenerationContents(promptHistory, theme));
    if (!result.ok) {
      logger.error(`prepareDailyQuestion: Geminiでの生成に失敗しました（${dateKey}）: ${result.detail}`);
      continue;
    }
    const text = parseGeneratedQuestion(result.text);
    if (!text) {
      logger.warn(`prepareDailyQuestion: 質問として使えない応答でした（${dateKey}）: ${truncateForLog(result.text)}`);
      continue;
    }
    if (used.has(normalizeQuestion(text))) {
      logger.warn(`prepareDailyQuestion: これまでの質問と被りました（${dateKey}）: ${text}`);
      continue;
    }
    question = { dateKey, text, source: "gemini" };
    break;
  }

  if (!question) {
    const reserve = pickReserveQuestion(RESERVE_QUESTIONS, used);
    if (!reserve) {
      // ここに来ると、アプリ側は手書きの90問（daily_question_picker.dart）から出す。
      logger.error(`prepareDailyQuestion: 生成に失敗し、予備の質問も使い切りました（${dateKey}）`);
      return null;
    }
    question = { dateKey, text: reserve, source: "reserve" };
  }

  try {
    // create は既にあると失敗する。同じ日の分を並行して作っても先勝ちになる。
    await ref.create({ ...question, createdAt: FieldValue.serverTimestamp() });
  } catch (err) {
    if ((err as { code?: unknown }).code !== ALREADY_EXISTS) throw err;
    logger.warn(`prepareDailyQuestion: ${dateKey}の質問は既に作られていました`);
    return null;
  }
  return question;
}
