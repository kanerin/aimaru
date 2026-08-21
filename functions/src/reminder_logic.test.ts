import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  CHECK_INTERVAL_MINUTES,
  DEFAULT_REMINDER_MINUTES_BEFORE,
  WINDOW_MINUTES,
  formatRelative,
  isStale,
  isWithinWindow,
  nextOccurrence,
  occurrenceInYear,
  resolveMinutesBefore,
  resolveReminderTargets,
  shouldRemindNow,
  visibleMemberIds,
} from "./reminder_logic";

const MINUTE = 60000;

describe("isWithinWindow / shouldRemindNow", () => {
  const nowMs = new Date(2026, 7, 12, 10, 0).getTime();

  it("窓の境界（ちょうど8分前後）は送信対象に含む", () => {
    assert.equal(isWithinWindow(nowMs - WINDOW_MINUTES * MINUTE, nowMs), true);
    assert.equal(isWithinWindow(nowMs + WINDOW_MINUTES * MINUTE, nowMs), true);
  });

  it("窓の外（8分超え）は送信対象に含まない", () => {
    assert.equal(isWithinWindow(nowMs - (WINDOW_MINUTES + 1) * MINUTE, nowMs), false);
    assert.equal(isWithinWindow(nowMs + (WINDOW_MINUTES + 1) * MINUTE, nowMs), false);
  });

  it("設定した分数だけ前が送信タイミングになる", () => {
    // 60分前設定なら、予定のちょうど60分前に窓の中心が来る
    const eventMs = nowMs + 60 * MINUTE;
    assert.equal(shouldRemindNow(eventMs, 60, nowMs), true);

    // 同じ予定でも「1日前」設定の人は、まだ送信タイミングではない
    assert.equal(shouldRemindNow(eventMs, 1440, nowMs), false);
  });

  it("15分間隔の実行で、どの送信予定時刻も必ず一度は窓に入る", () => {
    const tickMs = CHECK_INTERVAL_MINUTES * MINUTE;
    const firstTick = new Date(2026, 7, 12, 0, 0).getTime();
    const ticks = [0, 1, 2, 3, 4].map((i) => firstTick + i * tickMs);

    // 1時間ぶんの送信予定時刻を1分刻みで並べ、取りこぼしが無いことを見る
    for (let offset = 0; offset <= 60; offset++) {
      const targetMs = firstTick + offset * MINUTE;
      const hits = ticks.filter((t) => isWithinWindow(targetMs, t));
      assert.ok(hits.length >= 1, `${offset}分の予定が取りこぼされた`);
    }
  });

  it("窓は重なりうるので、重複防止はremindedフラグ側の責務になる", () => {
    // 窓幅(16分) > 実行間隔(15分) なので、隣り合う2回の実行の
    // 両方に入る時刻が必ず存在する。ここを詰めると取りこぼしが出るため、
    // 重複は送信済みフラグで防ぐ設計にしている。
    const tickMs = CHECK_INTERVAL_MINUTES * MINUTE;
    const firstTick = new Date(2026, 7, 12, 0, 0).getTime();
    const targetMs = firstTick + 7.5 * MINUTE;

    assert.equal(isWithinWindow(targetMs, firstTick), true);
    assert.equal(isWithinWindow(targetMs, firstTick + tickMs), true);
  });
});

describe("isStale", () => {
  const nowMs = new Date(2026, 7, 12, 10, 0).getTime();

  it("24時間以上過ぎた予定は片付け対象になる", () => {
    assert.equal(isStale(nowMs - 25 * 60 * MINUTE, nowMs), true);
  });

  it("24時間以内なら、過ぎていても片付けない", () => {
    assert.equal(isStale(nowMs - 23 * 60 * MINUTE, nowMs), false);
    assert.equal(isStale(nowMs + 60 * MINUTE, nowMs), false);
  });
});

describe("formatRelative", () => {
  it("分・時間・日で表現が切り替わる", () => {
    assert.equal(formatRelative(5), "5分後");
    assert.equal(formatRelative(59), "59分後");
    assert.equal(formatRelative(60), "1時間後");
    assert.equal(formatRelative(90), "2時間後"); // 四捨五入
    assert.equal(formatRelative(1439), "24時間後");
    assert.equal(formatRelative(1440), "1日後");
    assert.equal(formatRelative(2880), "2日後");
  });
});

describe("resolveMinutesBefore", () => {
  it("未設定なら既定値を使う", () => {
    assert.equal(resolveMinutesBefore(undefined), DEFAULT_REMINDER_MINUTES_BEFORE);
    assert.equal(resolveMinutesBefore(null), DEFAULT_REMINDER_MINUTES_BEFORE);
  });

  it("0分前の設定は既定値で潰さない", () => {
    assert.equal(resolveMinutesBefore(0), 0);
  });
});

describe("occurrenceInYear", () => {
  it("指定した年の同じ月日・同じ時刻になる", () => {
    const original = new Date(2020, 5, 15, 9, 30);
    const occurrence = occurrenceInYear(original, 2026);

    assert.equal(occurrence.getFullYear(), 2026);
    assert.equal(occurrence.getMonth(), 5);
    assert.equal(occurrence.getDate(), 15);
    assert.equal(occurrence.getHours(), 9);
    assert.equal(occurrence.getMinutes(), 30);
  });

  it("2月29日の記念日を平年に評価しても3月へ滑らない", () => {
    const original = new Date(2024, 1, 29, 12, 0);
    const occurrence = occurrenceInYear(original, 2026);

    assert.equal(occurrence.getMonth(), 1, "2月のままであること");
    assert.equal(occurrence.getDate(), 28, "月末で頭打ちになること");
  });

  it("2月29日の記念日は閏年ならその日のまま", () => {
    const original = new Date(2024, 1, 29, 12, 0);
    const occurrence = occurrenceInYear(original, 2028);

    assert.equal(occurrence.getMonth(), 1);
    assert.equal(occurrence.getDate(), 29);
  });
});

describe("nextOccurrence", () => {
  it("今年の発生日がまだ来ていなければ今年を採用する", () => {
    const original = new Date(2020, 11, 24, 18, 0);
    const nowMs = new Date(2026, 7, 12, 10, 0).getTime();

    assert.equal(nextOccurrence(original, nowMs).getFullYear(), 2026);
  });

  it("今年の発生日が十分過ぎていれば来年へ送る", () => {
    const original = new Date(2020, 2, 1, 12, 0);
    const nowMs = new Date(2026, 7, 12, 10, 0).getTime();

    const occurrence = nextOccurrence(original, nowMs);
    assert.equal(occurrence.getFullYear(), 2027);
    assert.equal(occurrence.getMonth(), 2);
  });

  it("過ぎて24時間以内なら今年扱いのままにする", () => {
    // 直前に過ぎた記念日を来年送りにすると、当日の通知が
    // まだ間に合う状況でも取りこぼしてしまう
    const original = new Date(2020, 7, 11, 10, 0);
    const nowMs = new Date(2026, 7, 11, 22, 0).getTime();

    assert.equal(nextOccurrence(original, nowMs).getFullYear(), 2026);
  });

  it("年末の記念日を年始に評価しても破綻しない", () => {
    const original = new Date(2020, 11, 31, 23, 0);
    const nowMs = new Date(2026, 0, 5, 10, 0).getTime();

    const occurrence = nextOccurrence(original, nowMs);
    assert.equal(occurrence.getFullYear(), 2026);
    assert.equal(occurrence.getMonth(), 11);
    assert.equal(occurrence.getDate(), 31);
  });
});

describe("visibleMemberIds", () => {
  it("privateな予定は作成者以外を通知対象から除く", () => {
    assert.deepEqual(visibleMemberIds(["a", "b"], "a", "private"), ["a"]);
  });

  it("sharedな予定は全員が通知対象のまま", () => {
    assert.deepEqual(visibleMemberIds(["a", "b"], "a", "shared"), ["a", "b"]);
  });

  it("visibilityが無い（既存ドキュメント）場合はshared扱いで全員に送る", () => {
    assert.deepEqual(visibleMemberIds(["a", "b"], "a", undefined), ["a", "b"]);
  });
});

describe("resolveReminderTargets", () => {
  const nowMs = new Date(2026, 7, 12, 10, 0).getTime();
  const eventMs = nowMs + 60 * MINUTE;

  it("タイミングが来たメンバーだけを送信対象にする", () => {
    const result = resolveReminderTargets(
      [
        { uid: "a", alreadyReminded: false, remindersEnabled: true, minutesBefore: 60 },
        { uid: "b", alreadyReminded: false, remindersEnabled: true, minutesBefore: 1440 },
      ],
      eventMs,
      nowMs,
    );

    assert.deepEqual(result.toRemind, ["a"], "60分前設定のaだけがタイミング");
    assert.equal(result.fullySettled, false, "1日前設定のbはまだ待ち");
  });

  it("全員のタイミングが来ていればfullySettledになる", () => {
    const result = resolveReminderTargets(
      [
        { uid: "a", alreadyReminded: false, remindersEnabled: true, minutesBefore: 60 },
        { uid: "b", alreadyReminded: false, remindersEnabled: true, minutesBefore: 60 },
      ],
      eventMs,
      nowMs,
    );

    assert.deepEqual(result.toRemind.sort(), ["a", "b"]);
    assert.equal(result.fullySettled, true);
  });

  it("送信済みのメンバーは対象から除く", () => {
    const result = resolveReminderTargets(
      [
        { uid: "a", alreadyReminded: true, remindersEnabled: true, minutesBefore: 60 },
        { uid: "b", alreadyReminded: false, remindersEnabled: true, minutesBefore: 60 },
      ],
      eventMs,
      nowMs,
    );

    assert.deepEqual(result.toRemind, ["b"]);
    assert.equal(result.fullySettled, true, "残る未送信メンバーもタイミングが来ていれば完了扱い");
  });

  it("remindersEnabledがfalseのメンバーは待ち扱いにしない（永久に保留させない）", () => {
    const result = resolveReminderTargets(
      [{ uid: "a", alreadyReminded: false, remindersEnabled: false, minutesBefore: 60 }],
      eventMs,
      nowMs,
    );

    assert.deepEqual(result.toRemind, []);
    assert.equal(result.fullySettled, true);
  });

  it("誰も送信済みでなく誰のタイミングも来ていなければ保留のまま", () => {
    const result = resolveReminderTargets(
      [{ uid: "a", alreadyReminded: false, remindersEnabled: true, minutesBefore: 1440 }],
      eventMs,
      nowMs,
    );

    assert.deepEqual(result.toRemind, []);
    assert.equal(result.fullySettled, false);
  });
});
