import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import { TRASH_RETENTION_MS } from "./trash_logic";

// ゴミ箱の自動削除（purgeTrash）の「Firestoreを読んで、保持期限を過ぎた
// ものだけ完全に削除する」経路のテスト。判定そのものは trash_logic.test.ts
// が純粋関数として検証している。
//
// FIRESTORE_EMULATOR_HOST が無い場合はスキップする。
const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;

const COUPLE_ID = "couple-x";

let app: ReturnType<typeof initializeApp> | undefined;
let db: FirebaseFirestore.Firestore;

/** 本番の purgeDeletedEvents と同じクエリ・削除ロジックを再現する。 */
async function purgeDeletedEvents(nowMs: number): Promise<string[]> {
  const cutoff = Timestamp.fromMillis(nowMs - TRASH_RETENTION_MS);
  const snap = await db.collectionGroup("events").where("deletedAt", "<=", cutoff).get();
  await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
  return snap.docs.map((doc) => doc.id);
}

describe("ゴミ箱のFirestore経路", { skip: EMULATOR ? false : "エミュレータ未起動" }, () => {
  before(() => {
    app = initializeApp({ projectId: "aimaru-test" }, `it-${Date.now()}`);
    db = getFirestore(app);
    db.settings({ ignoreUndefinedProperties: true });
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  afterEach(async () => {
    const docs = await db.collection("couples").listDocuments();
    await Promise.all(docs.map((d) => db.recursiveDelete(d)));
  });

  it("保持期間を過ぎた論理削除済みの予定だけを完全に削除する", async () => {
    const nowMs = Date.now();
    const eventsRef = db.collection("couples").doc(COUPLE_ID).collection("events");

    await eventsRef.doc("expired").set({
      title: "期限切れ",
      date: Timestamp.fromDate(new Date(2020, 0, 1)),
      deletedAt: Timestamp.fromMillis(nowMs - TRASH_RETENTION_MS - 1000),
    });
    await eventsRef.doc("recent").set({
      title: "最近削除",
      date: Timestamp.fromDate(new Date(2020, 0, 1)),
      deletedAt: Timestamp.fromMillis(nowMs - 1000),
    });
    await eventsRef.doc("active").set({
      title: "生きている予定",
      date: Timestamp.fromDate(new Date(2020, 0, 1)),
    });

    const purgedIds = await purgeDeletedEvents(nowMs);

    assert.deepEqual(purgedIds, ["expired"]);

    const remaining = await eventsRef.listDocuments();
    assert.deepEqual(
      remaining.map((d) => d.id).sort(),
      ["active", "recent"],
      "保持期間内のものと、そもそも削除されていないものは残る",
    );
  });
});
