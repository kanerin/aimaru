import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import { isCoupleMember, isOverLimit, nextRateLimitState, RateLimitState } from "./gemini_logic";

// askGemini の「Firestoreを読んで判定する」部分（カップルメンバー確認・
// 1日あたりの呼び出し回数制限）のテスト。判定そのものは gemini_logic.test.ts
// が純粋関数として検証している。Gemini API自体の呼び出し（callGeminiApi）は
// fetchを差し込めるのでネットワーク無しにgemini_logic.test.tsで検証済み。
//
// FIRESTORE_EMULATOR_HOST が無い場合はスキップする。
const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;

const COUPLE_ID = "couple-x";
const USER_A = "user-a";
const USER_B = "user-b";
const OUTSIDER = "user-outsider";

let app: ReturnType<typeof initializeApp> | undefined;
let db: FirebaseFirestore.Firestore;

interface RateLimitDoc {
  aiCallDate?: string;
  aiCallCount?: number;
}

/** 本番の checkCoupleMembership と同じ判定を再現する。 */
async function checkCoupleMembership(coupleId: string, uid: string): Promise<boolean> {
  const snap = await db.collection("couples").doc(coupleId).get();
  const memberIds: string[] = (snap.data()?.memberIds as string[] | undefined) ?? [];
  return isCoupleMember(memberIds, uid);
}

/** 本番の checkAndConsumeRateLimit と同じトランザクションを再現する。 */
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

describe("askGeminiのFirestore経路", { skip: EMULATOR ? false : "エミュレータ未起動" }, () => {
  before(() => {
    app = initializeApp({ projectId: "aimaru-test" }, `it-ask-gemini-${Date.now()}`);
    db = getFirestore(app);
    db.settings({ ignoreUndefinedProperties: true });
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  afterEach(async () => {
    for (const path of ["users", "couples"]) {
      const docs = await db.collection(path).listDocuments();
      await Promise.all(docs.map((d) => d.delete()));
    }
  });

  describe("checkCoupleMembership", () => {
    it("メンバーならtrue", async () => {
      await db.collection("couples").doc(COUPLE_ID).set({ memberIds: [USER_A, USER_B] });

      assert.equal(await checkCoupleMembership(COUPLE_ID, USER_A), true);
    });

    it("メンバーでなければfalse", async () => {
      await db.collection("couples").doc(COUPLE_ID).set({ memberIds: [USER_A, USER_B] });

      assert.equal(await checkCoupleMembership(COUPLE_ID, OUTSIDER), false);
    });

    it("カップル自体が存在しなければfalse", async () => {
      assert.equal(await checkCoupleMembership("no-such-couple", USER_A), false);
    });
  });

  describe("checkAndConsumeRateLimit", () => {
    it("初回呼び出しは許可し、カウントを1にする", async () => {
      const allowed = await checkAndConsumeRateLimit(USER_A, "2026-08-19");
      assert.equal(allowed, true);

      const doc = await db.collection("users").doc(USER_A).get();
      assert.equal(doc.data()?.aiCallDate, "2026-08-19");
      assert.equal(doc.data()?.aiCallCount, 1);
    });

    it("同じ日に繰り返し呼ぶとカウントが積み上がる", async () => {
      await checkAndConsumeRateLimit(USER_A, "2026-08-19");
      await checkAndConsumeRateLimit(USER_A, "2026-08-19");
      const allowed = await checkAndConsumeRateLimit(USER_A, "2026-08-19");
      assert.equal(allowed, true);

      const doc = await db.collection("users").doc(USER_A).get();
      assert.equal(doc.data()?.aiCallCount, 3);
    });

    it("上限に達すると拒否し、カウントは書き換えない", async () => {
      await db.collection("users").doc(USER_A).set({ aiCallDate: "2026-08-19", aiCallCount: 50 });

      const allowed = await checkAndConsumeRateLimit(USER_A, "2026-08-19");
      assert.equal(allowed, false);

      const doc = await db.collection("users").doc(USER_A).get();
      assert.equal(doc.data()?.aiCallCount, 50, "拒否時はカウントを増やさない");
    });

    it("日付が変わっていれば、前日の上限到達を引き継がず許可する", async () => {
      await db.collection("users").doc(USER_A).set({ aiCallDate: "2026-08-18", aiCallCount: 999 });

      const allowed = await checkAndConsumeRateLimit(USER_A, "2026-08-19");
      assert.equal(allowed, true);

      const doc = await db.collection("users").doc(USER_A).get();
      assert.equal(doc.data()?.aiCallDate, "2026-08-19");
      assert.equal(doc.data()?.aiCallCount, 1);
    });

    it("ユーザーごとに独立してカウントする", async () => {
      await checkAndConsumeRateLimit(USER_A, "2026-08-19");
      await checkAndConsumeRateLimit(USER_A, "2026-08-19");
      await checkAndConsumeRateLimit(USER_B, "2026-08-19");

      const [docA, docB] = await Promise.all([
        db.collection("users").doc(USER_A).get(),
        db.collection("users").doc(USER_B).get(),
      ]);
      assert.equal(docA.data()?.aiCallCount, 2);
      assert.equal(docB.data()?.aiCallCount, 1);
    });
  });
});
