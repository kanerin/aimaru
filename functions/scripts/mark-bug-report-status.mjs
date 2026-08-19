#!/usr/bin/env node
// ── バグ報告・機能要望の処理状況を更新する ─────────────────────
// fix-bug-reports.yml（自動実装ワークフロー）から、Claude Codeが
// Bashツールで実行する想定。GOOGLE_APPLICATION_CREDENTIALS の設定は
// list-pending-bug-reports.mjs と同じ。
//
// 使い方:
//   node scripts/mark-bug-report-status.mjs <reportId> in_progress
//   node scripts/mark-bug-report-status.mjs <reportId> done --pr 42
//   node scripts/mark-bug-report-status.mjs <reportId> rejected --reason "既存機能で対応済みのため"
//
// status は pending | in_progress | done | rejected のいずれか。
// 着手する前に必ず in_progress を書き込むこと（複数回のワークフロー実行が
// 同じ報告を重複して着手するのを防ぐロック代わりになる）。
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const VALID_STATUSES = ["pending", "in_progress", "done", "rejected"];

const [, , reportId, status, ...rest] = process.argv;

if (!reportId || !VALID_STATUSES.includes(status)) {
  console.error(
    `使い方: node mark-bug-report-status.mjs <reportId> <${VALID_STATUSES.join("|")}> [--pr <number>] [--reason <text>]`,
  );
  process.exit(1);
}

let prNumber;
let reason;
for (let i = 0; i < rest.length; i++) {
  if (rest[i] === "--pr") prNumber = Number(rest[++i]);
  if (rest[i] === "--reason") reason = rest[++i];
}

initializeApp();
const db = getFirestore();

const update = { status, updatedAt: FieldValue.serverTimestamp() };
if (prNumber !== undefined && !Number.isNaN(prNumber)) update.prNumber = prNumber;
if (reason !== undefined) update.reason = reason;

const ref = db.collection("bugReports").doc(reportId);
const snap = await ref.get();
if (!snap.exists) {
  console.error(`bugReports/${reportId} が見つかりません`);
  process.exit(1);
}

await ref.set(update, { merge: true });
console.log(`bugReports/${reportId} を ${status} に更新しました`);
