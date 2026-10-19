import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import {
  DAILY_QUESTIONS_COLLECTION,
  GenerateQuestion,
  prepareDailyQuestion,
} from "./daily_question_generation";
import { GENERATION_ATTEMPTS } from "./daily_question_logic";
import { LEGACY_QUESTIONS, RESERVE_QUESTIONS } from "./question_bank";

// 翌日の質問を dailyQuestions/{dateKey} に用意する経路のテスト。
// 本番と同じ prepareDailyQuestion に、エミュレータのFirestoreと偽のGeminiを
// 渡して検証する（被りの判定・作り直し・予備への切り替え・冪等性）。
//
// FIRESTORE_EMULATOR_HOST が無い場合はスキップする。
const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;

// 2026-10-19T22:00:00+09:00。翌日は2026-10-20。
const NOW_MS = Date.UTC(2026, 9, 19, 13, 0);
const TOMORROW = "2026-10-20";

let app: ReturnType<typeof initializeApp> | undefined;
let db: FirebaseFirestore.Firestore;

/** 渡した応答を順に返す偽のGemini。呼ばれた回数も数える。 */
function fakeGemini(...answers: string[]): GenerateQuestion & { calls: number } {
  const fn = async () => {
    fn.calls++;
    const answer = answers[Math.min(fn.calls - 1, answers.length - 1)];
    return { ok: true as const, text: JSON.stringify({ question: answer }) };
  };
  fn.calls = 0;
  return fn;
}

describe("ふたりの質問: 翌日の質問の用意", { skip: EMULATOR ? false : "エミュレータ未起動" }, () => {
  before(() => {
    app = initializeApp({ projectId: "aimaru-test" }, `it-daily-question-gen-${Date.now()}`);
    db = getFirestore(app);
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  afterEach(async () => {
    const docs = await db.collection(DAILY_QUESTIONS_COLLECTION).listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  });

  async function storedTomorrow() {
    return (await db.collection(DAILY_QUESTIONS_COLLECTION).doc(TOMORROW).get()).data();
  }

  it("Geminiが作った質問を翌日の日付で保存する", async () => {
    const generate = fakeGemini("2人で行きたい雪国の街は？");

    const result = await prepareDailyQuestion(db, NOW_MS, generate);

    assert.deepEqual(result, { dateKey: TOMORROW, text: "2人で行きたい雪国の街は？", source: "gemini" });
    const stored = await storedTomorrow();
    assert.equal(stored?.text, "2人で行きたい雪国の街は？");
    assert.equal(stored?.source, "gemini");
    assert.equal(stored?.dateKey, TOMORROW);
  });

  it("既に翌日の質問があれば作り直さない", async () => {
    await db.collection(DAILY_QUESTIONS_COLLECTION).doc(TOMORROW).set({
      dateKey: TOMORROW,
      text: "先に用意した質問は？",
      source: "gemini",
    });
    const generate = fakeGemini("別の質問は？");

    const result = await prepareDailyQuestion(db, NOW_MS, generate);

    assert.equal(result, null);
    assert.equal(generate.calls, 0);
    assert.equal((await storedTomorrow())?.text, "先に用意した質問は？");
  });

  it("過去に出した質問と被ったら作り直させる", async () => {
    await db.collection(DAILY_QUESTIONS_COLLECTION).doc("2026-10-19").set({
      dateKey: "2026-10-19",
      text: "好きな季節の果物は？",
      source: "gemini",
    });
    const generate = fakeGemini("好きな季節の果物は?", "2人で育ててみたい野菜は？");

    const result = await prepareDailyQuestion(db, NOW_MS, generate);

    assert.equal(generate.calls, 2);
    assert.equal(result?.text, "2人で育ててみたい野菜は？");
  });

  it("アプリが日付で出していた手書きの質問とも被らせない", async () => {
    const generate = fakeGemini(LEGACY_QUESTIONS[0], "最近気になる言葉は？");

    const result = await prepareDailyQuestion(db, NOW_MS, generate);

    assert.equal(result?.text, "最近気になる言葉は？");
  });

  it("被り続けたら予備の質問を出す", async () => {
    const generate = fakeGemini(LEGACY_QUESTIONS[0]);

    const result = await prepareDailyQuestion(db, NOW_MS, generate);

    assert.equal(generate.calls, GENERATION_ATTEMPTS);
    assert.deepEqual(result, { dateKey: TOMORROW, text: RESERVE_QUESTIONS[0], source: "reserve" });
  });

  it("Geminiが失敗したら予備のうち、まだ出していないものを出す", async () => {
    await db.collection(DAILY_QUESTIONS_COLLECTION).doc("2026-10-19").set({
      dateKey: "2026-10-19",
      text: RESERVE_QUESTIONS[0],
      source: "reserve",
    });
    const generate: GenerateQuestion = async () => ({
      ok: false,
      kind: "unavailable",
      detail: "Gemini APIが503を返しました",
    });

    const result = await prepareDailyQuestion(db, NOW_MS, generate);

    assert.equal(result?.text, RESERVE_QUESTIONS[1]);
  });

  it("APIキーが無ければGeminiを呼ばずに予備の質問を出す", async () => {
    const result = await prepareDailyQuestion(db, NOW_MS, null);

    assert.deepEqual(result, { dateKey: TOMORROW, text: RESERVE_QUESTIONS[0], source: "reserve" });
  });
});
