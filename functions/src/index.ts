import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/v2";
import {
  CHECK_INTERVAL_MINUTES,
  formatRelative,
  isStale,
  nextOccurrence,
  QUERY_LOOKAHEAD_MS,
  resolveMinutesBefore,
  resolveReminderTargets,
  visibleMemberIds,
} from "./reminder_logic";
import {
  buildCalendarFeedUrl,
  buildIcsCalendar,
  FeedEvent,
  generateFeedToken,
  isVisibleToFeedOwner,
} from "./calendar_feed_logic";
import { TRASH_RETENTION_MS } from "./trash_logic";
import {
  callGeminiApi,
  GeminiContent,
  isCoupleMember,
  isOverLimit,
  nextRateLimitState,
  RateLimitState,
  validateContents,
} from "./gemini_logic";
import {
  BUG_REPORT_MONTHLY_LIMIT,
  MAX_BUG_REPORT_IMAGES,
  buildTriageContents,
  parseTriageResponse,
  validateImageUrls,
  validateReportText,
} from "./bug_report_logic";
import { buildChatNotificationBody } from "./chat_notification_logic";
import { resolveQuestionReminderTargets, tokyoDateKey } from "./question_reminder_logic";

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
  // 繰り返し予定について、直近の発生時刻をキャッシュしたもの
  // （docs/open-issues.md 課題8フェーズ3向けの準備、現時点では未使用）。
  nextOccurrenceMs?: Timestamp | null;
  // null以外ならゴミ箱に入っている（論理削除済み）。
  // 保持期間中はまだ復元されうるので、リマインダー送信の対象から外す。
  deletedAt?: Timestamp | null;
  // 'private'なら作成者以外に通知しない（visibleMemberIds参照）。
  // 既存ドキュメントには無く、その場合はsharedとして扱う。
  visibility?: string;
}

interface UserDoc {
  displayName?: string;
  fcmToken?: string;
  notifyOnNewEvent?: boolean;
  notifyOnNewChatMessage?: boolean;
  notifyOnDailyQuestion?: boolean;
  remindersEnabled?: boolean;
  reminderMinutesBefore?: number;
}

interface ChatMessageDoc {
  text?: string;
  imageUrl?: string;
  senderId: string;
  // AI（アプリ内アシスタント）が発言した場合はtrue。現状クライアントからは
  // 常にfalseで作られるが、実際のパートナーからの発言ではないため、
  // 誤って「〇〇さんからメッセージが届きました」という通知を送らないよう
  // 将来の利用に備えてここでも弾いておく。
  isAi?: boolean;
}

interface AnniversaryDoc {
  title: string;
  date: Timestamp;
  createdBy: string;
  // processRecurringEvents の remindedYear/remindedUidsYear/remindedUids と
  // 同じ役割（発生年ごとの送信済み管理）。記念日タブから追加した
  // couples/{coupleId}/anniversaries はイベント（couples/{coupleId}/events）
  // とは別コレクションのため、こちらは独自に持つ。
  remindedYear?: number | null;
  remindedUidsYear?: number | null;
  remindedUids?: string[];
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
    const partnerIds = visibleMemberIds(memberIds, data.createdBy, data.visibility).filter(
      (id) => id !== data.createdBy,
    );
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

// ── トーク通知: パートナーがメッセージを送ったら通知 ──────────
export const onChatMessageCreated = onDocumentCreated(
  "couples/{coupleId}/chats/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() as ChatMessageDoc;
    const { coupleId, messageId } = event.params;

    // AIの発言（isAi: true）は実際のパートナーからの発言ではないため通知しない。
    if (data.isAi) return;

    const coupleSnap = await db.collection("couples").doc(coupleId).get();
    const memberIds: string[] = coupleSnap.data()?.memberIds ?? [];
    const partnerIds = memberIds.filter((id) => id !== data.senderId);
    if (partnerIds.length === 0) return;

    const senderSnap = await db.collection("users").doc(data.senderId).get();
    const senderName = (senderSnap.data() as UserDoc | undefined)?.displayName ?? "パートナー";
    const body = buildChatNotificationBody(data.text);

    await Promise.all(
      partnerIds.map(async (uid) => {
        const userSnap = await db.collection("users").doc(uid).get();
        const user = userSnap.data() as UserDoc | undefined;
        if (!user || user.notifyOnNewChatMessage === false) return;
        await sendFcm(
          user.fcmToken,
          `${senderName}さんからメッセージ`,
          body,
          { type: "new_chat_message", coupleId, messageId },
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
//
// 「reminded == false」だけの等価条件だと、何ヶ月も先の予定までユーザー数分
// 毎回全件読み込むことになり、課金と実行時間がイベント数に対して線形以上に
// 伸びる（docs/open-issues.md 課題8）。dateの上限を切ることで、まだリマインダー
// 対象になり得ない先の予定を読まないようにする。過去方向は絞らない
// （STALE_AFTER_MSを超えた予定を片付ける処理がそのまま働く）。
// このクエリには firestore.indexes.json の複合インデックスが要る。
async function processOneTimeEvents(nowMs: number): Promise<void> {
  const lookaheadCutoff = Timestamp.fromMillis(nowMs + QUERY_LOOKAHEAD_MS);
  const snap = await db
    .collectionGroup("events")
    .where("reminded", "==", false)
    .where("date", "<=", lookaheadCutoff)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data() as EventDoc;
    if (data.recurring) continue;
    if (data.deletedAt) continue;

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
    const notifiableMemberIds = visibleMemberIds(memberIds, data.createdBy, data.visibility);
    const alreadyRemindedUids = new Set(data.remindedUids ?? []);

    const members = await Promise.all(
      notifiableMemberIds.map(async (uid) => {
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
//
// 課題8フェーズ3: nextOccurrenceMsで絞り込む（フェーズ1で追加した索引を使う）。
// 既存ドキュメントへの書き戻しが行き渡っていることを
// scripts/check-recurring-events-migration.mjs で確認済み（2026-08-21）。
// 新規作成時にnextOccurrenceMsが未設定だとこのクエリに一切引っかからず
// 永久にリマインドされなくなるため、EventService側で作成・更新のたびに
// 必ずTimestamp.fromMillis(0)（絞り込みに確実に引っかかる過去日時）を
// 書き込むようにしてある（_freshReminderFields）。このクエリが初めてその
// ドキュメントを拾った時点で、下の書き戻し処理が実際の発生日時に直す。
async function processRecurringEvents(nowMs: number): Promise<void> {
  const lookaheadCutoff = Timestamp.fromMillis(nowMs + QUERY_LOOKAHEAD_MS);
  const snap = await db
    .collectionGroup("events")
    .where("recurring", "==", true)
    .where("nextOccurrenceMs", "<=", lookaheadCutoff)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data() as EventDoc;
    if (data.deletedAt) continue;

    // 今年 or 来年のうち、直近の発生日を採用する
    const occurrence = nextOccurrence(data.date.toDate(), nowMs);
    const occurrenceYear = occurrence.getFullYear();
    const occurrenceMs = occurrence.getTime();

    // 課題8フェーズ3（このクエリ自体を絞り込む）に備え、直近の発生時刻を
    // nextOccurrenceMsへ書き戻しておく。全件走査は今回まだ変えておらず、
    // このフィールドはまだクエリの絞り込みには使っていない（既存ドキュメントに
    // 未設定のものが残っているため、絞り込むと過去分の通知が止まってしまう）。
    const needsOccurrenceRefresh = data.nextOccurrenceMs?.toMillis() !== occurrenceMs;

    if (data.remindedYear === occurrenceYear) {
      if (needsOccurrenceRefresh) {
        await doc.ref.update({ nextOccurrenceMs: Timestamp.fromMillis(occurrenceMs) });
      }
      continue;
    }

    const coupleId = doc.ref.parent.parent?.id;
    if (!coupleId) continue;
    const coupleSnap = await db.collection("couples").doc(coupleId).get();
    const memberIds: string[] = coupleSnap.data()?.memberIds ?? [];
    const notifiableMemberIds = visibleMemberIds(memberIds, data.createdBy, data.visibility);

    // remindedUids は発生年が変わったらリセットする（去年の送信済み記録を
    // 今年の判定に持ち越さない）
    const alreadyRemindedUids =
      data.remindedUidsYear === occurrenceYear ? new Set(data.remindedUids ?? []) : new Set<string>();

    const members = await Promise.all(
      notifiableMemberIds.map(async (uid) => {
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

    const { toRemind, fullySettled } = resolveReminderTargets(members, occurrenceMs, nowMs);

    for (const uid of toRemind) {
      const member = members.find((m) => m.uid === uid)!;
      await sendFcm(
        member.fcmToken,
        "まもなく記念日です",
        `「${data.title}」が${formatRelative(member.minutesBefore)}にあります`,
        { type: "reminder", coupleId, eventId: doc.id },
      );
    }

    if (toRemind.length > 0 || fullySettled || needsOccurrenceRefresh) {
      await doc.ref.update({
        ...(toRemind.length > 0 || fullySettled
          ? {
              remindedUids: [...alreadyRemindedUids, ...toRemind],
              remindedUidsYear: occurrenceYear,
              remindedYear: fullySettled ? occurrenceYear : null,
            }
          : {}),
        nextOccurrenceMs: Timestamp.fromMillis(occurrenceMs),
      });
    }
  }
}

// 記念日タブ（AnniversaryHubScreen / couples/{coupleId}/anniversaries）の
// 記念日リマインダー。プロポーズ・入籍・初デートなど複数登録できる記念日は、
// カレンダーの繰り返し予定として登録し直さない限りこれまで通知手段が無く、
// TimeTreeには無いが Between・Twinest 等の移行先候補が持つ「記念日の
// カウントダウン通知」という差別化要素が欠けていた。
//
// 発生日の判定は processRecurringEvents と同じ nextOccurrence を使うが、
// 記念日は時刻ではなく「その日」を祝う概念のため、予定のような
// 「◯分前」の個人設定（reminderMinutesBefore）は使わず、発生時刻ちょうど
// （minutesBefore: 0）をもって通知タイミングとする。オン/オフの設定は
// 予定のリマインダーと共有する（remindersEnabled）。
async function processAnniversaryReminders(nowMs: number): Promise<void> {
  const snap = await db.collectionGroup("anniversaries").get();

  for (const doc of snap.docs) {
    const data = doc.data() as AnniversaryDoc;
    const occurrence = nextOccurrence(data.date.toDate(), nowMs);
    const occurrenceYear = occurrence.getFullYear();
    const occurrenceMs = occurrence.getTime();

    if (data.remindedYear === occurrenceYear) continue;

    const coupleId = doc.ref.parent.parent?.id;
    if (!coupleId) continue;
    const coupleSnap = await db.collection("couples").doc(coupleId).get();
    const memberIds: string[] = coupleSnap.data()?.memberIds ?? [];

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
          minutesBefore: 0,
        };
      }),
    );

    const { toRemind, fullySettled } = resolveReminderTargets(members, occurrenceMs, nowMs);

    for (const uid of toRemind) {
      const member = members.find((m) => m.uid === uid)!;
      await sendFcm(
        member.fcmToken,
        "記念日です",
        `「${data.title}」を迎えました`,
        { type: "anniversary", coupleId, anniversaryId: doc.id },
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
    await processAnniversaryReminders(nowMs);
  },
);

// 「ふたりの質問」（QuestionsScreen / couples/{coupleId}/questionAnswers）は
// 開いて気づかない限り、答え忘れたまま日が変わって終わってしまう。その日まだ
// 回答していないメンバーだけに1日1回リマインドする（question_reminder_logic参照）。
// 全カップルを1日1回走査するだけなので、sendRemindersの15分間隔スケジュールとは
// 分け、専用のスケジュールで実行する。
async function processDailyQuestionReminder(nowMs: number): Promise<void> {
  const dateKey = tokyoDateKey(nowMs);
  const couplesSnap = await db.collection("couples").get();

  for (const coupleDoc of couplesSnap.docs) {
    const memberIds: string[] = coupleDoc.data()?.memberIds ?? [];
    if (memberIds.length === 0) continue;

    const members = await Promise.all(
      memberIds.map(async (uid) => {
        const [userSnap, answerSnap] = await Promise.all([
          db.collection("users").doc(uid).get(),
          db
            .collection("couples")
            .doc(coupleDoc.id)
            .collection("questionAnswers")
            .doc(`${dateKey}_${uid}`)
            .get(),
        ]);
        const user = userSnap.data() as UserDoc | undefined;
        return {
          uid,
          fcmToken: user?.fcmToken,
          answered: answerSnap.exists,
          notifyOnDailyQuestion: !!user && user.notifyOnDailyQuestion !== false,
        };
      }),
    );

    const toRemind = resolveQuestionReminderTargets(members);
    for (const uid of toRemind) {
      const member = members.find((m) => m.uid === uid)!;
      await sendFcm(
        member.fcmToken,
        "今日の質問が届いています",
        "「ふたりの質問」にまだ答えていません。今日の質問に答えてみましょう。",
        { type: "question", coupleId: coupleDoc.id },
      );
    }
  }
}

export const sendDailyQuestionReminder = onSchedule(
  { schedule: "0 20 * * *", timeZone: "Asia/Tokyo" },
  async () => {
    await processDailyQuestionReminder(Date.now());
  },
);

// ── ゴミ箱の自動削除: 論理削除から保持期間を過ぎた予定を完全に消す ──
// deletedAtへの範囲クエリのみ（他フィールドとの複合条件が無い）なので、
// 単一フィールドの自動インデックスだけで動く。複合インデックスの
// 追加デプロイは不要。
async function purgeDeletedEvents(nowMs: number): Promise<void> {
  const cutoff = Timestamp.fromMillis(nowMs - TRASH_RETENTION_MS);
  const snap = await db.collectionGroup("events").where("deletedAt", "<=", cutoff).get();
  await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
}

export const purgeTrash = onSchedule(
  { schedule: "every 24 hours", timeZone: "Asia/Tokyo" },
  async () => {
    await purgeDeletedEvents(Date.now());
  },
);

// ── カップルのメンバーかどうかをFirestoreを読んで判定する ──────────
// 招待コードを知っているだけの非メンバーからの呼び出しを弾く。
// askGemini・dissolveCoupleの共通ヘルパー。
async function checkCoupleMembership(coupleId: string, uid: string): Promise<boolean> {
  const snap = await db.collection("couples").doc(coupleId).get();
  const memberIds: string[] = (snap.data()?.memberIds as string[] | undefined) ?? [];
  return isCoupleMember(memberIds, uid);
}

// ── AIチャット: Gemini呼び出しをサーバー側に隠す ──────────────
// 以前はAPIキーを --dart-define でビルドへ渡していたが、これはソースへの
// 直書きを防ぐだけでAPKからは抽出できる。抜かれると他人に課金され、
// 止める手段も無い（docs/open-issues.md 課題2）。
// キーはSecret Managerに置き、呼び出しは認証済み・カップルのメンバーに限り、
// 1日あたりの呼び出し回数もここで制限する。
const geminiApiKey = defineSecret("GEMINI_API_KEY");

interface RateLimitDoc {
  aiCallDate?: string;
  aiCallCount?: number;
}

/**
 * 1日あたりの呼び出し回数を users/{uid} に記録しながら判定する。
 * トランザクションにすることで、素早い連打でも上限を超えて通さない。
 * 許可した場合だけカウントを書き戻す（拒否時は書き込まない）。
 */
async function checkAndConsumeRateLimit(uid: string, todayStr: string): Promise<boolean> {
  const ref = db.collection("users").doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() as RateLimitDoc | undefined;
    const current: RateLimitState | undefined = data?.aiCallDate
      ? { date: data.aiCallDate, count: data.aiCallCount ?? 0 }
      : undefined;

    if (isOverLimit(current, todayStr)) return false;

    const next = nextRateLimitState(current, todayStr);
    tx.set(ref, { aiCallDate: next.date, aiCallCount: next.count }, { merge: true });
    return true;
  });
}

interface AskGeminiRequest {
  coupleId?: unknown;
  contents?: unknown;
}

export const askGemini = onCall<AskGeminiRequest>(
  { secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const uid = request.auth.uid;
    const { coupleId, contents } = request.data ?? {};

    if (typeof coupleId !== "string" || coupleId.length === 0 || !validateContents(contents)) {
      throw new HttpsError("invalid-argument", "リクエストの形式が不正です");
    }

    const isMember = await checkCoupleMembership(coupleId, uid);
    if (!isMember) {
      throw new HttpsError("permission-denied", "このカップルのメンバーではありません");
    }

    // Asia/TokyoでのYYYY-MM-DD。sv-SEロケールがこの並びで整形してくれる。
    const todayStr = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Tokyo" }).format(
      new Date(),
    );
    const allowed = await checkAndConsumeRateLimit(uid, todayStr);
    if (!allowed) {
      throw new HttpsError("resource-exhausted", "AIの利用上限に達しました");
    }

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      logger.error("askGemini: GEMINI_API_KEYシークレットが空です。Secret Managerへの登録と再デプロイが必要です");
      throw new HttpsError("failed-precondition", "AIのAPIキーが設定されていません");
    }

    const result = await callGeminiApi(contents as GeminiContent[], apiKey);
    if (!result.ok) {
      // 利用者へ返せるのはHttpsErrorのcodeだけなので、原因はここでログへ残す。
      // これが無いと「AIとの通信でエラーが発生しました」から先を追えない。
      logger.error(`askGemini: ${result.detail}`, { kind: result.kind, uid });
      throw new HttpsError(result.kind, "AIとの通信でエラーが発生しました");
    }

    return { text: result.text };
  },
);

// ── バグ報告・機能要望フォーム ───────────────────────────
// 設定画面から自由記述で送られてきた内容を、Geminiで「バグ報告」
// 「機能要望」「それ以外（無効）」に厳格に分類し、有効なものだけを
// bugReportsコレクションへ書き込む。書き込みはこの関数（Admin SDK）
// からのみ行い、クライアントからの直接書き込みはfirestore.rulesで拒否している
// （分類を経ずに偽の報告をキューへ紛れ込ませられないようにするため）。
// ストックされた内容は、別の自動化ワークフロー（fix-bug-reports.yml）が
// 定期的に読み取り、実装・PR作成・auto-mergeまで行う。

interface BugReportRateLimitDoc {
  reportCallMonth?: string;
  reportCallCount?: number;
}

// isOverLimit/nextRateLimitStateは「日付文字列が変わったらリセットする」
// という汎用ロジックなので、YYYY-MM-DDの代わりにYYYY-MM（月単位）を渡すだけで
// 月次レート制限として再利用できる（askGeminiの日次制限とは別カウント）。
async function checkAndConsumeBugReportRateLimit(uid: string, monthStr: string): Promise<boolean> {
  const ref = db.collection("users").doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() as BugReportRateLimitDoc | undefined;
    const current: RateLimitState | undefined = data?.reportCallMonth
      ? { date: data.reportCallMonth, count: data.reportCallCount ?? 0 }
      : undefined;

    if (isOverLimit(current, monthStr, BUG_REPORT_MONTHLY_LIMIT)) return false;

    const next = nextRateLimitState(current, monthStr);
    tx.set(ref, { reportCallMonth: next.date, reportCallCount: next.count }, { merge: true });
    return true;
  });
}

interface SubmitBugReportRequest {
  text?: unknown;
}

export const submitBugReport = onCall<SubmitBugReportRequest>(
  { secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const uid = request.auth.uid;
    const { text } = request.data ?? {};

    if (!validateReportText(text)) {
      throw new HttpsError("invalid-argument", "内容を5〜2000文字で入力してください");
    }

    // Asia/TokyoでのYYYY-MM。sv-SEロケールがYYYY-MM-DDで整形するのでスライスする。
    const monthStr = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Tokyo" })
      .format(new Date())
      .slice(0, 7);
    const allowed = await checkAndConsumeBugReportRateLimit(uid, monthStr);
    if (!allowed) {
      throw new HttpsError("resource-exhausted", "今月の送信回数の上限に達しました");
    }

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      logger.error("submitBugReport: GEMINI_API_KEYシークレットが空です。Secret Managerへの登録と再デプロイが必要です");
      throw new HttpsError("failed-precondition", "AIのAPIキーが設定されていません");
    }

    const result = await callGeminiApi(buildTriageContents(text), apiKey);
    if (!result.ok) {
      logger.error(`submitBugReport: ${result.detail}`, { kind: result.kind, uid });
      throw new HttpsError(result.kind, "判定処理でエラーが発生しました");
    }

    const triage = parseTriageResponse(result.text);
    if (!triage) {
      logger.error("submitBugReport: 判定結果をJSONとして解釈できませんでした", { uid });
      throw new HttpsError("internal", "判定結果を解釈できませんでした");
    }

    // invalidでも必ず記録を残す。以前はFirestoreへ一切書かずに戻っていたが、
    // それだと報告が跡形もなく消えていた（アプリの「送った報告」にも出ず、
    // Issueも起票されず、ログにも残らない）。分類プロンプトは
    // 「判断に迷う場合はinvalidに倒す」「既存機能の削除・無効化を求める要望は
    // invalid」と明示的にinvalid寄りにしてあるため、正当な機能要望が
    // invalidへ落ちることは十分に起こり得る。捨てずに残しておけば、
    // 本人が「送った報告」で見送りとして確認でき、拾い直しもできる。
    const accepted = triage.classification !== "invalid";
    const ref = await db.collection("bugReports").add({
      rawText: text,
      summary: triage.summary,
      classification: triage.classification,
      // invalidは自動実装のキュー（pending）へ積まず、最初から見送り扱いにする。
      status: accepted ? "pending" : "rejected",
      ...(accepted
        ? {}
        : {
            rejectCategory: "unclear",
            reason: "AIの判定で対象外と判断されました。内容を具体的にして送り直すこともできます",
          }),
      createdBy: uid,
      createdAt: Timestamp.now(),
    });

    return {
      accepted,
      classification: triage.classification,
      summary: triage.summary,
      // 画像の添付は受理された報告にだけ許す（クライアントもacceptedのときしか呼ばない）。
      ...(accepted ? { id: ref.id } : {}),
    };
  },
);

// ── バグ報告・機能要望に画像を添付する ──────────────────────
// submitBugReportが受理した報告（accepted: true）に対してのみ呼ぶ。
// bugReportsはfirestore.rulesでクライアントからの書き込みを一切拒否している
// （Gemini判定を経ない内容が紛れ込むのを防ぐため）ため、画像の添付も
// このAdmin SDK経由の専用関数を介す。画像自体はStorageへ直接アップロード
// 済みで、ここではURLをbugReportsドキュメントへ書き戻すだけ。
// storage.rulesの`bugReports/{reportId}/**`は、そのreportIdのcreatedByと
// 一致するユーザーしかアップロードできないようFirestoreを参照して制限して
// いるため、他人の報告IDへ画像を投げ込むこと自体がStorage側でも防がれる。
interface AttachBugReportImagesRequest {
  reportId?: unknown;
  imageUrls?: unknown;
}

export const attachBugReportImages = onCall<AttachBugReportImagesRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const uid = request.auth.uid;
  const { reportId, imageUrls } = request.data ?? {};

  if (typeof reportId !== "string" || reportId.length === 0) {
    throw new HttpsError("invalid-argument", "リクエストの形式が不正です");
  }
  if (!validateImageUrls(imageUrls)) {
    throw new HttpsError("invalid-argument", `画像は1〜${MAX_BUG_REPORT_IMAGES}件のURLで指定してください`);
  }

  const ref = db.collection("bugReports").doc(reportId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "報告が見つかりません");
  }
  if (snap.data()?.createdBy !== uid) {
    throw new HttpsError("permission-denied", "この報告に画像を添付する権限がありません");
  }

  await ref.update({ imageUrls });
  return { ok: true };
});

// ── ペアの解消: カップルの共有データをすべて削除する ──────────
// 「ペアを解消する」は、片方の操作で相手のデータだけ残す・自分だけ抜ける、
// ではなく、共有してきたデータ（予定・チャット・写真・TODO・
// ふたりの質問への回答）を両者ぶんまとめて完全に削除する仕様
// （docs/open-issues.md 課題4）。
//
// questionAnswersはクライアントからは削除できない設計
// （firestore.rulesにallow deleteが無い。相手の回答を見た後に自分の回答を
// 書き換える抜け道を防ぐため）。解消のときだけはAdmin SDK経由でまとめて
// 消す必要があるため、複数コレクションにまたがる削除をCloud Functionに
// 寄せている（クライアント側で1コレクションずつ消すと、途中で失敗したときに
// 中途半端な状態が残りやすいという理由もある）。
interface DissolveCoupleRequest {
  coupleId?: unknown;
}

export const dissolveCouple = onCall<DissolveCoupleRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const uid = request.auth.uid;
  const { coupleId } = request.data ?? {};

  if (typeof coupleId !== "string" || coupleId.length === 0) {
    throw new HttpsError("invalid-argument", "リクエストの形式が不正です");
  }

  const isMember = await checkCoupleMembership(coupleId, uid);
  if (!isMember) {
    throw new HttpsError("permission-denied", "このカップルのメンバーではありません");
  }

  // Storageの写真はFirestoreと別の保管先なので、個別に消す必要がある。
  // 写真が1枚も無いカップルでも空振りするだけでエラーにはならない。
  await getStorage().bucket().deleteFiles({ prefix: `couples/${coupleId}/`, force: true });

  // inviteCodes/{code} は couples のサブコレクションではなく別の
  // トップレベルコレクションなので、recursiveDeleteの対象に入らない。
  // 消し忘れると、解消済みのcoupleIdを指すミラーだけが孤立して残り、
  // そのコードで参加しようとした人が「couplesドキュメントが無いのに
  // 更新しようとして失敗する」という分かりにくいエラーになる。
  // couples本体を消す前にinviteCodeを読み、対応するミラーも合わせて消す。
  const coupleSnapForInviteCode = await db.collection("couples").doc(coupleId).get();
  const inviteCode = coupleSnapForInviteCode.data()?.inviteCode as string | undefined;
  if (inviteCode) {
    await db.collection("inviteCodes").doc(inviteCode).delete();
  }

  // couples/{coupleId} とその配下（events/chats/todos/
  // questionAnswers/googleCalendarCache）をまとめて削除する。
  await db.recursiveDelete(db.collection("couples").doc(coupleId));

  return { success: true };
});

// ── 外部カレンダー連携（iCalendar購読フィード）────────────────────
// TimeTreeは「設定 → カレンダー情報 → iCal URLをコピー」で、Googleカレンダーや
// Appleカレンダーへ読み取り専用でURL購読できるが、AIMARUはこれまでICSの取り込み
// （ics_import_screen.dart）しか持たず、外へ公開する方向（export/購読）が
// 無かった（2026年9月時点の競合調査）。
//
// トークンは users/{uid}/private/calendarFeed に保存する。users/{userId}本体は
// firestore.rulesで認証済みなら誰でもreadできる設計のため、そこへ秘密のトークンを
// 直接置くと、カップル外の第三者にも読めてしまう。privateサブコレクションは
// クライアントからの読み書きを一切拒否し（allow read, write: if false）、
// このファイルのCloud Functions（Admin SDK）からのみ触る。
interface CalendarFeedTokenDoc {
  token?: string;
}

function calendarFeedTokenRef(uid: string) {
  return db.collection("users").doc(uid).collection("private").doc("calendarFeed");
}

async function ensureCalendarFeedToken(uid: string): Promise<string> {
  const ref = calendarFeedTokenRef(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = (snap.data() as CalendarFeedTokenDoc | undefined)?.token;
    if (existing) return existing;

    const token = generateFeedToken();
    tx.set(ref, { token, createdAt: Timestamp.now() });
    return token;
  });
}

function calendarFeedUrlFor(uid: string, token: string): string {
  return buildCalendarFeedUrl(process.env.GCLOUD_PROJECT ?? "aimaru-7eb2e", uid, token);
}

// 既存のトークンがあれば使い回し、無ければ発行してURLを返す。
export const getCalendarFeedUrl = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const uid = request.auth.uid;
  const token = await ensureCalendarFeedToken(uid);
  return { url: calendarFeedUrlFor(uid, token) };
});

// 今のリンクを無効化し、新しいトークンでURLを発行し直す。リンクを誤って
// 共有してしまった場合の取り消し手段（トークン自体には有効期限を設けていない）。
export const regenerateCalendarFeedUrl = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const uid = request.auth.uid;
  const token = generateFeedToken();
  await calendarFeedTokenRef(uid).set({ token, createdAt: Timestamp.now() });
  return { url: calendarFeedUrlFor(uid, token) };
});

interface CalendarFeedEventDoc {
  title: string;
  date: Timestamp;
  endDate?: Timestamp | null;
  createdBy: string;
  recurring?: boolean;
  allDay?: boolean;
  location?: string | null;
  memo?: string | null;
  deletedAt?: Timestamp | null;
  visibility?: string;
}

// GoogleカレンダーやAppleカレンダーの「URLで購読」から直接叩かれる、認証を
// 経由しない公開エンドポイント。uid+tokenの組が正しい場合のみ、そのuidが
// 見てよい予定（visibility違反禁止はisVisibleToFeedOwner参照）をICSで返す。
export const calendarFeed = onRequest(async (req, res) => {
  const uid = typeof req.query.uid === "string" ? req.query.uid : undefined;
  const token = typeof req.query.token === "string" ? req.query.token : undefined;
  if (!uid || !token) {
    res.status(400).send("invalid request");
    return;
  }

  const tokenSnap = await calendarFeedTokenRef(uid).get();
  const storedToken = (tokenSnap.data() as CalendarFeedTokenDoc | undefined)?.token;
  if (!storedToken || storedToken !== token) {
    res.status(403).send("invalid token");
    return;
  }

  const coupleSnap = await db
    .collection("couples")
    .where("memberIds", "array-contains", uid)
    .limit(1)
    .get();

  const feedEvents: FeedEvent[] = [];
  if (!coupleSnap.empty) {
    const eventsSnap = await coupleSnap.docs[0].ref.collection("events").get();
    for (const doc of eventsSnap.docs) {
      const data = doc.data() as CalendarFeedEventDoc;
      if (data.deletedAt) continue;
      if (!isVisibleToFeedOwner(data.visibility, data.createdBy, uid)) continue;

      feedEvents.push({
        id: doc.id,
        title: data.title,
        start: data.date.toDate(),
        end: data.endDate ? data.endDate.toDate() : null,
        allDay: !!data.allDay,
        recurring: !!data.recurring,
        location: data.location ?? null,
        memo: data.memo ?? null,
      });
    }
  }

  res.set("Content-Type", "text/calendar; charset=utf-8");
  res.set("Cache-Control", "private, max-age=900");
  res.send(buildIcsCalendar(feedEvents, Date.now()));
});
