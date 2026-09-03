import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import { resolveQuestionReminderTargets, tokyoDateKey } from "./question_reminder_logic";

// デイリー質問リマインダーの「Firestore を読んで、まだ回答していないメンバーを
// 判定する」経路のテスト。question_reminder_logic.test.ts は判定そのものを
// 純粋関数として検証しているので、こちらが見るのはその外側
// （questionAnswersのドキュメントIDから正しく回答済みかどうかを判定できるか）。
//
// FIRESTORE_EMULATOR_HOST が無い場合はスキップする（純粋関数のテストは
// エミュレータ無しでも回したいため、実行を止めない）。
const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;

const COUPLE_ID = "couple-x";
const USER_A = "user-a";
const USER_B = "user-b";

let app: ReturnType<typeof initializeApp> | undefined;
let db: FirebaseFirestore.Firestore;

/** 本番の processDailyQuestionReminder と同じ順序で、送信対象を数える。 */
async function runDailyQuestionReminderPass(nowMs: number) {
  const dateKey = tokyoDateKey(nowMs);
  const couplesSnap = await db.collection("couples").get();
  const sent: Array<{ coupleId: string; uid: string }> = [];

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
        const user = userSnap.data() as { notifyOnDailyQuestion?: boolean } | undefined;
        return {
          uid,
          answered: answerSnap.exists,
          notifyOnDailyQuestion: !!user && user.notifyOnDailyQuestion !== false,
        };
      }),
    );

    const toRemind = resolveQuestionReminderTargets(members);
    for (const uid of toRemind) sent.push({ coupleId: coupleDoc.id, uid });
  }

  return sent;
}

describe("デイリー質問リマインダーのFirestore経路", { skip: EMULATOR ? false : "エミュレータ未起動" }, () => {
  before(() => {
    app = initializeApp({ projectId: "aimaru-test" }, `it-daily-question-${Date.now()}`);
    db = getFirestore(app);
    db.settings({ ignoreUndefinedProperties: true });
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  afterEach(async () => {
    for (const path of ["users", "couples"]) {
      const docs = await db.collection(path).listDocuments();
      await Promise.all(docs.map((d) => db.recursiveDelete(d)));
    }
  });

  async function seedCouple(users: Record<string, { notifyOnDailyQuestion?: boolean }>) {
    await db.collection("couples").doc(COUPLE_ID).set({
      memberIds: Object.keys(users),
      inviteCode: "A3K9PZ",
    });
    for (const [uid, settings] of Object.entries(users)) {
      await db.collection("users").doc(uid).set({ displayName: uid, fcmToken: `token-${uid}`, ...settings });
    }
  }

  async function seedAnswer(dateKey: string, uid: string) {
    await db
      .collection("couples")
      .doc(COUPLE_ID)
      .collection("questionAnswers")
      .doc(`${dateKey}_${uid}`)
      .set({ coupleId: COUPLE_ID, dateKey, uid, text: "回答", createdAt: new Date() });
  }

  it("誰も回答していなければ両方に通知する", async () => {
    const nowMs = new Date(2026, 7, 12, 20, 0).getTime();
    await seedCouple({ [USER_A]: {}, [USER_B]: {} });

    const sent = await runDailyQuestionReminderPass(nowMs);

    assert.deepEqual(new Set(sent.map((s) => s.uid)), new Set([USER_A, USER_B]));
  });

  it("回答済みのメンバーには送らない", async () => {
    const nowMs = new Date(2026, 7, 12, 20, 0).getTime();
    await seedCouple({ [USER_A]: {}, [USER_B]: {} });
    await seedAnswer(tokyoDateKey(nowMs), USER_A);

    const sent = await runDailyQuestionReminderPass(nowMs);

    assert.deepEqual(sent.map((s) => s.uid), [USER_B]);
  });

  it("両方回答済みなら誰にも送らない", async () => {
    const nowMs = new Date(2026, 7, 12, 20, 0).getTime();
    await seedCouple({ [USER_A]: {}, [USER_B]: {} });
    const dateKey = tokyoDateKey(nowMs);
    await seedAnswer(dateKey, USER_A);
    await seedAnswer(dateKey, USER_B);

    const sent = await runDailyQuestionReminderPass(nowMs);

    assert.deepEqual(sent, []);
  });

  it("notifyOnDailyQuestionがfalseのメンバーには送らない", async () => {
    const nowMs = new Date(2026, 7, 12, 20, 0).getTime();
    await seedCouple({
      [USER_A]: { notifyOnDailyQuestion: false },
      [USER_B]: {},
    });

    const sent = await runDailyQuestionReminderPass(nowMs);

    assert.deepEqual(sent.map((s) => s.uid), [USER_B]);
  });

  it("昨日の回答は今日の判定に影響しない", async () => {
    const nowMs = new Date(2026, 7, 12, 20, 0).getTime();
    await seedCouple({ [USER_A]: {} });
    await seedAnswer("2026-08-11", USER_A);

    const sent = await runDailyQuestionReminderPass(nowMs);

    assert.deepEqual(sent.map((s) => s.uid), [USER_A]);
  });
});
