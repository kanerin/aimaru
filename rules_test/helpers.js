import { readFileSync } from "node:fs";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";

// テストで使う固定の ID。
// coupleX に userA / userB が所属し、userC は無関係の第三者という構図。
// 「メンバーかどうか」の境界を見るのがルールテストの中心なので、
// この3人だけで大半のケースを表現できる。
export const COUPLE_ID = "couple-x";
export const USER_A = "user-a";
export const USER_B = "user-b";
export const USER_C = "user-c";

/**
 * エミュレータを温めておく。
 *
 * ルール内の `get()`（別ドキュメントの参照）は、その実行環境の初回呼び出しだけ
 * "Service call error" で落ちることがある。テストの1件目がたまたまその犠牲に
 * なると、ルールは正しいのに落ちて原因調査に時間を取られる。
 * 実害のあるコールドスタートではないので、先に一度空撃ちして吸収しておく。
 */
export async function warmUpRulesEngine(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}`).set({ memberIds: [USER_A] });
  });
  await testEnv
    .authenticatedContext(USER_A)
    .firestore()
    .doc(`couples/${COUPLE_ID}/events/warmup`)
    .get()
    .catch(() => {});
  await testEnv.clearFirestore();
}

export async function createTestEnv() {
  return initializeTestEnvironment({
    projectId: "aimaru-test",
    firestore: {
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
    storage: {
      rules: readFileSync(new URL("../storage.rules", import.meta.url), "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });
}

/**
 * ルールを迂回して初期データを入れる。
 *
 * ルール越しに用意しようとすると「準備そのものがルールに阻まれる」ため、
 * 前提データは必ずこの経路で作る。
 */
export async function seedCouple(testEnv, { members = [USER_A, USER_B], inviteCode = "A3K9PZ" } = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}`).set({
      memberIds: members,
      inviteCode,
      createdAt: new Date("2026-01-01"),
      anniversary: null,
    });
  });
}

export async function seedEvent(testEnv, eventId = "event-1") {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}/events/${eventId}`).set({
      coupleId: COUPLE_ID,
      title: "デート",
      date: new Date("2026-08-22T19:00:00"),
      type: "date",
      createdBy: USER_A,
      recurring: false,
      reminded: false,
      remindedYear: null,
    });
  });
}

export async function seedChat(testEnv, msgId = "msg-1") {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}/chats/${msgId}`).set({
      coupleId: COUPLE_ID,
      text: "こんにちは",
      senderId: USER_A,
      timestamp: new Date("2026-08-12T10:00:00"),
      isAi: false,
    });
  });
}

export async function seedTodo(testEnv, todoId = "todo-1") {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}/todos/${todoId}`).set({
      coupleId: COUPLE_ID,
      text: "水族館に行く",
      done: false,
      createdBy: USER_A,
      createdAt: new Date("2026-08-12T10:00:00"),
    });
  });
}
