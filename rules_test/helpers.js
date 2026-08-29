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

/**
 * 招待コード参加フロー用の inviteCodes ミラーを1件作る。
 * couples本体とは独立して用意できるようにし、ミラーの中身だけを
 * 意図的にcouples本体とズラしたテスト（不整合ケース）も書けるようにする。
 */
export async function seedInviteCode(
  testEnv,
  { code = "A3K9PZ", coupleId = COUPLE_ID, members = [USER_A, USER_B] } = {},
) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`inviteCodes/${code}`).set({
      coupleId,
      memberIds: members,
    });
  });
}

export async function seedEvent(
  testEnv,
  eventId = "event-1",
  { createdBy = USER_A, visibility } = {},
) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}/events/${eventId}`).set({
      coupleId: COUPLE_ID,
      title: "デート",
      date: new Date("2026-08-22T19:00:00"),
      type: "date",
      createdBy,
      recurring: false,
      reminded: false,
      remindedYear: null,
      ...(visibility !== undefined ? { visibility } : {}),
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

export async function seedChore(testEnv, choreId = "chore-1") {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}/chores/${choreId}`).set({
      coupleId: COUPLE_ID,
      title: "皿洗い",
      assignedTo: null,
      done: false,
      createdBy: USER_A,
      createdAt: new Date("2026-08-12T10:00:00"),
    });
  });
}

export async function seedShoppingItem(testEnv, itemId = "item-1") {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}/shoppingItems/${itemId}`).set({
      coupleId: COUPLE_ID,
      title: "牛乳",
      quantity: "1本",
      done: false,
      createdBy: USER_A,
      createdAt: new Date("2026-08-12T10:00:00"),
    });
  });
}

export async function seedAnniversary(testEnv, anniversaryId = "anniversary-1") {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}/anniversaries/${anniversaryId}`).set({
      coupleId: COUPLE_ID,
      title: "プロポーズ記念日",
      date: new Date("2024-03-10"),
      createdBy: USER_A,
      createdAt: new Date("2026-08-12T10:00:00"),
    });
  });
}

export async function seedAlbumPhoto(testEnv, photoId = "photo-1") {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}/albumPhotos/${photoId}`).set({
      coupleId: COUPLE_ID,
      imageUrl: "https://example.com/a.jpg",
      uploadedBy: USER_A,
      createdAt: new Date("2026-08-12T10:00:00"),
    });
  });
}

export async function seedQuestionAnswer(testEnv, { uid = USER_A, dateKey = "2026-08-17" } = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}/questionAnswers/${dateKey}_${uid}`).set({
      coupleId: COUPLE_ID,
      dateKey,
      uid,
      text: "水族館に行きたい",
      createdAt: new Date("2026-08-17T10:00:00"),
    });
  });
}

export async function seedDiaryEntry(testEnv, { uid = USER_A, dateKey = "2026-08-17" } = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`couples/${COUPLE_ID}/diaryEntries/${dateKey}_${uid}`).set({
      coupleId: COUPLE_ID,
      dateKey,
      uid,
      text: "公園を散歩した",
      createdAt: new Date("2026-08-17T10:00:00"),
      updatedAt: new Date("2026-08-17T10:00:00"),
    });
  });
}
