#!/usr/bin/env node
// ── バグ報告・機能要望の処理状況を更新する ─────────────────────
// fix-bug-reports.yml（自動実装ワークフロー）から、Claude Codeが
// Bashツールで実行する想定。GOOGLE_APPLICATION_CREDENTIALS の設定は
// list-pending-bug-reports.mjs と同じ。
//
// 使い方:
//   node scripts/mark-bug-report-status.mjs <reportId> in_progress
//   node scripts/mark-bug-report-status.mjs <reportId> done --pr 42
//   node scripts/mark-bug-report-status.mjs <reportId> rejected --category unclear --reason "内容が具体的でなかったため"
//
// status は pending | in_progress | done | rejected のいずれか。
// 着手する前に必ず in_progress を書き込むこと（複数回のワークフロー実行が
// 同じ報告を重複して着手するのを防ぐロック代わりになる）。
//
// rejected のときは --category が必須。アプリ側（BugReportRecord.rejectCategory）
// が固定のラベルに変換して表示するため、ここで定義した値以外は使わないこと。
// lib/models/models.dart の bugReportRejectCategoryLabels と一致させること。
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const VALID_STATUSES = ["pending", "in_progress", "done", "rejected"];
const VALID_REJECT_CATEGORIES = ["already_done", "unclear", "out_of_scope", "duplicate", "other"];

const [, , reportId, status, ...rest] = process.argv;

if (!reportId || !VALID_STATUSES.includes(status)) {
  console.error(
    `使い方: node mark-bug-report-status.mjs <reportId> <${VALID_STATUSES.join("|")}> [--pr <number>] [--category <category>] [--reason <text>]`,
  );
  process.exit(1);
}

let prNumber;
let category;
let reason;
for (let i = 0; i < rest.length; i++) {
  if (rest[i] === "--pr") prNumber = Number(rest[++i]);
  if (rest[i] === "--category") category = rest[++i];
  if (rest[i] === "--reason") reason = rest[++i];
}

if (status === "rejected") {
  if (!category || !VALID_REJECT_CATEGORIES.includes(category)) {
    console.error(
      `rejected にする場合は --category を <${VALID_REJECT_CATEGORIES.join("|")}> のいずれかで指定してください`,
    );
    process.exit(1);
  }
}

initializeApp();
const db = getFirestore();

const update = { status, updatedAt: FieldValue.serverTimestamp() };
if (prNumber !== undefined && !Number.isNaN(prNumber)) update.prNumber = prNumber;
if (category !== undefined) update.rejectCategory = category;
if (reason !== undefined) update.reason = reason;

const ref = db.collection("bugReports").doc(reportId);
const snap = await ref.get();
if (!snap.exists) {
  console.error(`bugReports/${reportId} が見つかりません`);
  process.exit(1);
}

await ref.set(update, { merge: true });
console.log(`bugReports/${reportId} を ${status} に更新しました`);
