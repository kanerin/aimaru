import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { findLeftoverSoloCouples } from "./couple_cleanup_logic";

describe("findLeftoverSoloCouples", () => {
  it("ペアに入っている人の、自分だけのカップルを返す", () => {
    const leftovers = findLeftoverSoloCouples([
      { id: "pair", memberIds: ["a", "b"] },
      { id: "solo-b", memberIds: ["b"] },
    ]);
    assert.deepEqual(leftovers, [{ coupleId: "solo-b", uid: "b" }]);
  });

  it("相手の参加を待っているだけの招待中のカップルは残す", () => {
    const leftovers = findLeftoverSoloCouples([
      { id: "pair", memberIds: ["a", "b"] },
      { id: "waiting", memberIds: ["c"] },
    ]);
    assert.deepEqual(leftovers, []);
  });

  it("ペアのカップル自体は対象にしない", () => {
    const leftovers = findLeftoverSoloCouples([
      { id: "pair-1", memberIds: ["a", "b"] },
      { id: "pair-2", memberIds: ["c", "d"] },
    ]);
    assert.deepEqual(leftovers, []);
  });

  it("メンバーが空のカップルは対象にしない", () => {
    const leftovers = findLeftoverSoloCouples([
      { id: "pair", memberIds: ["a", "b"] },
      { id: "empty", memberIds: [] },
    ]);
    assert.deepEqual(leftovers, []);
  });
});
