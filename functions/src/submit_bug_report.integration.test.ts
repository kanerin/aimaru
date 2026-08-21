import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import { isOverLimit, nextRateLimitState, RateLimitState } from "./gemini_logic";
import { BUG_REPORT_MONTHLY_LIMIT, MAX_BUG_REPORT_IMAGES, validateImageUrls } from "./bug_report_logic";

// submitBugReport の「Firestoreを読み書きする」部分（月次レート制限の
// トランザクション・受理されたレポートの書き込み）のテスト。分類ロジック
// 自体（プロンプト組み立て・Gemini応答のパース）は bug_report_logic.test.ts
// が純粋関数として検証している。
//
// FIRESTORE_EMULATOR_HOST が無い場合はスキップする。
const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;

const USER_A = "user-a";
const USER_B = "user-b";

let app: ReturnType<typeof initializeApp> | undefined;
let db: FirebaseFirestore.Firestore;

interface BugReportRateLimitDoc {
  reportCallMonth?: string;
  reportCallCount?: number;
}

/** 本番の checkAndConsumeBugReportRateLimit と同じトランザクションを再現する。 */
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

/** 本番の「受理された報告をbugReportsへ書き込む」処理を再現する。 */
async function storeAcceptedReport(
  uid: string,
  rawText: string,
  classification: "bug" | "feature_request",
  summary: string,
): Promise<string> {
  const ref = await db.collection("bugReports").add({
    rawText,
    summary,
    classification,
    status: "pending",
    createdBy: uid,
    createdAt: Timestamp.now(),
  });
  return ref.id;
}

type AttachImagesResult =
  | { ok: true }
  | { ok: false; reason: "invalid-argument" | "not-found" | "permission-denied" };

/** 本番の attachBugReportImages の「Firestoreを読み書きする」部分を再現する。 */
async function attachImages(
  uid: string,
  reportId: string,
  imageUrls: unknown,
): Promise<AttachImagesResult> {
  if (!validateImageUrls(imageUrls)) {
    return { ok: false, reason: "invalid-argument" };
  }
  const ref = db.collection("bugReports").doc(reportId);
  const snap = await ref.get();
  if (!snap.exists) {
    return { ok: false, reason: "not-found" };
  }
  if (snap.data()?.createdBy !== uid) {
    return { ok: false, reason: "permission-denied" };
  }
  await ref.update({ imageUrls });
  return { ok: true };
}

describe("submitBugReportのFirestore経路", { skip: EMULATOR ? false : "エミュレータ未起動" }, () => {
  before(() => {
    app = initializeApp({ projectId: "aimaru-test" }, `it-submit-bug-report-${Date.now()}`);
    db = getFirestore(app);
    db.settings({ ignoreUndefinedProperties: true });
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  afterEach(async () => {
    for (const path of ["users", "bugReports"]) {
      const docs = await db.collection(path).listDocuments();
      await Promise.all(docs.map((d) => d.delete()));
    }
  });

  describe("checkAndConsumeBugReportRateLimit", () => {
    it("初回呼び出しは許可し、カウントを1にする", async () => {
      const allowed = await checkAndConsumeBugReportRateLimit(USER_A, "2026-08");
      assert.equal(allowed, true);

      const doc = await db.collection("users").doc(USER_A).get();
      assert.equal(doc.data()?.reportCallMonth, "2026-08");
      assert.equal(doc.data()?.reportCallCount, 1);
    });

    it("askGemini（aiCallCount）とは独立したカウントを持つ", async () => {
      await db.collection("users").doc(USER_A).set({ aiCallDate: "2026-08-19", aiCallCount: 50 });

      const allowed = await checkAndConsumeBugReportRateLimit(USER_A, "2026-08");
      assert.equal(allowed, true, "AIチャットの上限がbugReportの送信に影響してはいけない");

      const doc = await db.collection("users").doc(USER_A).get();
      assert.equal(doc.data()?.aiCallCount, 50, "aiCallCountは変更されない");
      assert.equal(doc.data()?.reportCallCount, 1);
    });

    it(`上限（${BUG_REPORT_MONTHLY_LIMIT}件）に達すると拒否し、カウントは書き換えない`, async () => {
      await db.collection("users").doc(USER_A).set({
        reportCallMonth: "2026-08",
        reportCallCount: BUG_REPORT_MONTHLY_LIMIT,
      });

      const allowed = await checkAndConsumeBugReportRateLimit(USER_A, "2026-08");
      assert.equal(allowed, false);

      const doc = await db.collection("users").doc(USER_A).get();
      assert.equal(doc.data()?.reportCallCount, BUG_REPORT_MONTHLY_LIMIT, "拒否時はカウントを増やさない");
    });

    it("月が変わっていれば、前月の上限到達を引き継がず許可する", async () => {
      await db.collection("users").doc(USER_A).set({
        reportCallMonth: "2026-07",
        reportCallCount: 999,
      });

      const allowed = await checkAndConsumeBugReportRateLimit(USER_A, "2026-08");
      assert.equal(allowed, true);

      const doc = await db.collection("users").doc(USER_A).get();
      assert.equal(doc.data()?.reportCallMonth, "2026-08");
      assert.equal(doc.data()?.reportCallCount, 1);
    });

    it("ユーザーごとに独立してカウントする", async () => {
      await checkAndConsumeBugReportRateLimit(USER_A, "2026-08");
      await checkAndConsumeBugReportRateLimit(USER_A, "2026-08");
      await checkAndConsumeBugReportRateLimit(USER_B, "2026-08");

      const [docA, docB] = await Promise.all([
        db.collection("users").doc(USER_A).get(),
        db.collection("users").doc(USER_B).get(),
      ]);
      assert.equal(docA.data()?.reportCallCount, 2);
      assert.equal(docB.data()?.reportCallCount, 1);
    });
  });

  describe("受理された報告の書き込み", () => {
    it("bug分類がpending状態でbugReportsへ書き込まれる", async () => {
      const id = await storeAcceptedReport(USER_A, "カレンダーが表示されない", "bug", "要約");

      const doc = await db.collection("bugReports").doc(id).get();
      assert.equal(doc.data()?.rawText, "カレンダーが表示されない");
      assert.equal(doc.data()?.classification, "bug");
      assert.equal(doc.data()?.status, "pending");
      assert.equal(doc.data()?.createdBy, USER_A);
    });

    it("feature_request分類も同様に書き込まれる", async () => {
      const id = await storeAcceptedReport(USER_A, "ダークモードが欲しい", "feature_request", "要約");

      const doc = await db.collection("bugReports").doc(id).get();
      assert.equal(doc.data()?.classification, "feature_request");
      assert.equal(doc.data()?.status, "pending");
    });
  });

  describe("attachBugReportImages", () => {
    it("作成者本人は画像URLを添付できる", async () => {
      const id = await storeAcceptedReport(USER_A, "カレンダーが表示されない", "bug", "要約");
      const urls = ["https://example.com/a.jpg", "https://example.com/b.jpg"];

      const result = await attachImages(USER_A, id, urls);

      assert.deepEqual(result, { ok: true });
      const doc = await db.collection("bugReports").doc(id).get();
      assert.deepEqual(doc.data()?.imageUrls, urls);
    });

    it(`上限（${MAX_BUG_REPORT_IMAGES}件）までは添付できる`, async () => {
      const id = await storeAcceptedReport(USER_A, "カレンダーが表示されない", "bug", "要約");
      const urls = Array.from({ length: MAX_BUG_REPORT_IMAGES }, (_, i) => `https://example.com/${i}.jpg`);

      const result = await attachImages(USER_A, id, urls);

      assert.deepEqual(result, { ok: true });
    });

    it(`上限（${MAX_BUG_REPORT_IMAGES}件）を超えると拒否し、書き込まない`, async () => {
      const id = await storeAcceptedReport(USER_A, "カレンダーが表示されない", "bug", "要約");
      const urls = Array.from(
        { length: MAX_BUG_REPORT_IMAGES + 1 },
        (_, i) => `https://example.com/${i}.jpg`,
      );

      const result = await attachImages(USER_A, id, urls);

      assert.deepEqual(result, { ok: false, reason: "invalid-argument" });
      const doc = await db.collection("bugReports").doc(id).get();
      assert.equal(doc.data()?.imageUrls, undefined);
    });

    it("自分の報告でなければ拒否される（他人の報告IDへ画像を投げ込めない）", async () => {
      const id = await storeAcceptedReport(USER_A, "カレンダーが表示されない", "bug", "要約");

      const result = await attachImages(USER_B, id, ["https://example.com/a.jpg"]);

      assert.deepEqual(result, { ok: false, reason: "permission-denied" });
      const doc = await db.collection("bugReports").doc(id).get();
      assert.equal(doc.data()?.imageUrls, undefined);
    });

    it("存在しない報告IDでは拒否される", async () => {
      const result = await attachImages(USER_A, "no-such-report", ["https://example.com/a.jpg"]);

      assert.deepEqual(result, { ok: false, reason: "not-found" });
    });
  });
});
