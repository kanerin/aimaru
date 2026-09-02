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
// 2026-08-28、取り残しを拾えるようにした。以前は status == "pending" の
// 機能要望だけを対象にしていたため、この仕組みが入る前（2026-08-21以前）に
// 届いた機能要望や、先にrejected/done/in_progressへ動いていた機能要望は
// 永久にIssueが起票されないままだった。statusではなく「issueNumberを
// 書き戻したか」で判定し、起票後にドキュメントへ書き戻すことで、
// 取り残しを拾いつつ何度実行しても二重起票しないようにしている。
//
// GH_TOKEN（gh CLI用）とGOOGLE_APPLICATION_CREDENTIALS（Firestore用）が
// 環境変数に必要。route-feature-requests.yml（単体・毎日）と
// fix-bug-reports.yml（Claude Codeの実行より前）の両方から呼ぶ。
// 冪等なので二重に走っても害は無い。
//
// 使い方: node scripts/route-feature-requests-to-issues.mjs [--dry-run]
import { execFileSync } from "node:child_process";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

import {
  buildIssueBody,
  buildIssueTitle,
  selectReportsNeedingIssue,
} from "./feature_request_routing.mjs";

const dryRun = process.argv.includes("--dry-run");

initializeApp();
const db = getFirestore();

// statusで絞らず機能要望を全件読み、Issue未起票のものだけをJS側で選ぶ。
// bugReportsは1人あたり月10件の上限がある小さなコレクションなので、
// 全件読んでも負荷にならず、複合索引も増やさずに済む。
const snap = await db
  .collection("bugReports")
  .where("classification", "==", "feature_request")
  .get();

const reports = snap.docs.map((doc) => {
  const data = doc.data();
  return {
    id: doc.id,
    classification: data.classification,
    status: data.status,
    summary: data.summary ?? "",
    rawText: data.rawText ?? "",
    issueNumber: data.issueNumber,
    createdAt: data.createdAt?.toDate?.().toISOString() ?? null,
  };
});

const targets = selectReportsNeedingIssue(reports);

if (targets.length === 0) {
  console.log(`Issue未起票の機能要望はありません（機能要望は全${reports.length}件）`);
  process.exit(0);
}

console.log(`Issue未起票の機能要望が${targets.length}件あります（機能要望は全${reports.length}件）`);

// 1件の失敗で残り全部が止まらないようにする。以前はexecFileSyncの例外が
// そのままループを抜けてしまい、後続の報告が次回実行まで放置されていた。
let failed = 0;
for (const report of targets) {
  try {
    const alreadyRejected = report.status !== "pending";
    const title = buildIssueTitle(report.summary);
    const body = buildIssueBody({
      reportId: report.id,
      summary: report.summary,
      rawText: report.rawText,
      alreadyRejected,
    });

    if (dryRun) {
      console.log(`[dry-run] report ${report.id} (status=${report.status}) -> ${title}`);
      continue;
    }

    // execFileSync は配列で引数を渡すため、summary・rawText に含まれる文字
    // （バックティック・ダブルクォート・改行等）がシェルに解釈される余地が無い
    // （どちらも元をたどればユーザーの自由入力に由来する信頼できない文字列)。
    const issueUrl = execFileSync("gh", ["issue", "create", "--title", title, "--body", body], {
      encoding: "utf8",
    }).trim();
    const issueNumber = Number(issueUrl.split("/").pop());

    // 先にFirestoreへ書き戻す。ここを後回しにすると、この直後に落ちたときに
    // 次回実行が同じ報告をもう一度起票してしまう。
    await db.collection("bugReports").doc(report.id).set(
      {
        issueNumber,
        issueUrl,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    // まだキューに残っている（pending）ものだけ見送りへ動かす。すでに
    // rejected/done になっている取り残し分は、後からIssueを足すだけにして
    // 当時の判定結果（rejectCategory・reason・prNumber）を上書きしない。
    if (!alreadyRejected) {
      execFileSync(
        "node",
        [
          "scripts/mark-bug-report-status.mjs",
          report.id,
          "rejected",
          "--category",
          "out_of_scope",
          "--reason",
          `機能要望のため人間の判断へ回しました（Issue #${issueNumber}）`,
        ],
        { encoding: "utf8", stdio: "inherit" },
      );
    }

    console.log(`report ${report.id} (status=${report.status}) -> ${issueUrl}`);
  } catch (err) {
    failed++;
    console.error(`report ${report.id} の起票に失敗しました: ${err.message}`);
  }
}

if (failed > 0) {
  console.error(`${failed}件の起票に失敗しました`);
  process.exit(1);
}
