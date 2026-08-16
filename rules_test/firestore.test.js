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
