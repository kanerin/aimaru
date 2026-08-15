import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { TRASH_RETENTION_MS, isPastRetention } from "./trash_logic";

const DAY = 24 * 60 * 60 * 1000;

describe("isPastRetention", () => {
  const nowMs = new Date(2026, 7, 15).getTime();

  it("保持期間ちょうどに削除された予定は対象になる", () => {
    assert.equal(isPastRetention(nowMs - TRASH_RETENTION_MS, nowMs), true);
  });

  it("保持期間を過ぎていれば対象になる", () => {
    assert.equal(isPastRetention(nowMs - TRASH_RETENTION_MS - DAY, nowMs), true);
  });

  it("保持期間内はまだ対象にならない", () => {
    assert.equal(isPastRetention(nowMs - TRASH_RETENTION_MS + 1, nowMs), false);
  });

  it("削除されていない（保持期間がまだ始まっていない）ものは対象にならない", () => {
    assert.equal(isPastRetention(nowMs, nowMs), false);
  });
});
