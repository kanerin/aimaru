// ── 外部カレンダー連携（iCalendar購読フィード）の純粋関数 ───────────
// Firestore や HTTP に触れないため、エミュレータ無しで単体テストできる。
// index.ts はここから import して、I/O と組み合わせるだけにする。
//
// TimeTreeは「設定 → カレンダー情報 → iCal URLをコピー」で、GoogleカレンダーやApple
// カレンダーへ読み取り専用でURL購読できるが、AIMARUはこれまでICSの取り込み（import）
// しか持たず、外へ公開する方向（export/購読）が無かった（2026年9月時点の競合調査）。

import { randomBytes } from "crypto";

export const CALENDAR_FEED_NAME = "AIMARUカレンダー";

/** 購読URLに載せる、当てずっぽうでは推測できないトークン。 */
export function generateFeedToken(): string {
  return randomBytes(24).toString("hex");
}

/** 購読URL（webcal購読・ブラウザどちらからも同じhttpsで取得できる）。 */
export function buildCalendarFeedUrl(projectId: string, uid: string, token: string): string {
  const params = new URLSearchParams({ uid, token });
  return `https://us-central1-${projectId}.cloudfunctions.net/calendarFeed?${params.toString()}`;
}

/**
 * このイベントを、フィードの持ち主（ownerUid）へ見せてよいか。
 *
 * firestore.rules・event_service.dartの読み取り制限（visibility === 'private'な
 * 予定は作成者本人にしか見えない）に、この公開フィードも合わせる。ここが漏れると、
 * カレンダー上は見えないはずのprivateな予定が、外部カレンダーアプリ経由でパートナーの
 * 目に触れてしまう。visibilityが無い（既存ドキュメント）場合はsharedとして扱う。
 */
export function isVisibleToFeedOwner(
  visibility: string | undefined,
  createdBy: string,
  ownerUid: string,
): boolean {
  return visibility !== "private" || createdBy === ownerUid;
}

export interface FeedEvent {
  id: string;
  title: string;
  start: Date;
  end: Date | null;
  allDay: boolean;
  recurring: boolean;
  location?: string | null;
  memo?: string | null;
}

function pad(n: number, len = 2): string {
  return n.toString().padStart(len, "0");
}

/** 終日予定用の日付表現（YYYYMMDD）。 */
export function formatIcsDate(date: Date): string {
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}`;
}

/** 時刻指定予定用のUTC日時表現（YYYYMMDDTHHMMSSZ）。 */
export function formatIcsDateTimeUtc(date: Date): string {
  return (
    `${date.getUTCFullYear()}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}T` +
    `${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}${pad(date.getUTCSeconds())}Z`
  );
}

/** RFC5545: TEXT値のバックスラッシュ・カンマ・セミコロン・改行をエスケープする。 */
export function escapeIcsText(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\n/g, "\\n");
}

/**
 * RFC5545: 1行75オクテット超は継続行へ折り返す（継続行の先頭は半角スペース）。
 * マルチバイト文字（日本語）の途中でバイト列を切らないよう、UTF-8のバイト長で調整する。
 */
export function foldIcsLine(line: string): string {
  if (Buffer.byteLength(line, "utf8") <= 75) return line;

  const segments: string[] = [];
  let rest = line;
  let isFirst = true;
  while (Buffer.byteLength(rest, "utf8") > (isFirst ? 75 : 74)) {
    const limit = isFirst ? 75 : 74;
    let cut = Math.min(limit, rest.length);
    while (Buffer.byteLength(rest.slice(0, cut), "utf8") > limit) cut--;
    segments.push((isFirst ? "" : " ") + rest.slice(0, cut));
    rest = rest.slice(cut);
    isFirst = false;
  }
  segments.push(` ${rest}`);
  return segments.join("\r\n");
}

/** 終日予定の end（排他的、翌日扱い）。google_calendar_service.dartのallDayEndExclusiveと同じ考え方。 */
function allDayEndExclusive(start: Date, lastDay: Date): Date {
  const startDay = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  const next = new Date(lastDay.getFullYear(), lastDay.getMonth(), lastDay.getDate());
  next.setDate(next.getDate() + 1);
  return next.getTime() > startDay.getTime() ? next : new Date(startDay.getTime() + 86400000);
}

function buildVEventLines(event: FeedEvent, dtStamp: string): string[] {
  const lines: string[] = ["BEGIN:VEVENT", `UID:${event.id}@aimaru`, `DTSTAMP:${dtStamp}`];

  if (event.allDay) {
    lines.push(`DTSTART;VALUE=DATE:${formatIcsDate(event.start)}`);
    lines.push(
      `DTEND;VALUE=DATE:${formatIcsDate(allDayEndExclusive(event.start, event.end ?? event.start))}`,
    );
  } else {
    lines.push(`DTSTART:${formatIcsDateTimeUtc(event.start)}`);
    const end = event.end ?? new Date(event.start.getTime() + 60 * 60 * 1000);
    lines.push(`DTEND:${formatIcsDateTimeUtc(end)}`);
  }

  lines.push(`SUMMARY:${escapeIcsText(event.title)}`);
  if (event.location) lines.push(`LOCATION:${escapeIcsText(event.location)}`);
  if (event.memo) lines.push(`DESCRIPTION:${escapeIcsText(event.memo)}`);
  // 毎年繰り返す予定（記念日等）。発生日の展開自体は購読側のカレンダーアプリに任せる。
  if (event.recurring) lines.push("RRULE:FREQ=YEARLY");

  lines.push("END:VEVENT");
  return lines;
}

/** イベント一覧からiCalendar(.ics)本文全体を組み立てる。 */
export function buildIcsCalendar(events: FeedEvent[], nowMs: number): string {
  const dtStamp = formatIcsDateTimeUtc(new Date(nowMs));
  const lines: string[] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//AIMARU//Calendar Feed//JA",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${escapeIcsText(CALENDAR_FEED_NAME)}`,
  ];
  for (const event of events) {
    lines.push(...buildVEventLines(event, dtStamp));
  }
  lines.push("END:VCALENDAR");

  return `${lines.map(foldIcsLine).join("\r\n")}\r\n`;
}
