import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { resolveQuestionReminderTargets, tokyoDateKey } from "./question_reminder_logic";

describe("tokyoDateKey", () => {
  it("JST日中の時刻はそのままの日付になる", () => {
    // 2026-08-12T20:00:00+09:00
    assert.equal(tokyoDateKey(Date.UTC(2026, 7, 12, 11, 0)), "2026-08-12");
  });

  it("JSTで日付が変わる直前・直後で切り替わる", () => {
    // 2026-08-12T23:30:00+09:00
    assert.equal(tokyoDateKey(Date.UTC(2026, 7, 12, 14, 30)), "2026-08-12");
    // 2026-08-13T00:30:00+09:00
    assert.equal(tokyoDateKey(Date.UTC(2026, 7, 12, 15, 30)), "2026-08-13");
  });

  it("UTCの日付とJSTの日付がずれる時刻でもJST基準になる", () => {
    // UTC 2026-08-12T15:30 は JST 2026-08-13T00:30
    assert.equal(tokyoDateKey(Date.UTC(2026, 7, 12, 15, 30)), "2026-08-13");
  });

  it("月・日が1桁でも0埋めされる", () => {
    // 2026-01-05T09:00:00+09:00
    assert.equal(tokyoDateKey(Date.UTC(2026, 0, 5, 0, 0)), "2026-01-05");
  });
});

describe("resolveQuestionReminderTargets", () => {
  it("未回答かつ通知が有効なメンバーだけを返す", () => {
    const targets = resolveQuestionReminderTargets([
      { uid: "a", answered: false, notifyOnDailyQuestion: true },
      { uid: "b", answered: false, notifyOnDailyQuestion: true },
    ]);
    assert.deepEqual(targets, ["a", "b"]);
  });

  it("回答済みのメンバーは除外する", () => {
    const targets = resolveQuestionReminderTargets([
      { uid: "a", answered: true, notifyOnDailyQuestion: true },
      { uid: "b", answered: false, notifyOnDailyQuestion: true },
    ]);
    assert.deepEqual(targets, ["b"]);
  });

  it("通知を無効にしているメンバーは除外する", () => {
    const targets = resolveQuestionReminderTargets([
      { uid: "a", answered: false, notifyOnDailyQuestion: false },
      { uid: "b", answered: false, notifyOnDailyQuestion: true },
    ]);
    assert.deepEqual(targets, ["b"]);
  });

  it("全員が回答済み、または通知無効なら空配列になる", () => {
    const targets = resolveQuestionReminderTargets([
      { uid: "a", answered: true, notifyOnDailyQuestion: true },
      { uid: "b", answered: false, notifyOnDailyQuestion: false },
    ]);
    assert.deepEqual(targets, []);
  });
});
