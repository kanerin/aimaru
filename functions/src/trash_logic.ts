// ── ゴミ箱（論理削除）の保持期間に関する純粋関数 ─────────────
// Firestore に触れないため、エミュレータ無しで単体テストできる。

/** 論理削除してから完全に削除するまでの保持日数。 */
export const TRASH_RETENTION_DAYS = 30;
export const TRASH_RETENTION_MS = TRASH_RETENTION_DAYS * 24 * 60 * 60 * 1000;

/** 論理削除した時刻が、保持期限を過ぎているか。 */
export function isPastRetention(deletedAtMs: number, nowMs: number): boolean {
  return deletedAtMs <= nowMs - TRASH_RETENTION_MS;
}
