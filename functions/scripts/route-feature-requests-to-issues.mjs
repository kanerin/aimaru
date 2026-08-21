#!/usr/bin/env node
// ── 機能要望をGitHub Issueへ回し、自動実装の対象から外す ──────────────
// fix-bug-reports.ymlはバグ修正のみを自動実装する（人間レビュー無しで
// developへマージされるため、機能追加のような製品判断が要るものを無人で
// 決めさせない設計）。feature_request に分類された報告は、この決定的な
// スクリプト（Gemini・Claude Codeどちらの判断も介さない）がGitHub Issueを
// 起票し、bugReportsは rejected（out_of_scope）にする。
// Issueを見た人間が実装してほしいと判断したら、そのIssueへ @claude で
// メンションすること（claude-mention.yml が対応する）。
//
// GH_TOKEN（gh CLI用）とGOOGLE_APPLICATION_CREDENTIALS（Firestore用）が
// 環境変数に必要。fix-bug-reports.yml のジョブ内で、Claude Codeの実行より
// 前に実行する想定。
//
// 使い方: node scripts/route-feature-requests-to-issues.mjs
import { execFileSync } from "node:child_process";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

const snap = await db
  .collection("bugReports")
  .where("status", "==", "pending")
  .where("classification", "==", "feature_request")
  .get();

if (snap.empty) {
  console.log("機能要望のpending報告はありません");
  process.exit(0);
}

for (const doc of snap.docs) {
  const data = doc.data();
  const summary = data.summary || "(要約なし)";

  // execFileSync は配列で引数を渡すため、summary に含まれる文字（バック
  // ティック・ダブルクォート・改行等）がシェルに解釈される余地が無い
  // （summaryはGemini生成とはいえ、元をたどればユーザーの自由入力に
  // 由来する信頼できない文字列であるため、シェル文字列展開を避ける）。
  const title = `[機能要望] ${summary}`;
  const body = [
    "アプリ内のバグ報告・機能要望フォームから届いた機能要望です。",
    "fix-bug-reports.yml はバグ修正のみを自動実装するため、機能要望はここで人間の判断を待ちます。",
    "",
    "## 要約",
    summary,
    "",
    "## 対応するには",
    "このIssueへ `@claude` でメンションし、実装してほしい旨を具体的に指示してください（claude-mention.yml が対応します）。",
    "",
    "---",
    `報告ID: ${doc.id}`,
  ].join("\n");

  const issueUrl = execFileSync("gh", ["issue", "create", "--title", title, "--body", body], {
    encoding: "utf8",
  }).trim();
  const issueNumber = issueUrl.split("/").pop();

  execFileSync(
    "node",
    [
      "scripts/mark-bug-report-status.mjs",
      doc.id,
      "rejected",
      "--category",
      "out_of_scope",
      "--reason",
      `機能要望のため人間の判断へ回しました（Issue #${issueNumber}）`,
    ],
    { encoding: "utf8", stdio: "inherit" },
  );

  console.log(`report ${doc.id} -> ${issueUrl}`);
}
