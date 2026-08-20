import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { HttpsError, onCall } from "firebase-functions/v2/https";
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
} from "./reminder_logic";
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
  BUG_REPORT_DAILY_LIMIT,
  buildTriageContents,
  parseTriageResponse,
  validateReportText,
} from "./bug_report_logic";

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

export const sendReminders = onSchedule(
  { schedule: `every ${CHECK_INTERVAL_MINUTES} minutes`, timeZone: "Asia/Tokyo" },
  async () => {
    const nowMs = Date.now();
    await processOneTimeEvents(nowMs);
    await processRecurringEvents(nowMs);
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
      throw new HttpsError("failed-precondition", "AIのAPIキーが設定されていません");
    }

    const result = await callGeminiApi(contents as GeminiContent[], apiKey);
    if (!result.ok) {
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
  reportCallDate?: string;
  reportCallCount?: number;
}

async function checkAndConsumeBugReportRateLimit(uid: string, todayStr: string): Promise<boolean> {
  const ref = db.collection("users").doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() as BugReportRateLimitDoc | undefined;
    const current: RateLimitState | undefined = data?.reportCallDate
      ? { date: data.reportCallDate, count: data.reportCallCount ?? 0 }
      : undefined;

    if (isOverLimit(current, todayStr, BUG_REPORT_DAILY_LIMIT)) return false;

    const next = nextRateLimitState(current, todayStr);
    tx.set(ref, { reportCallDate: next.date, reportCallCount: next.count }, { merge: true });
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

    const todayStr = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Tokyo" }).format(
      new Date(),
    );
    const allowed = await checkAndConsumeBugReportRateLimit(uid, todayStr);
    if (!allowed) {
      throw new HttpsError("resource-exhausted", "本日の送信回数の上限に達しました");
    }

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      throw new HttpsError("failed-precondition", "AIのAPIキーが設定されていません");
    }

    const result = await callGeminiApi(buildTriageContents(text), apiKey);
    if (!result.ok) {
      throw new HttpsError(result.kind, "判定処理でエラーが発生しました");
    }

    const triage = parseTriageResponse(result.text);
    if (!triage) {
      throw new HttpsError("internal", "判定結果を解釈できませんでした");
    }

    if (triage.classification === "invalid") {
      return { accepted: false, classification: triage.classification, summary: triage.summary };
    }

    await db.collection("bugReports").add({
      rawText: text,
      summary: triage.summary,
      classification: triage.classification,
      status: "pending",
      createdBy: uid,
      createdAt: Timestamp.now(),
    });

    return { accepted: true, classification: triage.classification, summary: triage.summary };
  },
);

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

  // couples/{coupleId} とその配下（events/chats/todos/
  // questionAnswers/googleCalendarCache）をまとめて削除する。
  await db.recursiveDelete(db.collection("couples").doc(coupleId));

  return { success: true };
});
