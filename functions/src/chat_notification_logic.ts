// ── トークメッセージのプッシュ通知本文を組み立てる純粋関数 ───────────
// Firestoreや外部APIに触れないため、エミュレータ無しで単体テストできる。
// index.ts はここから import して、I/O と組み合わせるだけにする。

// 長文をそのまま通知に出すと1行しかない通知の見た目が崩れるため、
// 自由入力のテキストだけここで丸める（予定通知は固定長の文言なので対象外）。
export const CHAT_NOTIFICATION_PREVIEW_MAX_LENGTH = 40;

export function buildChatNotificationBody(text: string | undefined): string {
  const trimmed = (text ?? "").trim();
  if (trimmed.length === 0) return "写真を送りました";
  if (trimmed.length <= CHAT_NOTIFICATION_PREVIEW_MAX_LENGTH) return trimmed;
  return `${trimmed.slice(0, CHAT_NOTIFICATION_PREVIEW_MAX_LENGTH)}…`;
}
