import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { getBytes, ref, uploadBytes } from "firebase/storage";

import {
  COUPLE_ID,
  USER_A,
  USER_B,
  USER_C,
  createTestEnv,
  seedCouple,
  warmUpRulesEngine,
} from "./helpers.js";

const REPORT_ID = "report-1";

// Storage セキュリティルールのテスト。
//
// 写真はこのアプリで最もプライベートなデータで、URL さえ知られれば
// 取れてしまう状態は避けたい。メンバー判定は Firestore の couples を
// 参照して行うため、Firestore 側にペアを用意してから検証する。
let testEnv;

const bytes = new Uint8Array([0x89, 0x50, 0x4e, 0x47]); // PNG のマジックバイト

before(async () => {
  testEnv = await createTestEnv();
  await warmUpRulesEngine(testEnv);
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await seedCouple(testEnv);
});

const storageFor = (uid) =>
  uid ? testEnv.authenticatedContext(uid).storage() : testEnv.unauthenticatedContext().storage();

describe("couples 配下の画像", () => {
  const path = `couples/${COUPLE_ID}/events/photo.png`;

  it("メンバーはアップロードできる", async () => {
    await assertSucceeds(uploadBytes(ref(storageFor(USER_A), path), bytes));
  });

  it("メンバーは相手がアップロードした画像を読める", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), path), bytes);
    });

    await assertSucceeds(getBytes(ref(storageFor(USER_B), path)));
  });

  it("メンバー以外は読めない", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), path), bytes);
    });

    await assertFails(getBytes(ref(storageFor(USER_C), path)));
  });

  it("メンバー以外は書き込めない", async () => {
    await assertFails(uploadBytes(ref(storageFor(USER_C), path), bytes));
  });

  it("未認証は読み書きできない", async () => {
    await assertFails(uploadBytes(ref(storageFor(null), path), bytes));
  });
});

describe("bugReports 配下の画像", () => {
  const path = `bugReports/${REPORT_ID}/photo.png`;

  async function seedReport(createdBy = USER_A) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`bugReports/${REPORT_ID}`).set({
        rawText: "テスト",
        summary: "要約",
        classification: "bug",
        status: "pending",
        createdBy,
      });
    });
  }

  it("報告の作成者はアップロード・閲覧できる", async () => {
    await seedReport(USER_A);
    await assertSucceeds(uploadBytes(ref(storageFor(USER_A), path), bytes));
    await assertSucceeds(getBytes(ref(storageFor(USER_A), path)));
  });

  it("作成者以外はアップロードできない（自分のカップルの相手であっても）", async () => {
    await seedReport(USER_A);
    await assertFails(uploadBytes(ref(storageFor(USER_B), path), bytes));
  });

  it("作成者以外は読めない", async () => {
    await seedReport(USER_A);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), path), bytes);
    });
    await assertFails(getBytes(ref(storageFor(USER_B), path)));
  });

  it("報告自体が存在しなければアップロードできない", async () => {
    await assertFails(uploadBytes(ref(storageFor(USER_A), `bugReports/no-such-report/photo.png`), bytes));
  });

  it("未認証は読み書きできない", async () => {
    await seedReport(USER_A);
    await assertFails(uploadBytes(ref(storageFor(null), path), bytes));
  });
});

describe("couples 配下以外", () => {
  it("メンバーであっても任意のパスへは置けない", async () => {
    // 書き込み先を couples/ 配下に閉じておかないと、アプリの外から
    // ストレージを物置に使われる余地が残る
    await assertFails(uploadBytes(ref(storageFor(USER_A), "uploads/anything.png"), bytes));
    await assertFails(uploadBytes(ref(storageFor(USER_A), "photo.png"), bytes));
  });
});
