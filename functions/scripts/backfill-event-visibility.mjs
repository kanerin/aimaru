#!/usr/bin/env node
// ── 課題3フェーズ2: 既存のeventsドキュメントにvisibility: 'shared' を書き戻す ──
// EventService._visibilityFilter()（Filter.or）で絞り込むクエリは、
// visibilityフィールドを持たないドキュメントにマッチしない
// （Firestoreは「フィールドが存在しない」ことを等価一致の対象にできないため）。
// フェーズ2のクエリ変更をデプロイする前に、既存ドキュメントへ一度だけ
// このフィールドを補完しておかないと、それらの予定がカレンダーから
// 消えて見える（本番データを壊すわけではないが、表示が壊れる）。
//
// 一度だけ、本番へ手動で実行する想定（FIREBASE_SERVICE_ACCOUNT_KEYと同じ
// 資格情報。GOOGLE_APPLICATION_CREDENTIALSで指定するか、gcloud auth login
// 済みのADCで動く）。
//
// 使い方:
//   node scripts/backfill-event-visibility.mjs --dry-run   件数だけ確認
//   node scripts/backfill-event-visibility.mjs             実際に書き込む
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const dryRun = process.argv.includes("--dry-run");

initializeApp();
const db = getFirestore();

const snap = await db.collectionGroup("events").get();
const missing = snap.docs.filter((doc) => !("visibility" in doc.data()));

console.log(`events総数: ${snap.size}件 / visibility未設定: ${missing.length}件`);

if (missing.length === 0) {
  console.log("補完対象はありません");
  process.exit(0);
}

if (dryRun) {
  console.log("--dry-run のため書き込みは行いません（対象一覧）:");
  for (const doc of missing) {
    console.log(` - ${doc.ref.path}`);
  }
  process.exit(0);
}

// Firestoreの1バッチは500件までのため分割してコミットする
const BATCH_SIZE = 500;
for (let i = 0; i < missing.length; i += BATCH_SIZE) {
  const chunk = missing.slice(i, i + BATCH_SIZE);
  const batch = db.batch();
  for (const doc of chunk) {
    batch.update(doc.ref, { visibility: "shared" });
  }
  await batch.commit();
  console.log(`${Math.min(i + BATCH_SIZE, missing.length)}/${missing.length}件 完了`);
}

console.log("補完完了");
