// ── askGemini の判定ロジック（純粋関数のみ）───────────────
// Firestore や外部APIに触れないため、エミュレータ無しで単体テストできる。
// index.ts はここから import して、I/O と組み合わせるだけにする。

// 1日あたりの呼び出し上限。凝った設計にはせず、まず1箇所の定数で
// 誰でも調整できるようにしておく。
export const AI_DAILY_CALL_LIMIT = 50;

// Gemini側に渡すモデル名。gemini-flash-latestは無料枠が1日20リクエストしか
// なく枯渇しやすいため、より余裕のあるgemini-flash-lite-latestを使う
// （lib/services/gemini_service.dart の旧実装と合わせている）。
export const GEMINI_MODEL = "gemini-flash-lite-latest";

export interface RateLimitState {
  /** Asia/TokyoでのYYYY-MM-DD。日付が変わったらカウントをリセットする対象。 */
  date: string;
  count: number;
}

/**
 * 現在の呼び出しカウントに対して、今回の呼び出しを許可してよいかを判定する。
 *
 * 日付が変わっている（またはまだ記録が無い）場合は、今日はまだ0回として扱う。
 */
export function isOverLimit(
  current: RateLimitState | undefined,
  todayStr: string,
  limit: number = AI_DAILY_CALL_LIMIT,
): boolean {
  if (!current || current.date !== todayStr) return false;
  return current.count >= limit;
}

/**
 * 今回の呼び出しを記録した後の状態を返す。
 *
 * 日付が変わっていればカウントを1から数え直す。呼び出し前に
 * isOverLimit で許可判定を済ませてから使うこと（ここでは上限を見ない）。
 */
export function nextRateLimitState(
  current: RateLimitState | undefined,
  todayStr: string,
): RateLimitState {
  if (!current || current.date !== todayStr) {
    return { date: todayStr, count: 1 };
  }
  return { date: todayStr, count: current.count + 1 };
}

/** カップルのメンバーかどうか。招待コードだけ知っている非メンバーを弾く。 */
export function isCoupleMember(memberIds: string[], uid: string): boolean {
  return memberIds.includes(uid);
}

// ── Gemini API とのやり取り ─────────────────────────────

export type GeminiPart =
  | { text: string }
  | { inlineData: { mimeType: string; data: string } };

export interface GeminiContent {
  role: "user" | "model";
  parts: GeminiPart[];
}

/**
 * クライアントから届いた contents が、Gemini APIへそのまま渡してよい形か検証する。
 * 壊れた・巨大すぎるペイロードを弾く最低限のガード。
 */
export function validateContents(value: unknown): value is GeminiContent[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > 200) return false;
  return value.every((content) => {
    if (typeof content !== "object" || content === null) return false;
    const c = content as Record<string, unknown>;
    if (c.role !== "user" && c.role !== "model") return false;
    if (!Array.isArray(c.parts) || c.parts.length === 0) return false;
    return c.parts.every((part) => {
      if (typeof part !== "object" || part === null) return false;
      const p = part as Record<string, unknown>;
      if (typeof p.text === "string") return p.text.length <= 20000;
      if (
        typeof p.inlineData === "object" &&
        p.inlineData !== null &&
        typeof (p.inlineData as Record<string, unknown>).mimeType === "string" &&
        typeof (p.inlineData as Record<string, unknown>).data === "string"
      ) {
        // base64。画像は呼び出し側で1600px程度に縮小済みの前提でも、
        // 悪意あるペイロードで際限なく膨らむのは防ぐ（目安10MB相当）。
        return ((p.inlineData as Record<string, unknown>).data as string).length <= 14_000_000;
      }
      return false;
    });
  });
}

/** Gemini APIのHTTPステータスから、呼び出し元に返すエラー種別を決める。 */
export type GeminiErrorKind = "resource-exhausted" | "failed-precondition" | "internal";

export function classifyGeminiApiError(status: number): GeminiErrorKind {
  if (status === 429) return "resource-exhausted";
  // 401/403はこちら（サーバー側）が持つ鍵の問題であり、呼び出したユーザーの
  // 問題ではない。鍵未設定・失効のどちらもここに落ちる。
  if (status === 401 || status === 403) return "failed-precondition";
  return "internal";
}

/**
 * Gemini APIの生レスポンスから応答テキストを取り出す。
 * 形が想定と違う場合はnullを返し、呼び出し側でエラーとして扱わせる。
 */
export function extractGeminiText(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return null;
  const candidates = (body as Record<string, unknown>).candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) return null;
  const content = (candidates[0] as Record<string, unknown> | undefined)?.content;
  if (typeof content !== "object" || content === null) return null;
  const parts = (content as Record<string, unknown>).parts;
  if (!Array.isArray(parts) || parts.length === 0) return null;
  const text = (parts[0] as Record<string, unknown> | undefined)?.text;
  return typeof text === "string" ? text : null;
}

export interface GeminiCallResult {
  ok: true;
  text: string;
}
export interface GeminiCallError {
  ok: false;
  kind: GeminiErrorKind;
}

/**
 * Gemini APIを呼び出し、応答テキストか分類済みエラーを返す。
 * fetchImplを差し込めるようにしてあるので、テストでは実ネットワークに
 * 触れずレスポンス分岐を検証できる（globalのfetchは既定値として使うだけ）。
 */
export async function callGeminiApi(
  contents: GeminiContent[],
  apiKey: string,
  fetchImpl: typeof fetch = fetch,
): Promise<GeminiCallResult | GeminiCallError> {
  const res = await fetchImpl(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify({
        contents,
        generationConfig: { responseMimeType: "application/json" },
      }),
    },
  );

  if (!res.ok) {
    return { ok: false, kind: classifyGeminiApiError(res.status) };
  }

  const body: unknown = await res.json();
  const text = extractGeminiText(body);
  if (text === null) return { ok: false, kind: "internal" };
  return { ok: true, text };
}
