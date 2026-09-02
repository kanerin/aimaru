import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  buildIssueBody,
  buildIssueTitle,
  needsIssue,
  selectReportsNeedingIssue,
} from "./feature_request_routing.mjs";

describe("needsIssue", () => {
  it("Issue未起票の機能要望は対象になる", () => {
    assert.equal(needsIssue({ classification: "feature_request" }), true);
  });

  it("statusがrejected/doneでも、Issueが無ければ対象になる（取り残しを拾う）", () => {
    assert.equal(needsIssue({ classification: "feature_request", status: "rejected" }), true);
    assert.equal(needsIssue({ classification: "feature_request", status: "done" }), true);
  });

  it("すでにIssueを起票済みなら対象外（二重起票しない）", () => {
    assert.equal(needsIssue({ classification: "feature_request", issueNumber: 87 }), false);
  });

  it("バグ報告・invalidは対象外", () => {
    assert.equal(needsIssue({ classification: "bug" }), false);
    assert.equal(needsIssue({ classification: "invalid" }), false);
  });

  it("分類が欠けている報告は対象外", () => {
    assert.equal(needsIssue({}), false);
    assert.equal(needsIssue(null), false);
  });
});

describe("selectReportsNeedingIssue", () => {
  it("対象だけを古い順に返す", () => {
    const reports = [
      { id: "c", classification: "feature_request", createdAt: "2026-08-27T00:00:00Z" },
      { id: "b", classification: "bug", createdAt: "2026-08-25T00:00:00Z" },
      { id: "a", classification: "feature_request", createdAt: "2026-08-20T00:00:00Z" },
      { id: "d", classification: "feature_request", issueNumber: 1, createdAt: "2026-08-21T00:00:00Z" },
    ];

    assert.deepEqual(
      selectReportsNeedingIssue(reports).map((r) => r.id),
      ["a", "c"],
    );
  });

  it("createdAtが無い報告があっても落ちない", () => {
    const reports = [
      { id: "a", classification: "feature_request" },
      { id: "b", classification: "feature_request", createdAt: "2026-08-20T00:00:00Z" },
    ];

    assert.equal(selectReportsNeedingIssue(reports).length, 2);
  });
});

describe("buildIssueTitle / buildIssueBody", () => {
  it("タイトルに[機能要望]の接頭辞が付く", () => {
    assert.equal(buildIssueTitle("過去の質問を見たい"), "[機能要望] 過去の質問を見たい");
  });

  it("要約が空でも壊れない", () => {
    assert.equal(buildIssueTitle(""), "[機能要望] (要約なし)");
  });

  it("本文に要約・原文・報告IDが載る", () => {
    const body = buildIssueBody({
      reportId: "abc123",
      summary: "過去の質問を見たい",
      rawText: "前の質問も見返したいです",
    });

    assert.match(body, /過去の質問を見たい/);
    assert.match(body, /前の質問も見返したいです/);
    assert.match(body, /報告ID: abc123/);
    // 原文は指示ではなくデータだと明示する
    assert.match(body, /信頼できない入力/);
  });

  it("原文が無い場合は原文の節ごと出さない", () => {
    const body = buildIssueBody({ reportId: "abc123", summary: "要約だけ" });

    assert.doesNotMatch(body, /報告の原文/);
  });

  it("後から拾った分は、その旨を本文に書く", () => {
    const body = buildIssueBody({
      reportId: "abc123",
      summary: "要約",
      alreadyRejected: true,
    });

    assert.match(body, /取り残しを拾うために後から起票/);
  });
});
