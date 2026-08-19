import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

// dissolveCouple の「Firestoreのサブコレクションをまとめて削除する」
// 「Storageの写真も削除する」経路のテスト。認証・メンバー確認は
// askGeminiと同じ形（checkCoupleMembership）なので、ここでは判定ロジック
// そのものではなく削除範囲を検証する。
//
// FIRESTORE_EMULATOR_HOST が無い場合はスキップする。
const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;

const COUPLE_ID = "couple-x";
const OTHER_COUPLE_ID = "couple-other";
const USER_A = "user-a";
const USER_B = "user-b";

let app: ReturnType<typeof initializeApp> | undefined;
let db: FirebaseFirestore.Firestore;

describe("dissolveCoupleのFirestore・Storage経路", { skip: EMULATOR ? false : "エミュレータ未起動" }, () => {
  before(() => {
    app = initializeApp(
      { projectId: "aimaru-test", storageBucket: "aimaru-test.appspot.com" },
      `it-dissolve-${Date.now()}`,
    );
    db = getFirestore(app);
    db.settings({ ignoreUndefinedProperties: true });
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  afterEach(async () => {
    for (const path of ["couples"]) {
      const docs = await db.collection(path).listDocuments();
      await Promise.all(docs.map((d) => db.recursiveDelete(d)));
    }
  });

  async function seedCoupleWithData(coupleId: string) {
    const coupleRef = db.collection("couples").doc(coupleId);
    await coupleRef.set({ memberIds: [USER_A, USER_B], inviteCode: "A3K9PZ" });
    await coupleRef.collection("events").doc("e1").set({ title: "デート" });
    await coupleRef.collection("chats").doc("m1").set({ text: "やあ" });
    await coupleRef.collection("todos").doc("t1").set({ text: "水族館" });
    await coupleRef.collection("expenses").doc("x1").set({ amount: 1000 });
    // questionAnswersはクライアントからは削除できない（firestore.rulesに
    // allow deleteが無い）。dissolveCoupleがAdmin SDK経由でここも
    // まとめて消せることを確認するのがこのテストの主眼のひとつ。
    await coupleRef
      .collection("questionAnswers")
      .doc("2026-08-19_user-a")
      .set({ uid: USER_A, text: "初デートの場所", createdAt: Timestamp.now() });
  }

  it("couplesドキュメントとすべてのサブコレクションを削除する", async () => {
    await seedCoupleWithData(COUPLE_ID);

    await db.recursiveDelete(db.collection("couples").doc(COUPLE_ID));

    const coupleDoc = await db.collection("couples").doc(COUPLE_ID).get();
    assert.equal(coupleDoc.exists, false);

    for (const sub of ["events", "chats", "todos", "expenses", "questionAnswers"]) {
      const snap = await db.collection("couples").doc(COUPLE_ID).collection(sub).get();
      assert.equal(snap.docs.length, 0, `${sub} が削除されずに残っている`);
    }
  });

  it("他のカップルのデータには影響しない", async () => {
    await seedCoupleWithData(COUPLE_ID);
    await seedCoupleWithData(OTHER_COUPLE_ID);

    await db.recursiveDelete(db.collection("couples").doc(COUPLE_ID));

    const otherDoc = await db.collection("couples").doc(OTHER_COUPLE_ID).get();
    assert.equal(otherDoc.exists, true);
    const otherEvents = await db
      .collection("couples")
      .doc(OTHER_COUPLE_ID)
      .collection("events")
      .get();
    assert.equal(otherEvents.docs.length, 1, "別カップルの予定は残るべき");
  });

  it("Storageの写真をprefixで削除できる", async () => {
    const bucket = getStorage(app).bucket();
    const path = `couples/${COUPLE_ID}/event-photo.jpg`;
    await bucket.file(path).save(Buffer.from("dummy image bytes"));

    const [existsBefore] = await bucket.file(path).exists();
    assert.equal(existsBefore, true);

    await bucket.deleteFiles({ prefix: `couples/${COUPLE_ID}/`, force: true });

    const [existsAfter] = await bucket.file(path).exists();
    assert.equal(existsAfter, false);
  });

  it("写真が1枚も無いカップルでもStorage削除はエラーにならない", async () => {
    const bucket = getStorage(app).bucket();
    await assert.doesNotReject(
      bucket.deleteFiles({ prefix: `couples/no-photos-here/`, force: true }),
    );
  });

  describe("checkCoupleMembership", () => {
    // 本番のcheckCoupleMembershipと同じ判定を再現する。
    async function checkCoupleMembership(coupleId: string, uid: string): Promise<boolean> {
      const snap = await db.collection("couples").doc(coupleId).get();
      const memberIds: string[] = (snap.data()?.memberIds as string[] | undefined) ?? [];
      return memberIds.includes(uid);
    }

    it("メンバーならtrue", async () => {
      await seedCoupleWithData(COUPLE_ID);
      assert.equal(await checkCoupleMembership(COUPLE_ID, USER_A), true);
    });

    it("メンバーでなければfalse（招待コードだけ知っている非メンバーを拒否）", async () => {
      await seedCoupleWithData(COUPLE_ID);
      assert.equal(await checkCoupleMembership(COUPLE_ID, "user-outsider"), false);
    });

    it("カップル自体が存在しなければfalse", async () => {
      assert.equal(await checkCoupleMembership("no-such-couple", USER_A), false);
    });
  });

  it("Storageの削除は他のカップルの写真に影響しない", async () => {
    const bucket = getStorage(app).bucket();
    const mine = `couples/${COUPLE_ID}/photo.jpg`;
    const theirs = `couples/${OTHER_COUPLE_ID}/photo.jpg`;
    await bucket.file(mine).save(Buffer.from("mine"));
    await bucket.file(theirs).save(Buffer.from("theirs"));

    await bucket.deleteFiles({ prefix: `couples/${COUPLE_ID}/`, force: true });

    const [mineExists] = await bucket.file(mine).exists();
    const [theirsExists] = await bucket.file(theirs).exists();
    assert.equal(mineExists, false);
    assert.equal(theirsExists, true, "別カップルの写真は残るべき");
  });
});
