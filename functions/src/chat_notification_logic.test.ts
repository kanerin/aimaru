import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { CHAT_NOTIFICATION_PREVIEW_MAX_LENGTH, buildChatNotificationBody } from "./chat_notification_logic";

describe("buildChatNotificationBody", () => {
  it("テキストがあればそのまま返す", () => {
    assert.equal(buildChatNotificationBody("今日ありがとう"), "今日ありがとう");
  });

  it("テキストが無い（画像のみ）場合は固定文言を返す", () => {
    assert.equal(buildChatNotificationBody(undefined), "写真を送りました");
    assert.equal(buildChatNotificationBody(""), "写真を送りました");
    assert.equal(buildChatNotificationBody("   "), "写真を送りました");
  });

  it("上限ちょうどの長さはそのまま返す", () => {
    const text = "あ".repeat(CHAT_NOTIFICATION_PREVIEW_MAX_LENGTH);
    assert.equal(buildChatNotificationBody(text), text);
  });

  it("上限を超えるテキストは切り詰めて…を付ける", () => {
    const text = "あ".repeat(CHAT_NOTIFICATION_PREVIEW_MAX_LENGTH + 10);
    const result = buildChatNotificationBody(text);
    assert.equal(result, `${"あ".repeat(CHAT_NOTIFICATION_PREVIEW_MAX_LENGTH)}…`);
  });

  it("前後の空白はトリムしてから判定する", () => {
    assert.equal(buildChatNotificationBody("  よろしく  "), "よろしく");
  });
});
