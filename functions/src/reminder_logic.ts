// ── リマインダーの判定ロジック（純粋関数のみ）───────────────
// Firestore や FCM に触れないため、エミュレータ無しで単体テストできる。
// index.ts はここから import して、I/O と組み合わせるだけにする。

// スケジュール関数の実行間隔。
export const CHECK_INTERVAL_MINUTES = 15;

// 送信タイミングの判定に持たせる幅。実行間隔(15分)を切れ目なく
// カバーできるよう、片側8分（幅16分）を取っている。
export const WINDOW_MINUTES = 8;

// これ以上過ぎた予定はもう通知せず、クエリ肥大化を防ぐため片付ける。
export const STALE_AFTER_MS = 24 * 60 * 60 * 1000;

// リマインダーを何分前に送るかの既定値。
export const DEFAULT_REMINDER_MINUTES_BEFORE = 60;

/** 送信予定時刻が「今まさに送るべき」幅に収まっているか。 */
export function isWithinWindow(targetMs: number, nowMs: number): boolean {
  return Math.abs(targetMs - nowMs) / 60000 <= WINDOW_MINUTES;
}

/** 予定が古すぎて、もう通知する意味がないか。 */
export function isStale(eventMs: number, nowMs: number): boolean {
  return eventMs < nowMs - STALE_AFTER_MS;
}

/** 通知本文に出す「◯◯後」の表現。 */
export function formatRelative(minutesBefore: number): string {
  if (minutesBefore >= 1440) return `${Math.round(minutesBefore / 1440)}日後`;
  if (minutesBefore >= 60) return `${Math.round(minutesBefore / 60)}時間後`;
  return `${minutesBefore}分後`;
}

/**
 * 指定した年における、繰り返し予定の発生日。
 *
 * 2/29 の記念日を平年に評価すると `new Date(2026, 1, 29)` が 3/1 へ
 * 繰り上がってしまい、記念日が別の月に飛ぶ。月末で頭打ちにして
 * 2月内に留める。
 */
export function occurrenceInYear(original: Date, year: number): Date {
  const month = original.getMonth();
  const lastDayOfMonth = new Date(year, month + 1, 0).getDate();
  return new Date(
    year,
    month,
    Math.min(original.getDate(), lastDayOfMonth),
    original.getHours(),
    original.getMinutes(),
  );
}

/**
 * 繰り返し予定について、いま基準にすべき発生日を返す。
 *
 * 今年の発生日がまだ来ていない、あるいは過ぎて間もない(STALE_AFTER_MS以内)
 * ならそれを、すでに十分過ぎているなら来年の発生日を採用する。
 */
export function nextOccurrence(original: Date, nowMs: number): Date {
  const currentYear = new Date(nowMs).getFullYear();
  const candidates = [currentYear, currentYear + 1].map((year) =>
    occurrenceInYear(original, year),
  );
  return (
    candidates.find((d) => d.getTime() >= nowMs - STALE_AFTER_MS) ??
    candidates[candidates.length - 1]
  );
}

/**
 * あるメンバーに対して、この予定のリマインダーを今送るべきか。
 *
 * @param eventMs        予定の開始時刻
 * @param minutesBefore  そのメンバーの「何分前に通知するか」設定
 */
export function shouldRemindNow(
  eventMs: number,
  minutesBefore: number,
  nowMs: number,
): boolean {
  return isWithinWindow(eventMs - minutesBefore * 60000, nowMs);
}

/** users ドキュメントの reminderMinutesBefore を既定値込みで解決する。 */
export function resolveMinutesBefore(value: number | undefined | null): number {
  return value ?? DEFAULT_REMINDER_MINUTES_BEFORE;
}
