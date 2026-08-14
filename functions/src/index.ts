import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import {
  CHECK_INTERVAL_MINUTES,
  formatRelative,
  isStale,
  nextOccurrence,
  resolveMinutesBefore,
  resolveReminderTargets,
} from "./reminder_logic";

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

interface EventDoc {
  title: string;
  date: Timestamp;
  createdBy: string;
  recurring?: boolean;
  // reminded / remindedYear は「全メンバーへの送信が完了したか」を表す。
  // メンバーごとの送信済み状態は remindedUids で管理する（片方だけ送って
  // フラグが立ち、もう片方の通知が永久に失われるのを防ぐため）。
  reminded?: boolean;
  remindedUids?: string[];
  remindedYear?: number | null;
  // remindedUids は「年ごと」にリセットする必要がある繰り返し予定でも
  // 使い回すため、どの年についての集計かをここで持つ。
  remindedUidsYear?: number | null;
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
// 判定そのものは reminder_logic.ts の純粋関数に寄せてある。

// 単発の予定（recurring != true）のリマインダー
async function processOneTimeEvents(nowMs: number): Promise<void> {
  const snap = await db.collectionGroup("events").where("reminded", "==", false).get();

  for (const doc of snap.docs) {
    const data = doc.data() as EventDoc;
    if (data.recurring) continue;

    const eventMs = data.date.toDate().getTime();

    // 大きく過ぎた予定はクエリ肥大化を防ぐため片付ける
    if (isStale(eventMs, nowMs)) {
      await doc.ref.update({ reminded: true });
      continue;
    }

    const coupleId = doc.ref.parent.parent?.id;
    if (!coupleId) continue;
    const coupleSnap = await db.collection("couples").doc(coupleId).get();
    const memberIds: string[] = coupleSnap.data()?.memberIds ?? [];
    const alreadyRemindedUids = new Set(data.remindedUids ?? []);

    const members = await Promise.all(
      memberIds.map(async (uid) => {
        const userSnap = await db.collection("users").doc(uid).get();
        const user = userSnap.data() as UserDoc | undefined;
        return {
          uid,
          fcmToken: user?.fcmToken,
          alreadyReminded: alreadyRemindedUids.has(uid),
          remindersEnabled: !!user && user.remindersEnabled !== false,
          minutesBefore: resolveMinutesBefore(user?.reminderMinutesBefore),
        };
      }),
    );

    const { toRemind, fullySettled } = resolveReminderTargets(members, eventMs, nowMs);

    for (const uid of toRemind) {
      const member = members.find((m) => m.uid === uid)!;
      await sendFcm(
        member.fcmToken,
        "まもなく予定です",
        `「${data.title}」が${formatRelative(member.minutesBefore)}にあります`,
        { type: "reminder", coupleId, eventId: doc.id },
      );
    }

    if (toRemind.length > 0 || fullySettled) {
      await doc.ref.update({
        remindedUids: [...alreadyRemindedUids, ...toRemind],
        reminded: fullySettled,
      });
    }
  }
}

// 毎年繰り返す予定（記念日など、recurring == true）のリマインダー
async function processRecurringEvents(nowMs: number): Promise<void> {
  const snap = await db.collectionGroup("events").where("recurring", "==", true).get();

  for (const doc of snap.docs) {
    const data = doc.data() as EventDoc;

    // 今年 or 来年のうち、直近の発生日を採用する
    const occurrence = nextOccurrence(data.date.toDate(), nowMs);
    const occurrenceYear = occurrence.getFullYear();

    if (data.remindedYear === occurrenceYear) continue;

    const coupleId = doc.ref.parent.parent?.id;
    if (!coupleId) continue;
    const coupleSnap = await db.collection("couples").doc(coupleId).get();
    const memberIds: string[] = coupleSnap.data()?.memberIds ?? [];

    // remindedUids は発生年が変わったらリセットする（去年の送信済み記録を
    // 今年の判定に持ち越さない）
    const alreadyRemindedUids =
      data.remindedUidsYear === occurrenceYear ? new Set(data.remindedUids ?? []) : new Set<string>();

    const members = await Promise.all(
      memberIds.map(async (uid) => {
        const userSnap = await db.collection("users").doc(uid).get();
        const user = userSnap.data() as UserDoc | undefined;
        return {
          uid,
          fcmToken: user?.fcmToken,
          alreadyReminded: alreadyRemindedUids.has(uid),
          remindersEnabled: !!user && user.remindersEnabled !== false,
          minutesBefore: resolveMinutesBefore(user?.reminderMinutesBefore),
        };
      }),
    );

    const { toRemind, fullySettled } = resolveReminderTargets(members, occurrence.getTime(), nowMs);

    for (const uid of toRemind) {
      const member = members.find((m) => m.uid === uid)!;
      await sendFcm(
        member.fcmToken,
        "まもなく記念日です",
        `「${data.title}」が${formatRelative(member.minutesBefore)}にあります`,
        { type: "reminder", coupleId, eventId: doc.id },
      );
    }

    if (toRemind.length > 0 || fullySettled) {
      await doc.ref.update({
        remindedUids: [...alreadyRemindedUids, ...toRemind],
        remindedUidsYear: occurrenceYear,
        remindedYear: fullySettled ? occurrenceYear : null,
      });
    }
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
