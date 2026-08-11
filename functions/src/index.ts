import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

interface EventDoc {
  title: string;
  date: Timestamp;
  createdBy: string;
  recurring?: boolean;
  reminded?: boolean;
  remindedYear?: number | null;
}

interface UserDoc {
  displayName?: string;
  fcmToken?: string;
  notifyOnNewEvent?: boolean;
  remindersEnabled?: boolean;
  reminderMinutesBefore?: number;
}

async function sendFcm(
  token: string | undefined,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  if (!token) return;
  try {
    await messaging.send({ token, notification: { title, body }, data });
  } catch (err) {
    logger.warn("FCM送信に失敗しました", err);
  }
}

function formatRelative(minutesBefore: number): string {
  if (minutesBefore >= 1440) return `${Math.round(minutesBefore / 1440)}日後`;
  if (minutesBefore >= 60) return `${Math.round(minutesBefore / 60)}時間後`;
  return `${minutesBefore}分後`;
}

// ── 予定登録通知: パートナーが予定を追加したら通知 ──────────
export const onEventCreated = onDocumentCreated(
  "couples/{coupleId}/events/{eventId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() as EventDoc;
    const { coupleId, eventId } = event.params;

    const coupleSnap = await db.collection("couples").doc(coupleId).get();
    const memberIds: string[] = coupleSnap.data()?.memberIds ?? [];
    const partnerIds = memberIds.filter((id) => id !== data.createdBy);
    if (partnerIds.length === 0) return;

    const creatorSnap = await db.collection("users").doc(data.createdBy).get();
    const creatorName = (creatorSnap.data() as UserDoc | undefined)?.displayName ?? "パートナー";

    const dateStr = data.date.toDate().toLocaleDateString("ja-JP", {
      month: "numeric",
      day: "numeric",
      timeZone: "Asia/Tokyo",
    });

    await Promise.all(
      partnerIds.map(async (uid) => {
        const userSnap = await db.collection("users").doc(uid).get();
        const user = userSnap.data() as UserDoc | undefined;
        if (!user || user.notifyOnNewEvent === false) return;
        await sendFcm(
          user.fcmToken,
          "新しい予定が追加されました",
          `${creatorName}さんが「${data.title}」(${dateStr})を追加しました`,
          { type: "new_event", coupleId, eventId },
        );
      }),
    );
  },
);

// ── リマインダー通知: 予定の開始前に通知 ────────────────────
// CHECK_INTERVAL_MINUTES間隔で実行し、各メンバーの reminderMinutesBefore
// 設定に応じて「今まさに通知すべき予定」を判定する。
// 実行タイミングのずれを吸収するため、判定に幅（WINDOW_MINUTES）を持たせる。
const CHECK_INTERVAL_MINUTES = 15;
const WINDOW_MINUTES = 8; // 実行間隔(15分)を切れ目なくカバーできる幅

function isWithinWindow(targetMs: number, nowMs: number): boolean {
  return Math.abs(targetMs - nowMs) / 60000 <= WINDOW_MINUTES;
}

// 単発の予定（recurring != true）のリマインダー
async function processOneTimeEvents(nowMs: number): Promise<void> {
  const snap = await db.collectionGroup("events").where("reminded", "==", false).get();

  for (const doc of snap.docs) {
    const data = doc.data() as EventDoc;
    if (data.recurring) continue;

    const eventMs = data.date.toDate().getTime();

    // 大きく過ぎた予定はクエリ肥大化を防ぐため片付ける
    if (eventMs < nowMs - 24 * 60 * 60 * 1000) {
      await doc.ref.update({ reminded: true });
      continue;
    }

    const coupleId = doc.ref.parent.parent?.id;
    if (!coupleId) continue;
    const coupleSnap = await db.collection("couples").doc(coupleId).get();
    const memberIds: string[] = coupleSnap.data()?.memberIds ?? [];

    let anySent = false;
    for (const uid of memberIds) {
      const userSnap = await db.collection("users").doc(uid).get();
      const user = userSnap.data() as UserDoc | undefined;
      if (!user || user.remindersEnabled === false) continue;

      const minutesBefore = user.reminderMinutesBefore ?? 60;
      const targetMs = eventMs - minutesBefore * 60000;
      if (!isWithinWindow(targetMs, nowMs)) continue;

      await sendFcm(
        user.fcmToken,
        "まもなく予定です",
        `「${data.title}」が${formatRelative(minutesBefore)}にあります`,
        { type: "reminder", coupleId, eventId: doc.id },
      );
      anySent = true;
    }
    if (anySent) await doc.ref.update({ reminded: true });
  }
}

// 毎年繰り返す予定（記念日など、recurring == true）のリマインダー
async function processRecurringEvents(nowMs: number): Promise<void> {
  const snap = await db.collectionGroup("events").where("recurring", "==", true).get();
  const now = new Date(nowMs);

  for (const doc of snap.docs) {
    const data = doc.data() as EventDoc;
    const original = data.date.toDate();

    // 今年 or 来年のうち、直近の発生日を採用する
    const candidates = [now.getFullYear(), now.getFullYear() + 1].map(
      (year) =>
        new Date(
          year,
          original.getMonth(),
          original.getDate(),
          original.getHours(),
          original.getMinutes(),
        ),
    );
    const occurrence =
      candidates.find((d) => d.getTime() >= nowMs - 24 * 60 * 60 * 1000) ??
      candidates[candidates.length - 1];
    const occurrenceYear = occurrence.getFullYear();

    if (data.remindedYear === occurrenceYear) continue;

    const coupleId = doc.ref.parent.parent?.id;
    if (!coupleId) continue;
    const coupleSnap = await db.collection("couples").doc(coupleId).get();
    const memberIds: string[] = coupleSnap.data()?.memberIds ?? [];

    let anySent = false;
    for (const uid of memberIds) {
      const userSnap = await db.collection("users").doc(uid).get();
      const user = userSnap.data() as UserDoc | undefined;
      if (!user || user.remindersEnabled === false) continue;

      const minutesBefore = user.reminderMinutesBefore ?? 60;
      const targetMs = occurrence.getTime() - minutesBefore * 60000;
      if (!isWithinWindow(targetMs, nowMs)) continue;

      await sendFcm(
        user.fcmToken,
        "まもなく記念日です",
        `「${data.title}」が${formatRelative(minutesBefore)}にあります`,
        { type: "reminder", coupleId, eventId: doc.id },
      );
      anySent = true;
    }
    if (anySent) await doc.ref.update({ remindedYear: occurrenceYear });
  }
}

export const sendReminders = onSchedule(
  { schedule: `every ${CHECK_INTERVAL_MINUTES} minutes`, timeZone: "Asia/Tokyo" },
  async () => {
    const nowMs = Date.now();
    await processOneTimeEvents(nowMs);
    await processRecurringEvents(nowMs);
  },
);
