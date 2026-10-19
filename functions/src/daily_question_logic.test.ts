import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  buildQuestionGenerationContents,
  normalizeQuestion,
  parseGeneratedQuestion,
  pickQuestionTheme,
  pickReserveQuestion,
  QUESTION_THEMES,
} from "./daily_question_logic";
import { LEGACY_QUESTIONS, RESERVE_QUESTIONS } from "./question_bank";

describe("normalizeQuestion", () => {
  it("全角・半角、空白、文末の記号の違いは同じ質問とみなす", () => {
    assert.equal(normalizeQuestion("好きな色は？"), normalizeQuestion("好きな色は?"));
    assert.equal(normalizeQuestion("好きな色は？"), normalizeQuestion(" 好きな 色は "));
    assert.equal(normalizeQuestion("教えて！"), normalizeQuestion("教えて"));
  });

  it("文中の違いは別の質問として残す", () => {
    assert.notEqual(normalizeQuestion("好きな色は？"), normalizeQuestion("嫌いな色は？"));
  });
});

describe("pickQuestionTheme", () => {
  it("同じ日・同じ試行回数なら同じテーマになる", () => {
    assert.equal(pickQuestionTheme("2026-10-20"), pickQuestionTheme("2026-10-20"));
  });

  it("作り直すたびに別のテーマになる", () => {
    assert.notEqual(pickQuestionTheme("2026-10-20", 0), pickQuestionTheme("2026-10-20", 1));
  });

  it("用意したテーマのどれかを返す", () => {
    for (let d = 1; d <= 31; d++) {
      const dateKey = `2026-10-${String(d).padStart(2, "0")}`;
      assert.ok(QUESTION_THEMES.includes(pickQuestionTheme(dateKey)));
    }
  });
});

describe("buildQuestionGenerationContents", () => {
  it("テーマとこれまでの質問をプロンプトに含める", () => {
    const contents = buildQuestionGenerationContents(["好きな色は？", "好きな花は？"], "食べ物・料理");
    assert.equal(contents.length, 1);
    const part = contents[0].parts[0];
    assert.ok("text" in part);
    assert.match(part.text, /今日のテーマ: 食べ物・料理/);
    assert.match(part.text, /- 好きな色は？\n- 好きな花は？/);
  });

  it("これまでの質問が無くても組み立てられる", () => {
    const part = buildQuestionGenerationContents([], "自分のこと")[0].parts[0];
    assert.ok("text" in part);
    assert.match(part.text, /（まだありません）/);
  });
});

describe("parseGeneratedQuestion", () => {
  it("JSONのquestionを前後の空白を除いて取り出す", () => {
    assert.equal(parseGeneratedQuestion('{"question": " 好きな季節は？ "}'), "好きな季節は？");
  });

  it("「！」で終わる問いかけも受け付ける", () => {
    assert.equal(parseGeneratedQuestion('{"question": "好きな季節を教えて！"}'), "好きな季節を教えて！");
  });

  it("JSONでない・questionが無い・文字列でない応答はnull", () => {
    assert.equal(parseGeneratedQuestion("好きな季節は？"), null);
    assert.equal(parseGeneratedQuestion('{"text": "好きな季節は？"}'), null);
    assert.equal(parseGeneratedQuestion('{"question": 1}'), null);
    assert.equal(parseGeneratedQuestion("null"), null);
  });

  it("複数行・短すぎ・長すぎ・問いかけで終わらない応答はnull", () => {
    assert.equal(parseGeneratedQuestion('{"question": "好きな季節は？\\n理由も教えて！"}'), null);
    assert.equal(parseGeneratedQuestion('{"question": "色は？"}'), null);
    assert.equal(parseGeneratedQuestion(JSON.stringify({ question: `${"あ".repeat(60)}？` })), null);
    assert.equal(parseGeneratedQuestion('{"question": "好きな季節について"}'), null);
  });
});

describe("pickReserveQuestion", () => {
  it("まだ出していない最初の質問を返す", () => {
    const used = new Set([normalizeQuestion("A？")]);
    assert.equal(pickReserveQuestion(["A？", "B？", "C？"], used), "B？");
  });

  it("使い切っていればnull", () => {
    const used = new Set(["A", "B"].map(normalizeQuestion));
    assert.equal(pickReserveQuestion(["A？", "B？"], used), null);
  });
});

describe("question_bank", () => {
  it("予備の質問は、これまでの質問とも予備同士でも被らない", () => {
    const seen = new Set(LEGACY_QUESTIONS.map(normalizeQuestion));
    for (const q of RESERVE_QUESTIONS) {
      const key = normalizeQuestion(q);
      assert.ok(!seen.has(key), `被っています: ${q}`);
      seen.add(key);
    }
  });

  it("予備の質問はどれも、生成した質問と同じ形式の条件を満たす", () => {
    for (const q of RESERVE_QUESTIONS) {
      assert.equal(parseGeneratedQuestion(JSON.stringify({ question: q })), q);
    }
  });
});
