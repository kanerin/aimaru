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

// 単発予定の走査を絞り込む先読み幅。設定できるリマインダーの最大値
// （lib/screens/settings_screen.dart の _reminderOptions、現状最大は
// 1440分=1日前）より確実に長く取ってある。ここを縮めると、先読み幅を
// 超えて設定されたリマインダーが発火しなくなるので、_reminderOptions に
// より長い選択肢を追加する場合はあわせて見直すこと。
export const QUERY_LOOKAHEAD_MS = 3 * 24 * 60 * 60 * 1000;

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

/**
 * 予定の通知（新規追加・リマインダー）を送ってよいメンバーを絞り込む。
 *
 * firestore.rulesとevent_service.dartの読み取り制限（visibility === 'private'
 * な予定は作成者本人にしか見えない）に、Cloud Functionsからの通知経路
 * （onEventCreated・processOneTimeEvents・processRecurringEvents）も
 * 合わせる。ここが漏れると、カレンダー上は見えないはずのprivateな予定の
 * タイトルが、追加通知やリマインダー通知の本文としてパートナーに届いてしまう。
 * visibilityが無い（既存ドキュメント）場合はsharedとして全員に送る。
 */
export function visibleMemberIds(
  memberIds: string[],
  createdBy: string,
  visibility: string | undefined,
): string[] {
  if (visibility === "private") return memberIds.filter((uid) => uid === createdBy);
  return memberIds;
}

/** メンバー1人ぶんの、リマインダー判定に要る情報。 */
export interface MemberReminderState {
  uid: string;
  /** この予定について、このメンバーへは送信済みか */
  alreadyReminded: boolean;
  remindersEnabled: boolean;
  minutesBefore: number;
}

export interface ReminderTargets {
  /** 今回新たに送信すべきメンバーのuid */
  toRemind: string[];
  /**
   * 全メンバーが「送信済み」か「今後も送信不要（無効化）」のどちらかに
   * 収まったか。falseなら、まだ送信タイミングを待っているメンバーがいる。
   */
  fullySettled: boolean;
}

/**
 * 予定単位の `reminded` フラグだと、先にタイミングが来たメンバーへ送った
 * 時点でフラグが立ち、他のメンバー（例: 「1日前」設定で自分より遅く
 * タイミングが来る人）が二度と拾われなくなる。
 *
 * メンバーごとに `alreadyReminded` を管理し、「まだ送信していない・
 * 無効化されていない・タイミングも来ていない」メンバーが1人でもいる間は
 * `fullySettled` を false のままにすることで、次回以降の実行でも
 * その予定を拾い続けられるようにする。
 */
export function resolveReminderTargets(
  members: MemberReminderState[],
  eventMs: number,
  nowMs: number,
): ReminderTargets {
  const toRemind: string[] = [];
  let stillPending = false;

  for (const member of members) {
    if (member.alreadyReminded || !member.remindersEnabled) continue;
    if (shouldRemindNow(eventMs, member.minutesBefore, nowMs)) {
      toRemind.push(member.uid);
    } else {
      stillPending = true;
    }
  }

  return { toRemind, fullySettled: !stillPending };
}
