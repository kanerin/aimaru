import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";

import {
  COUPLE_ID,
  USER_A,
  USER_B,
  USER_C,
  createTestEnv,
  warmUpRulesEngine,
  seedChat,
  seedCouple,
  seedEvent,
  seedExpense,
  seedQuestionAnswer,
  seedTodo,
} from "./helpers.js";

// Firestore セキュリティルールのテスト。
//
// このアプリで守るべき境界はひとつ「カップルのメンバー以外は、そのカップルの
// データに触れない」。実装側で気をつけていても、ルールが緩ければ
// アプリを経由しない直接アクセスで全部抜ける。だからここが最後の砦になる。
let testEnv;

before(async () => {
  testEnv = await createTestEnv();
  await warmUpRulesEngine(testEnv);
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

const asA = () => testEnv.authenticatedContext(USER_A).firestore();
const asB = () => testEnv.authenticatedContext(USER_B).firestore();
const asC = () => testEnv.authenticatedContext(USER_C).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

describe("events — メンバー境界", () => {
  beforeEach(async () => {
    await seedCouple(testEnv);
    await seedEvent(testEnv);
  });

  it("メンバーは予定を読める", async () => {
    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/events/event-1`).get());
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/events/event-1`).get());
  });

  it("メンバー以外は予定を読めない", async () => {
    await assertFails(asC().doc(`couples/${COUPLE_ID}/events/event-1`).get());
  });

  it("メンバー以外は予定を作成・更新・削除できない", async () => {
    const ref = asC().doc(`couples/${COUPLE_ID}/events/event-2`);
    await assertFails(ref.set({ title: "勝手な予定" }));
    await assertFails(asC().doc(`couples/${COUPLE_ID}/events/event-1`).update({ title: "改ざん" }));
    await assertFails(asC().doc(`couples/${COUPLE_ID}/events/event-1`).delete());
  });

  it("未認証は予定に一切アクセスできない", async () => {
    await assertFails(asAnon().doc(`couples/${COUPLE_ID}/events/event-1`).get());
    await assertFails(asAnon().doc(`couples/${COUPLE_ID}/events/event-2`).set({ title: "x" }));
  });

  it("メンバーは予定を作成・更新・削除できる", async () => {
    await assertSucceeds(
      asA().doc(`couples/${COUPLE_ID}/events/event-3`).set({
        coupleId: COUPLE_ID,
        title: "新しい予定",
        date: new Date("2026-09-01"),
        type: "date",
        createdBy: USER_A,
      }),
    );
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/events/event-1`).update({ title: "変更" }));
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/events/event-1`).delete());
  });
});

describe("chats — メンバー境界", () => {
  beforeEach(async () => {
    await seedCouple(testEnv);
    await seedChat(testEnv);
  });

  it("メンバーはチャットを読み書きできる", async () => {
    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/chats/msg-1`).get());
    await assertSucceeds(
      asB().doc(`couples/${COUPLE_ID}/chats/msg-2`).set({
        coupleId: COUPLE_ID,
        text: "やあ",
        senderId: USER_B,
        timestamp: new Date(),
        isAi: false,
      }),
    );
  });

  it("メンバー以外はチャットを読めない・書けない", async () => {
    await assertFails(asC().doc(`couples/${COUPLE_ID}/chats/msg-1`).get());
    await assertFails(
      asC().doc(`couples/${COUPLE_ID}/chats/msg-3`).set({ text: "割り込み", senderId: USER_C }),
    );
  });
});

describe("todos — メンバー境界", () => {
  beforeEach(async () => {
    await seedCouple(testEnv);
    await seedTodo(testEnv);
  });

  it("メンバーはTODOを読める", async () => {
    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/todos/todo-1`).get());
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/todos/todo-1`).get());
  });

  it("メンバー以外はTODOを読めない", async () => {
    await assertFails(asC().doc(`couples/${COUPLE_ID}/todos/todo-1`).get());
  });

  it("メンバーはTODOを作成・完了切り替え・削除できる", async () => {
    await assertSucceeds(
      asA().doc(`couples/${COUPLE_ID}/todos/todo-2`).set({
        coupleId: COUPLE_ID,
        text: "水族館に行く",
        done: false,
        createdBy: USER_A,
        createdAt: new Date("2026-08-12T10:00:00"),
      }),
    );
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/todos/todo-1`).update({ done: true }));
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/todos/todo-1`).delete());
  });

  it("メンバー以外はTODOを作成・更新・削除できない", async () => {
    const ref = asC().doc(`couples/${COUPLE_ID}/todos/todo-3`);
    await assertFails(ref.set({ text: "勝手なTODO" }));
    await assertFails(asC().doc(`couples/${COUPLE_ID}/todos/todo-1`).update({ done: true }));
    await assertFails(asC().doc(`couples/${COUPLE_ID}/todos/todo-1`).delete());
  });

  it("未認証はTODOに一切アクセスできない", async () => {
    await assertFails(asAnon().doc(`couples/${COUPLE_ID}/todos/todo-1`).get());
    await assertFails(asAnon().doc(`couples/${COUPLE_ID}/todos/todo-4`).set({ text: "x" }));
  });
});

describe("expenses — メンバー境界", () => {
  beforeEach(async () => {
    await seedCouple(testEnv);
    await seedExpense(testEnv);
  });

  it("メンバーは立て替え記録を読める", async () => {
    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/expenses/expense-1`).get());
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/expenses/expense-1`).get());
  });

  it("メンバー以外は立て替え記録を読めない", async () => {
    await assertFails(asC().doc(`couples/${COUPLE_ID}/expenses/expense-1`).get());
  });

  it("メンバーは立て替え記録を作成・削除できる", async () => {
    await assertSucceeds(
      asA().doc(`couples/${COUPLE_ID}/expenses/expense-2`).set({
        coupleId: COUPLE_ID,
        title: "映画代",
        amount: 3600,
        paidBy: USER_B,
        createdBy: USER_A,
        createdAt: new Date("2026-08-12T10:00:00"),
      }),
    );
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/expenses/expense-1`).delete());
  });

  it("メンバー以外は立て替え記録を作成・削除できない", async () => {
    const ref = asC().doc(`couples/${COUPLE_ID}/expenses/expense-3`);
    await assertFails(ref.set({ title: "勝手な記録", amount: 100 }));
    await assertFails(asC().doc(`couples/${COUPLE_ID}/expenses/expense-1`).delete());
  });

  it("未認証は立て替え記録に一切アクセスできない", async () => {
    await assertFails(asAnon().doc(`couples/${COUPLE_ID}/expenses/expense-1`).get());
    await assertFails(asAnon().doc(`couples/${COUPLE_ID}/expenses/expense-4`).set({ title: "x" }));
  });

  // アプリの割り勘画面が実際に投げるのは単一ドキュメントのgetではなく、
  // コレクション全体を並べ替えて購読するクエリ(list)。
  // getだけを検証していると、listで落ちる状態に気づけない。
  it("メンバーは立て替え記録を一覧できる（アプリと同じクエリ）", async () => {
    await assertSucceeds(
      asA().collection(`couples/${COUPLE_ID}/expenses`).orderBy("createdAt", "desc").get(),
    );
  });

  it("メンバー以外は立て替え記録を一覧できない", async () => {
    await assertFails(
      asC().collection(`couples/${COUPLE_ID}/expenses`).orderBy("createdAt", "desc").get(),
    );
  });
});

describe("questionAnswers — メンバー境界・自分の回答のみ書き込み", () => {
  beforeEach(async () => {
    await seedCouple(testEnv);
    await seedQuestionAnswer(testEnv, { uid: USER_A });
  });

  it("メンバーは回答を読める", async () => {
    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/questionAnswers/2026-08-17_${USER_A}`).get());
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/questionAnswers/2026-08-17_${USER_A}`).get());
  });

  it("メンバー以外は回答を読めない", async () => {
    await assertFails(asC().doc(`couples/${COUPLE_ID}/questionAnswers/2026-08-17_${USER_A}`).get());
  });

  it("自分の回答は作成できる", async () => {
    await assertSucceeds(
      asB().doc(`couples/${COUPLE_ID}/questionAnswers/2026-08-17_${USER_B}`).set({
        coupleId: COUPLE_ID,
        dateKey: "2026-08-17",
        uid: USER_B,
        text: "動物園に行きたい",
        createdAt: new Date("2026-08-17T11:00:00"),
      }),
    );
  });

  it("相手のuidを騙って回答を作成できない", async () => {
    await assertFails(
      asB().doc(`couples/${COUPLE_ID}/questionAnswers/2026-08-17_${USER_A}`).set({
        coupleId: COUPLE_ID,
        dateKey: "2026-08-17",
        uid: USER_A,
        text: "なりすまし",
        createdAt: new Date("2026-08-17T11:00:00"),
      }),
    );
  });

  it("回答は更新・削除できない（相手の回答を見た後の書き換えを防ぐ）", async () => {
    await assertFails(
      asA().doc(`couples/${COUPLE_ID}/questionAnswers/2026-08-17_${USER_A}`).update({ text: "書き換え" }),
    );
    await assertFails(asA().doc(`couples/${COUPLE_ID}/questionAnswers/2026-08-17_${USER_A}`).delete());
  });

  it("メンバー以外は回答を作成できない", async () => {
    await assertFails(
      asC().doc(`couples/${COUPLE_ID}/questionAnswers/2026-08-17_${USER_C}`).set({
        coupleId: COUPLE_ID,
        dateKey: "2026-08-17",
        uid: USER_C,
        text: "割り込み",
        createdAt: new Date("2026-08-17T11:00:00"),
      }),
    );
  });

  it("未認証は回答に一切アクセスできない", async () => {
    await assertFails(asAnon().doc(`couples/${COUPLE_ID}/questionAnswers/2026-08-17_${USER_A}`).get());
    await assertFails(
      asAnon().doc(`couples/${COUPLE_ID}/questionAnswers/2026-08-17_${USER_C}`).set({ uid: USER_C }),
    );
  });
});

describe("googleCalendarCache — 書き込みは自分の分だけ", () => {
  beforeEach(async () => {
    await seedCouple(testEnv);
  });

  it("自分のキャッシュには書ける", async () => {
    await assertSucceeds(
      asA().doc(`couples/${COUPLE_ID}/googleCalendarCache/${USER_A}`).set({ events: [] }),
    );
  });

  it("パートナーのキャッシュは読めるが上書きできない", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`couples/${COUPLE_ID}/googleCalendarCache/${USER_B}`).set({ events: [] });
    });

    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/googleCalendarCache/${USER_B}`).get());
    await assertFails(
      asA().doc(`couples/${COUPLE_ID}/googleCalendarCache/${USER_B}`).set({ events: ["改ざん"] }),
    );
  });

  it("メンバー以外はキャッシュを読めない", async () => {
    await assertFails(asC().doc(`couples/${COUPLE_ID}/googleCalendarCache/${USER_A}`).get());
  });
});

describe("couples — ペアの作成と参加", () => {
  it("自分を含まないペアは作れない", async () => {
    await assertFails(
      asC().doc("couples/new-couple").set({ memberIds: [USER_A], inviteCode: "XXXXXX" }),
    );
  });

  it("自分を含むペアは作れる", async () => {
    await assertSucceeds(
      asC().doc("couples/new-couple").set({
        memberIds: [USER_C],
        inviteCode: "XXXXXX",
        createdAt: new Date(),
        anniversary: null,
      }),
    );
  });

  it("1名のペアには2人目として参加できる", async () => {
    await seedCouple(testEnv, { members: [USER_A] });

    await assertSucceeds(
      asC().doc(`couples/${COUPLE_ID}`).update({ memberIds: [USER_A, USER_C] }),
    );
  });

  it("2名埋まっているペアに3人目は入れない", async () => {
    await seedCouple(testEnv, { members: [USER_A, USER_B] });

    await assertFails(
      asC().doc(`couples/${COUPLE_ID}`).update({ memberIds: [USER_A, USER_B, USER_C] }),
    );
  });

  it("メンバー以外はペアを削除できない", async () => {
    await seedCouple(testEnv);

    await assertFails(asC().doc(`couples/${COUPLE_ID}`).delete());
  });

  it("メンバーはペアを削除できる", async () => {
    await seedCouple(testEnv);

    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}`).delete());
  });

  it("未認証はペアを読めない", async () => {
    await seedCouple(testEnv);

    await assertFails(asAnon().doc(`couples/${COUPLE_ID}`).get());
  });

  // 既知の妥協点。招待コードでの検索を成立させるため couples の read を
  // request.auth != null まで緩めており、無関係の認証済みユーザーでも
  // 他人のペアの memberIds / anniversary が読めてしまう。
  //
  // これは「直っていない」ことを固定するテスト。締めるなら inviteCode を
  // 別コレクションへ分離する設計変更が要る。挙動を変えたらここが落ちるので、
  // 変更したことに気づける。
  it("【既知】認証済みなら第三者でも他人のペアを読めてしまう", async () => {
    await seedCouple(testEnv);

    await assertSucceeds(asC().doc(`couples/${COUPLE_ID}`).get());
  });
});

describe("users — 自分のドキュメントだけ書ける", () => {
  it("自分のドキュメントは書ける", async () => {
    await assertSucceeds(asA().doc(`users/${USER_A}`).set({ displayName: "A", reminderMinutesBefore: 30 }));
  });

  it("他人のドキュメントは書けない", async () => {
    await assertFails(asA().doc(`users/${USER_B}`).set({ reminderMinutesBefore: 5 }));
  });

  it("認証済みなら他人のドキュメントを読める（パートナー名の表示に必要）", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${USER_B}`).set({ displayName: "B" });
    });

    await assertSucceeds(asA().doc(`users/${USER_B}`).get());
  });

  it("未認証は読み書きできない", async () => {
    await assertFails(asAnon().doc(`users/${USER_A}`).get());
    await assertFails(asAnon().doc(`users/${USER_A}`).set({ displayName: "x" }));
  });
});

// askGemini（Cloud Functions）が1日あたりのAI呼び出し回数を数える場所。
// クライアントが直接書き換えられると、自分のカウントを0に戻して
// レート制限を無効化できてしまうため、他フィールドと切り分けて守る。
describe("users — aiCallDate/aiCallCountはクライアントから書き換えられない", () => {
  it("新規ドキュメント作成時にaiCallCountを含められない", async () => {
    await assertFails(
      asA().doc(`users/${USER_A}`).set({ displayName: "A", aiCallCount: 0 }),
    );
  });

  it("新規ドキュメント作成時にaiCallDateを含められない", async () => {
    await assertFails(
      asA().doc(`users/${USER_A}`).set({ displayName: "A", aiCallDate: "2026-08-19" }),
    );
  });

  it("既にカウントが付いたドキュメントに対し、カウントをリセットする書き込みは拒否される", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${USER_A}`).set({
        displayName: "A",
        aiCallDate: "2026-08-19",
        aiCallCount: 50,
      });
    });

    await assertFails(
      asA().doc(`users/${USER_A}`).set({ aiCallCount: 0 }, { merge: true }),
    );
    await assertFails(
      asA().doc(`users/${USER_A}`).set({ aiCallDate: "2020-01-01", aiCallCount: 0 }, { merge: true }),
    );
  });

  it("カウントが既に付いていても、他の設定フィールドは引き続き更新できる", async () => {
    // merge:trueの書き込みでは、変更していない既存フィールド（ここでは
    // aiCallDate/aiCallCount）もrequest.resource.dataに含まれてくる。
    // 値そのものを変更していなければ許可されることを確かめる
    // （affectedKeys()ではなくkeys()だけで判定すると、ここが壊れて
    // AI利用済みのユーザーが設定変更できなくなる）。
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${USER_A}`).set({
        displayName: "A",
        aiCallDate: "2026-08-19",
        aiCallCount: 50,
      });
    });

    await assertSucceeds(
      asA().doc(`users/${USER_A}`).set({ remindersEnabled: false }, { merge: true }),
    );
  });
});
