import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  AI_DAILY_CALL_LIMIT,
  callGeminiApi,
  classifyGeminiApiError,
  extractGeminiText,
  isCoupleMember,
  isOverLimit,
  nextRateLimitState,
  validateContents,
} from "./gemini_logic";

describe("isOverLimit", () => {
  it("記録が無ければ許可する", () => {
    assert.equal(isOverLimit(undefined, "2026-08-19"), false);
  });

  it("日付が変わっていれば、前日のカウントを引き継がず許可する", () => {
    assert.equal(isOverLimit({ date: "2026-08-18", count: 999 }, "2026-08-19"), false);
  });

  it("上限未満なら許可する", () => {
    assert.equal(
      isOverLimit({ date: "2026-08-19", count: AI_DAILY_CALL_LIMIT - 1 }, "2026-08-19"),
      false,
    );
  });

  it("上限ちょうどで拒否する", () => {
    assert.equal(
      isOverLimit({ date: "2026-08-19", count: AI_DAILY_CALL_LIMIT }, "2026-08-19"),
      true,
    );
  });

  it("上限を超えていれば拒否する", () => {
    assert.equal(
      isOverLimit({ date: "2026-08-19", count: AI_DAILY_CALL_LIMIT + 5 }, "2026-08-19"),
      true,
    );
  });

  it("カスタムの上限を指定できる", () => {
    assert.equal(isOverLimit({ date: "2026-08-19", count: 3 }, "2026-08-19", 3), true);
    assert.equal(isOverLimit({ date: "2026-08-19", count: 2 }, "2026-08-19", 3), false);
  });
});

describe("nextRateLimitState", () => {
  it("記録が無ければ1件目として記録する", () => {
    assert.deepEqual(nextRateLimitState(undefined, "2026-08-19"), {
      date: "2026-08-19",
      count: 1,
    });
  });

  it("同じ日ならカウントを1増やす", () => {
    assert.deepEqual(nextRateLimitState({ date: "2026-08-19", count: 4 }, "2026-08-19"), {
      date: "2026-08-19",
      count: 5,
    });
  });

  it("日付が変わっていればカウントを1からやり直す", () => {
    assert.deepEqual(nextRateLimitState({ date: "2026-08-18", count: 999 }, "2026-08-19"), {
      date: "2026-08-19",
      count: 1,
    });
  });
});

describe("isCoupleMember", () => {
  it("メンバーならtrue", () => {
    assert.equal(isCoupleMember(["uid-a", "uid-b"], "uid-a"), true);
  });

  it("メンバーでなければfalse（招待コードだけ知っている非メンバーを弾く）", () => {
    assert.equal(isCoupleMember(["uid-a", "uid-b"], "uid-c"), false);
  });

  it("空配列ならfalse", () => {
    assert.equal(isCoupleMember([], "uid-a"), false);
  });
});

describe("classifyGeminiApiError", () => {
  it("429はresource-exhausted", () => {
    assert.equal(classifyGeminiApiError(429), "resource-exhausted");
  });

  it("401・403は、こちらの鍵の問題としてfailed-precondition", () => {
    assert.equal(classifyGeminiApiError(401), "failed-precondition");
    assert.equal(classifyGeminiApiError(403), "failed-precondition");
  });

  it("それ以外はinternal", () => {
    assert.equal(classifyGeminiApiError(500), "internal");
    assert.equal(classifyGeminiApiError(400), "internal");
  });
});

describe("extractGeminiText", () => {
  it("正常なレスポンスからテキストを取り出せる", () => {
    const body = {
      candidates: [{ content: { parts: [{ text: '{"kind":"text","text":"こんにちは"}' }] } }],
    };
    assert.equal(extractGeminiText(body), '{"kind":"text","text":"こんにちは"}');
  });

  it("candidatesが空ならnull", () => {
    assert.equal(extractGeminiText({ candidates: [] }), null);
  });

  it("candidatesが無ければnull", () => {
    assert.equal(extractGeminiText({}), null);
  });

  it("partsが無ければnull", () => {
    assert.equal(extractGeminiText({ candidates: [{ content: {} }] }), null);
  });

  it("textが文字列でなければnull", () => {
    assert.equal(
      extractGeminiText({ candidates: [{ content: { parts: [{ text: 42 }] } }] }),
      null,
    );
  });

  it("オブジェクトでない入力ではnull", () => {
    assert.equal(extractGeminiText("not an object"), null);
    assert.equal(extractGeminiText(null), null);
  });
});

describe("validateContents", () => {
  it("正しい形のcontentsは通す", () => {
    assert.equal(
      validateContents([
        { role: "user", parts: [{ text: "こんにちは" }] },
        { role: "model", parts: [{ text: "はい" }] },
      ]),
      true,
    );
  });

  it("inlineDataのpartも通す", () => {
    assert.equal(
      validateContents([
        { role: "user", parts: [{ text: "この画像から" }, { inlineData: { mimeType: "image/jpeg", data: "AAAA" } }] },
      ]),
      true,
    );
  });

  it("配列でなければ拒否する", () => {
    assert.equal(validateContents({ role: "user" }), false);
    assert.equal(validateContents(null), false);
    assert.equal(validateContents("text"), false);
  });

  it("空配列は拒否する", () => {
    assert.equal(validateContents([]), false);
  });

  it("roleが不正なら拒否する", () => {
    assert.equal(validateContents([{ role: "system", parts: [{ text: "x" }] }]), false);
  });

  it("partsが空なら拒否する", () => {
    assert.equal(validateContents([{ role: "user", parts: [] }]), false);
  });

  it("text・inlineDataのどちらでもないpartは拒否する", () => {
    assert.equal(validateContents([{ role: "user", parts: [{ foo: "bar" }] }]), false);
  });

  it("要素数が多すぎる場合は拒否する（会話履歴の際限ない肥大化を防ぐ）", () => {
    const tooMany = Array.from({ length: 201 }, () => ({ role: "user" as const, parts: [{ text: "x" }] }));
    assert.equal(validateContents(tooMany), false);
  });

  it("1件のtextが長すぎる場合は拒否する", () => {
    assert.equal(
      validateContents([{ role: "user", parts: [{ text: "a".repeat(20001) }] }]),
      false,
    );
  });
});

describe("callGeminiApi", () => {
  function fakeFetch(status: number, body: unknown): typeof fetch {
    return (async () =>
      new Response(JSON.stringify(body), { status })) as unknown as typeof fetch;
  }

  it("成功時はokとテキストを返す", async () => {
    const fetchImpl = fakeFetch(200, {
      candidates: [{ content: { parts: [{ text: '{"kind":"text","text":"やあ"}' }] } }],
    });
    const result = await callGeminiApi(
      [{ role: "user", parts: [{ text: "こんにちは" }] }],
      "dummy-key",
      fetchImpl,
    );
    assert.deepEqual(result, { ok: true, text: '{"kind":"text","text":"やあ"}' });
  });

  it("429はresource-exhaustedとして返す", async () => {
    const fetchImpl = fakeFetch(429, { error: "quota" });
    const result = await callGeminiApi([{ role: "user", parts: [{ text: "x" }] }], "dummy-key", fetchImpl);
    assert.deepEqual(result, { ok: false, kind: "resource-exhausted" });
  });

  it("403はfailed-preconditionとして返す（サーバー側の鍵の問題）", async () => {
    const fetchImpl = fakeFetch(403, { error: "forbidden" });
    const result = await callGeminiApi([{ role: "user", parts: [{ text: "x" }] }], "bad-key", fetchImpl);
    assert.deepEqual(result, { ok: false, kind: "failed-precondition" });
  });

  it("200でも本文の形が想定と違えばinternalとして扱う", async () => {
    const fetchImpl = fakeFetch(200, { candidates: [] });
    const result = await callGeminiApi([{ role: "user", parts: [{ text: "x" }] }], "dummy-key", fetchImpl);
    assert.deepEqual(result, { ok: false, kind: "internal" });
  });

  it("リクエストにAPIキーとcontentsを渡す", async () => {
    let capturedHeaders: HeadersInit | undefined;
    let capturedBody: string | undefined;
    const fetchImpl = (async (_url: string, init?: RequestInit) => {
      capturedHeaders = init?.headers;
      capturedBody = init?.body as string;
      return new Response(
        JSON.stringify({ candidates: [{ content: { parts: [{ text: "ok" }] } }] }),
        { status: 200 },
      );
    }) as unknown as typeof fetch;

    await callGeminiApi([{ role: "user", parts: [{ text: "こんにちは" }] }], "my-secret-key", fetchImpl);

    assert.equal((capturedHeaders as Record<string, string>)["x-goog-api-key"], "my-secret-key");
    const parsedBody = JSON.parse(capturedBody!);
    assert.deepEqual(parsedBody.contents, [{ role: "user", parts: [{ text: "こんにちは" }] }]);
    assert.equal(parsedBody.generationConfig.responseMimeType, "application/json");
  });
});
