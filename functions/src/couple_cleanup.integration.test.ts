import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import { cleanupLeftoverSoloCouples, deleteCoupleData, StorageBucket } from "./couple_cleanup";

// 残った「自分だけのカップル」の片付けと、それに使うカップルの削除処理の
// テスト。本番と同じ関数に、エミュレータのFirestore・Storageを渡して検証する。
//
// FIRESTORE_EMULATOR_HOST が無い場合はスキップする。
const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;

const USER_A = "user-a";
const USER_B = "user-b";
const USER_C = "user-c";

let app: ReturnType<typeof initializeApp> | undefined;
let db: FirebaseFirestore.Firestore;
let bucket: StorageBucket;

describe("残った自分だけのカップルの片付け", { skip: EMULATOR ? false : "エミュレータ未起動" }, () => {
  before(() => {
    app = initializeApp(
      { projectId: "aimaru-test", storageBucket: "aimaru-test.appspot.com" },
      `it-couple-cleanup-${Date.now()}`,
    );
    db = getFirestore(app);
    bucket = getStorage(app).bucket();
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  afterEach(async () => {
    for (const path of ["couples", "inviteCodes"]) {
      const docs = await db.collection(path).listDocuments();
      await Promise.all(docs.map((d) => db.recursiveDelete(d)));
    }
  });

  async function seedCouple(coupleId: string, memberIds: string[], inviteCode: string) {
    await db.collection("couples").doc(coupleId).set({ memberIds, inviteCode });
    await db.collection("inviteCodes").doc(inviteCode).set({ coupleId, memberIds });
  }

  const cleanup = () =>
    cleanupLeftoverSoloCouples(db, (coupleId) => deleteCoupleData(db, bucket, coupleId));

  async function exists(path: string) {
    return (await db.doc(path).get()).exists;
  }

  it("ペアに入った人に残った自分だけのカップルを、招待コードごと削除する", async () => {
    // Aが招待コードを作り、Bも画面を開いた時点で自分のコードが作られ、
    // そのままAのコードで参加した状態。
    await seedCouple("pair", [USER_A, USER_B], "PAIR22");
    await seedCouple("solo-b", [USER_B], "SOLO22");

    const deleted = await cleanup();

    assert.deepEqual(deleted, ["solo-b"]);
    assert.equal(await exists("couples/solo-b"), false);
    assert.equal(await exists("inviteCodes/SOLO22"), false);
    assert.equal(await exists("couples/pair"), true);
    assert.equal(await exists("inviteCodes/PAIR22"), true);
  });

  it("相手の参加を待っている招待中のカップルは消さない", async () => {
    await seedCouple("pair", [USER_A, USER_B], "PAIR22");
    await seedCouple("waiting", [USER_C], "WAIT22");

    const deleted = await cleanup();

    assert.deepEqual(deleted, []);
    assert.equal(await exists("couples/waiting"), true);
    assert.equal(await exists("inviteCodes/WAIT22"), true);
  });

  it("予定などのデータが入っているものは消さない", async () => {
    await seedCouple("pair", [USER_A, USER_B], "PAIR22");
    await seedCouple("solo-b", [USER_B], "SOLO22");
    await db.collection("couples").doc("solo-b").collection("events").doc("e1").set({ title: "予定" });

    const deleted = await cleanup();

    assert.deepEqual(deleted, []);
    assert.equal(await exists("couples/solo-b"), true);
    assert.equal(await exists("couples/solo-b/events/e1"), true);
  });

  it("deleteCoupleDataはサブコレクション・招待コード・写真をまとめて消し、他のカップルには触れない", async () => {
    await seedCouple("x", [USER_A, USER_B], "XXXX22");
    await seedCouple("y", [USER_C], "YYYY22");
    await db.collection("couples").doc("x").collection("questionAnswers").doc("a").set({ text: "回答" });
    await bucket.file("couples/x/photo.jpg").save(Buffer.from("x"));
    await bucket.file("couples/y/photo.jpg").save(Buffer.from("y"));

    await deleteCoupleData(db, bucket, "x");

    assert.equal(await exists("couples/x"), false);
    assert.equal(await exists("couples/x/questionAnswers/a"), false);
    assert.equal(await exists("inviteCodes/XXXX22"), false);
    assert.equal((await bucket.file("couples/x/photo.jpg").exists())[0], false);
    assert.equal(await exists("couples/y"), true);
    assert.equal(await exists("inviteCodes/YYYY22"), true);
    assert.equal((await bucket.file("couples/y/photo.jpg").exists())[0], true);
  });
});
