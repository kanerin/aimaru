import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  buildCalendarFeedUrl,
  buildIcsCalendar,
  escapeIcsText,
  FeedEvent,
  foldIcsLine,
  formatIcsDate,
  formatIcsDateTimeUtc,
  generateFeedToken,
  isVisibleToFeedOwner,
} from "./calendar_feed_logic";

describe("generateFeedToken", () => {
  it("推測しにくい十分な長さの16進文字列を返す", () => {
    const token = generateFeedToken();
    assert.match(token, /^[0-9a-f]{48}$/);
  });

  it("毎回異なるトークンを返す", () => {
    assert.notEqual(generateFeedToken(), generateFeedToken());
  });
});

describe("buildCalendarFeedUrl", () => {
  it("プロジェクトID・uid・tokenを含むURLを組み立てる", () => {
    const url = buildCalendarFeedUrl("aimaru-7eb2e", "uid123", "tok456");
    assert.equal(
      url,
      "https://us-central1-aimaru-7eb2e.cloudfunctions.net/calendarFeed?uid=uid123&token=tok456",
    );
  });
});

describe("isVisibleToFeedOwner", () => {
  it("sharedな予定は誰の分でも見える", () => {
    assert.equal(isVisibleToFeedOwner("shared", "other-uid", "owner-uid"), true);
  });

  it("visibilityが無い（既存ドキュメント）予定はsharedとして見える", () => {
    assert.equal(isVisibleToFeedOwner(undefined, "other-uid", "owner-uid"), true);
  });

  it("自分が作成したprivateな予定は見える", () => {
    assert.equal(isVisibleToFeedOwner("private", "owner-uid", "owner-uid"), true);
  });

  it("相手が作成したprivateな予定は見えない", () => {
    assert.equal(isVisibleToFeedOwner("private", "other-uid", "owner-uid"), false);
  });
});

describe("formatIcsDate / formatIcsDateTimeUtc", () => {
  it("終日予定はYYYYMMDDで表す", () => {
    assert.equal(formatIcsDate(new Date(2026, 8, 4)), "20260904");
  });

  it("桁を0埋めする", () => {
    assert.equal(formatIcsDate(new Date(2026, 0, 5)), "20260105");
  });

  it("時刻指定予定はUTCのYYYYMMDDTHHMMSSZで表す", () => {
    const date = new Date(Date.UTC(2026, 8, 4, 3, 5, 9));
    assert.equal(formatIcsDateTimeUtc(date), "20260904T030509Z");
  });
});

describe("escapeIcsText", () => {
  it("カンマ・セミコロン・バックスラッシュ・改行をエスケープする", () => {
    assert.equal(escapeIcsText("a,b;c\\d\ne"), "a\\,b\\;c\\\\d\\ne");
  });

  it("エスケープ不要な文字列はそのまま返す", () => {
    assert.equal(escapeIcsText("東京デート"), "東京デート");
  });
});

describe("foldIcsLine", () => {
  it("75オクテット以下の行はそのまま返す", () => {
    const line = "SUMMARY:短いタイトル";
    assert.equal(foldIcsLine(line), line);
    assert.ok(Buffer.byteLength(line, "utf8") <= 75);
  });

  it("75オクテットを超える行は継続行へ折り返し、先頭に半角スペースを付ける", () => {
    const line = `SUMMARY:${"あ".repeat(60)}`;
    const folded = foldIcsLine(line);
    const segments = folded.split("\r\n");

    assert.ok(segments.length > 1);
    assert.ok(Buffer.byteLength(segments[0], "utf8") <= 75);
    for (const seg of segments.slice(1)) {
      assert.ok(seg.startsWith(" "));
      assert.ok(Buffer.byteLength(seg, "utf8") <= 75);
    }
    // 折り返しを取り除いて結合すると元のテキストに戻る（マルチバイト文字が壊れていない）
    assert.equal(segments.map((s, i) => (i === 0 ? s : s.slice(1))).join(""), line);
  });
});

describe("buildIcsCalendar", () => {
  const nowMs = new Date(2026, 8, 4, 12, 0, 0).getTime();

  it("空リストでもVCALENDARの器だけは返す", () => {
    const ics = buildIcsCalendar([], nowMs);
    assert.ok(ics.startsWith("BEGIN:VCALENDAR\r\n"));
    assert.ok(ics.endsWith("END:VCALENDAR\r\n"));
    assert.ok(ics.includes("VERSION:2.0"));
  });

  it("終日予定はVALUE=DATEで、終了日は翌日（排他的）になる", () => {
    const event: FeedEvent = {
      id: "e1",
      title: "旅行",
      start: new Date(2026, 9, 1),
      end: new Date(2026, 9, 2), // 最終日（含む）
      allDay: true,
      recurring: false,
    };
    const ics = buildIcsCalendar([event], nowMs);
    assert.ok(ics.includes("DTSTART;VALUE=DATE:20261001"));
    assert.ok(ics.includes("DTEND;VALUE=DATE:20261003"));
    assert.ok(ics.includes("UID:e1@aimaru"));
    assert.ok(ics.includes("SUMMARY:旅行"));
  });

  it("時刻指定予定でendが無ければ1時間後をDTENDにする", () => {
    const event: FeedEvent = {
      id: "e2",
      title: "ディナー",
      start: new Date(Date.UTC(2026, 9, 1, 10, 0, 0)),
      end: null,
      allDay: false,
      recurring: false,
    };
    const ics = buildIcsCalendar([event], nowMs);
    assert.ok(ics.includes("DTSTART:20261001T100000Z"));
    assert.ok(ics.includes("DTEND:20261001T110000Z"));
  });

  it("毎年繰り返す予定にはRRULE:FREQ=YEARLYを付ける", () => {
    const event: FeedEvent = {
      id: "e3",
      title: "記念日",
      start: new Date(2026, 9, 1),
      end: null,
      allDay: true,
      recurring: true,
    };
    const ics = buildIcsCalendar([event], nowMs);
    assert.ok(ics.includes("RRULE:FREQ=YEARLY"));
  });

  it("locationとmemoを持つ予定はLOCATION/DESCRIPTIONを出す", () => {
    const event: FeedEvent = {
      id: "e4",
      title: "デート",
      start: new Date(Date.UTC(2026, 9, 1, 3, 0, 0)),
      end: null,
      allDay: false,
      recurring: false,
      location: "渋谷",
      memo: "映画を見る",
    };
    const ics = buildIcsCalendar([event], nowMs);
    assert.ok(ics.includes("LOCATION:渋谷"));
    assert.ok(ics.includes("DESCRIPTION:映画を見る"));
  });

  it("locationとmemoが無ければそれぞれの行を出さない", () => {
    const event: FeedEvent = {
      id: "e5",
      title: "デート",
      start: new Date(Date.UTC(2026, 9, 1, 3, 0, 0)),
      end: null,
      allDay: false,
      recurring: false,
    };
    const ics = buildIcsCalendar([event], nowMs);
    assert.ok(!ics.includes("LOCATION:"));
    assert.ok(!ics.includes("DESCRIPTION:"));
  });

  it("全ての行はCRLFで区切られ、75オクテット以下に収まる", () => {
    const event: FeedEvent = {
      id: "e6",
      title: "あ".repeat(80),
      start: new Date(2026, 9, 1),
      end: null,
      allDay: true,
      recurring: false,
    };
    const ics = buildIcsCalendar([event], nowMs);
    const lines = ics.split("\r\n").filter((l) => l.length > 0);
    for (const line of lines) {
      assert.ok(Buffer.byteLength(line, "utf8") <= 75, `line too long: ${line}`);
    }
  });
});
