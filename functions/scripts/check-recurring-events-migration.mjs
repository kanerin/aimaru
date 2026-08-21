#!/usr/bin/env node
// ── 課題8フェーズ3の前提確認: nextOccurrenceMsの書き戻しが行き渡ったか ──
// processRecurringEvents（functions/src/index.ts）は毎年繰り返す予定を
// collectionGroup("events").where("recurring", "==", true) で全件走査し、
// 実行のたびに nextOccurrenceMs へ発生日時を書き戻す。絞り込みが無いため、
// このコード（PR #41）がデプロイされ、スケジュール関数（15分間隔）が
// 1回でも走れば全件に行き渡るはずだが、「実際にデプロイされ、走ったか」は
// 本番Firestoreを見ないと確認できない。フェーズ3（クエリへの
// where("nextOccurrenceMs", "<=", ...) narrowing追加）に進む前に、
// このスクリプトで未設定件数が0であることを確認すること。
//
// GOOGLE_APPLICATION_CREDENTIALS に FIREBASE_SERVICE_ACCOUNT_KEY を
// 書き出したファイルを指定して実行する（他のscripts/*.mjsと同じ資格情報）。
//
// 使い方: node scripts/check-recurring-events-migration.mjs
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

const snap = await db.collectionGroup("events").where("recurring", "==", true).get();

let deleted = 0;
let missing = 0;
let migrated = 0;

for (const doc of snap.docs) {
  const data = doc.data();
  if (data.deletedAt) {
    // processRecurringEvents はゴミ箱の予定を書き戻し対象から除外するため、
    // ここでも母数から除く
    deleted++;
    continue;
  }
  if (data.nextOccurrenceMs == null) {
    missing++;
  } else {
    migrated++;
  }
}

const result = {
  totalRecurring: snap.size,
  excludedDeleted: deleted,
  migrated,
  missing,
  readyForPhase3Narrowing: missing === 0,
};

process.stdout.write(JSON.stringify(result, null, 2));
process.stdout.write("\n");
