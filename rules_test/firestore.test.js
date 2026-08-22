import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
// compat（.doc()/.collection()の連鎖）ではFilter.or/andによる複合クエリを
// 組み立てられないため、そのテストだけmodular APIの関数を使う。
// rules-unit-testingのfirestore()が返すcompatインスタンスは、この
// modular関数にそのまま渡せる（Firebase公式の相互運用）。
import { and, collection, getDocs, or, query, where } from "firebase/firestore";

import {
  COUPLE_ID,
  USER_A,
  USER_B,
  USER_C,
  createTestEnv,
  warmUpRulesEngine,
  seedAnniversary,
  seedChat,
  seedCouple,
  seedEvent,
  seedInviteCode,
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

describe("events — visibility（private/shared）", () => {
  beforeEach(async () => {
    await seedCouple(testEnv);
  });

  it("createdBy以外は自分をcreatedByにしてしか作成できない", async () => {
    await assertFails(
      asA().doc(`couples/${COUPLE_ID}/events/spoofed`).set({
        coupleId: COUPLE_ID,
        title: "なりすまし",
        date: new Date("2026-09-01"),
        type: "date",
        createdBy: USER_B,
      }),
    );
    await assertSucceeds(
      asA().doc(`couples/${COUPLE_ID}/events/own`).set({
        coupleId: COUPLE_ID,
        title: "自分の予定",
        date: new Date("2026-09-01"),
        type: "date",
        createdBy: USER_A,
        visibility: "private",
      }),
    );
  });

  it("visibilityフィールドが無い既存ドキュメントはメンバー全員が読める（sharedとして扱う）", async () => {
    await seedEvent(testEnv, "no-visibility-field");
    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/events/no-visibility-field`).get());
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/events/no-visibility-field`).get());
  });

  it("sharedな予定はメンバー全員が読み書きできる", async () => {
    await seedEvent(testEnv, "shared-1", { createdBy: USER_A, visibility: "shared" });
    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/events/shared-1`).get());
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/events/shared-1`).get());
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/events/shared-1`).update({ title: "変更" }));
  });

  it("privateな予定は作成者本人だけが読み書き・削除できる", async () => {
    await seedEvent(testEnv, "private-1", { createdBy: USER_A, visibility: "private" });

    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/events/private-1`).get());
    await assertFails(asB().doc(`couples/${COUPLE_ID}/events/private-1`).get());

    await assertFails(asB().doc(`couples/${COUPLE_ID}/events/private-1`).update({ title: "改ざん" }));
    await assertFails(asB().doc(`couples/${COUPLE_ID}/events/private-1`).delete());

    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/events/private-1`).update({ title: "自分で編集" }));
  });

  it("更新でcreatedByを書き換えることはできない（所有権の乗っ取り防止）", async () => {
    await seedEvent(testEnv, "shared-2", { createdBy: USER_A, visibility: "shared" });
    await assertFails(
      asB().doc(`couples/${COUPLE_ID}/events/shared-2`).update({ createdBy: USER_B }),
    );
  });

  it("visibilityで絞り込まないlistクエリは、単発getでは拒否される相手のprivateな予定も返してしまう", async () => {
    // 単発get()なら拒否されるドキュメントでも（上の「privateな予定は作成者本人だけが
    // 読み書き・削除できる」テストの通り）、visibilityをwhere句に含めないlistクエリは
    // それを止められない。Firestoreのセキュリティルールはlistクエリの結果を
    // ドキュメント単位でフィルタしてはくれないため、「見せてはいけないデータを
    // クライアント側のwhere句で確実に除外する」ことが唯一の防御線になる
    // （EventService._visibilityFilter()が全クエリに必須な理由）。
    await seedEvent(testEnv, "shared-x", { createdBy: USER_A, visibility: "shared" });
    await seedEvent(testEnv, "private-in-range", { createdBy: USER_A, visibility: "private" });

    const snap = await asB()
      .collection(`couples/${COUPLE_ID}/events`)
      .where("coupleId", "==", COUPLE_ID)
      .get();
    const ids = snap.docs.map((d) => d.id).sort();
    assert.deepEqual(ids, ["private-in-range", "shared-x"]);
  });

  it("visibilityで絞り込んだlistクエリなら、相手は自分のsharedと自分のprivateだけ読める", async () => {
    await seedEvent(testEnv, "a-shared", { createdBy: USER_A, visibility: "shared" });
    await seedEvent(testEnv, "a-private", { createdBy: USER_A, visibility: "private" });
    await seedEvent(testEnv, "b-private", { createdBy: USER_B, visibility: "private" });

    // lib/services/event_service.dartの_visibilityFilter()と同じ形。
    // ここが同じ形でないと、ルールが許可しても本番のFlutter側クエリが
    // 拒否される（またはその逆）ため、あえてDart側と同型のクエリを組む。
    const q = query(
      collection(asB(), `couples/${COUPLE_ID}/events`),
      or(
        where("visibility", "==", "shared"),
        and(where("visibility", "==", "private"), where("createdBy", "==", USER_B)),
      ),
    );
    const snap = await getDocs(q);

    const ids = snap.docs.map((d) => d.id).sort();
    assert.deepEqual(ids, ["a-shared", "b-private"]);
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

describe("anniversaries — メンバー境界", () => {
  beforeEach(async () => {
    await seedCouple(testEnv);
    await seedAnniversary(testEnv);
  });

  it("メンバーは記念日を読める", async () => {
    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/anniversaries/anniversary-1`).get());
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/anniversaries/anniversary-1`).get());
  });

  it("メンバー以外は記念日を読めない", async () => {
    await assertFails(asC().doc(`couples/${COUPLE_ID}/anniversaries/anniversary-1`).get());
  });

  it("メンバーは記念日を作成・削除できる", async () => {
    await assertSucceeds(
      asA().doc(`couples/${COUPLE_ID}/anniversaries/anniversary-2`).set({
        coupleId: COUPLE_ID,
        title: "初デート",
        date: new Date("2022-01-01"),
        createdBy: USER_A,
        createdAt: new Date("2026-08-12T10:00:00"),
      }),
    );
    await assertSucceeds(asB().doc(`couples/${COUPLE_ID}/anniversaries/anniversary-1`).delete());
  });

  it("メンバー以外は記念日を作成・更新・削除できない", async () => {
    const ref = asC().doc(`couples/${COUPLE_ID}/anniversaries/anniversary-3`);
    await assertFails(ref.set({ title: "勝手な記念日" }));
    await assertFails(asC().doc(`couples/${COUPLE_ID}/anniversaries/anniversary-1`).update({ title: "改ざん" }));
    await assertFails(asC().doc(`couples/${COUPLE_ID}/anniversaries/anniversary-1`).delete());
  });

  it("未認証は記念日に一切アクセスできない", async () => {
    await assertFails(asAnon().doc(`couples/${COUPLE_ID}/anniversaries/anniversary-1`).get());
    await assertFails(asAnon().doc(`couples/${COUPLE_ID}/anniversaries/anniversary-4`).set({ title: "x" }));
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

describe("googleEventVisibility — 自分の指定は自分しか読み書きできない", () => {
  beforeEach(async () => {
    await seedCouple(testEnv);
  });

  it("自分の指定は書ける・読める", async () => {
    await assertSucceeds(
      asA().doc(`couples/${COUPLE_ID}/googleEventVisibility/${USER_A}`).set({
        privateEventIds: ["gcal-1"],
      }),
    );
    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}/googleEventVisibility/${USER_A}`).get());
  });

  it("パートナーの指定は読めない（googleCalendarCacheと違いメンバーでも不可）", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore()
        .doc(`couples/${COUPLE_ID}/googleEventVisibility/${USER_B}`)
        .set({ privateEventIds: ["gcal-1"] });
    });

    await assertFails(asA().doc(`couples/${COUPLE_ID}/googleEventVisibility/${USER_B}`).get());
  });

  it("パートナーの指定を書き換えられない", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore()
        .doc(`couples/${COUPLE_ID}/googleEventVisibility/${USER_B}`)
        .set({ privateEventIds: [] });
    });

    await assertFails(
      asA().doc(`couples/${COUPLE_ID}/googleEventVisibility/${USER_B}`).set({
        privateEventIds: ["改ざん"],
      }),
    );
  });

  it("メンバー以外は書けない", async () => {
    await assertFails(
      asC().doc(`couples/${COUPLE_ID}/googleEventVisibility/${USER_C}`).set({
        privateEventIds: [],
      }),
    );
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

  it("メンバーは自分のペアを読める", async () => {
    await seedCouple(testEnv, { members: [USER_A, USER_B] });

    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}`).get());
  });

  // 2026-08-22解消。招待コードでの検索を inviteCodes（別コレクション、
  // 下記）へ分離したことで、couples の read をメンバーのみへ締められる
  // ようになった（旧TC-072）。無関係の認証済みユーザーが他人のペアの
  // memberIds / anniversary を読めていた状態を固定していたテストを反転する。
  it("認証済みでもメンバー以外は他人のペアを読めない", async () => {
    await seedCouple(testEnv, { members: [USER_A, USER_B] });

    await assertFails(asC().doc(`couples/${COUPLE_ID}`).get());
  });
});

describe("inviteCodes — 招待コード参加フローの事前確認用ミラー", () => {
  it("認証済みなら誰でもコードでcoupleIdを引ける（get）", async () => {
    await seedInviteCode(testEnv, { members: [USER_A] });

    await assertSucceeds(asC().doc("inviteCodes/A3K9PZ").get());
  });

  it("未認証はコードを引けない", async () => {
    await seedInviteCode(testEnv, { members: [USER_A] });

    await assertFails(asAnon().doc("inviteCodes/A3K9PZ").get());
  });

  it("コレクション全体のlist（総当たり列挙）はできない", async () => {
    await seedInviteCode(testEnv, { members: [USER_A] });

    await assertFails(
      asC().collection("inviteCodes").get(),
    );
  });

  it("自分1人だけのミラーは作れる（ペア作成時）", async () => {
    await assertSucceeds(
      asA().doc("inviteCodes/NEWCODE").set({
        coupleId: "new-couple",
        memberIds: [USER_A],
      }),
    );
  });

  it("自分を含まないミラーは作れない", async () => {
    await assertFails(
      asA().doc("inviteCodes/NEWCODE").set({
        coupleId: "new-couple",
        memberIds: [USER_B],
      }),
    );
  });

  it("最初から2人分のミラーは作れない（定員を偽装できない）", async () => {
    await assertFails(
      asA().doc("inviteCodes/NEWCODE").set({
        coupleId: "new-couple",
        memberIds: [USER_A, USER_B],
      }),
    );
  });

  it("1人のミラーに2人目として自分を追加できる", async () => {
    await seedInviteCode(testEnv, { members: [USER_A] });

    await assertSucceeds(
      asC().doc("inviteCodes/A3K9PZ").update({ memberIds: [USER_A, USER_C] }),
    );
  });

  it("すでに2人埋まっているミラーに3人目は追加できない", async () => {
    await seedInviteCode(testEnv, { members: [USER_A, USER_B] });

    await assertFails(
      asC().doc("inviteCodes/A3K9PZ").update({ memberIds: [USER_A, USER_B, USER_C] }),
    );
  });

  it("更新でcoupleIdを書き換えられない", async () => {
    await seedInviteCode(testEnv, { members: [USER_A] });

    await assertFails(
      asC().doc("inviteCodes/A3K9PZ").update({
        coupleId: "someone-elses-couple",
        memberIds: [USER_A, USER_C],
      }),
    );
  });

  it("削除できない", async () => {
    await seedInviteCode(testEnv, { members: [USER_A] });

    await assertFails(asA().doc("inviteCodes/A3K9PZ").delete());
  });
});

describe("couples — ペアの解消（leaveCouple）", () => {
  it("メンバーは自分だけをmemberIdsから外せる", async () => {
    await seedCouple(testEnv, { members: [USER_A, USER_B] });

    await assertSucceeds(
      asA().doc(`couples/${COUPLE_ID}`).update({ memberIds: [USER_B] }),
    );
  });

  it("メンバーでない第三者はmemberIdsを書き換えられない", async () => {
    await seedCouple(testEnv, { members: [USER_A, USER_B] });

    await assertFails(
      asC().doc(`couples/${COUPLE_ID}`).update({ memberIds: [USER_A] }),
    );
  });

  it("自分しかいないペアは自分で削除できる", async () => {
    await seedCouple(testEnv, { members: [USER_A] });

    await assertSucceeds(asA().doc(`couples/${COUPLE_ID}`).delete());
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

describe("users — reportCallMonth/reportCallCountはクライアントから書き換えられない", () => {
  it("新規ドキュメント作成時にreportCallCountを含められない", async () => {
    await assertFails(
      asA().doc(`users/${USER_A}`).set({ displayName: "A", reportCallCount: 0 }),
    );
  });

  it("既にカウントが付いたドキュメントに対し、カウントをリセットする書き込みは拒否される", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${USER_A}`).set({
        displayName: "A",
        reportCallMonth: "2026-08",
        reportCallCount: 5,
      });
    });

    await assertFails(
      asA().doc(`users/${USER_A}`).set({ reportCallCount: 0 }, { merge: true }),
    );
  });
});

describe("bugReports — 書き込みは常に拒否、読み取りは自分の報告のみ", () => {
  // submitBugReport（Cloud Functions、Admin SDK）だけが書き込める。
  // Gemini判定を経ずにクライアントが直接キューへ書き込めると、
  // 分類チェックそのものを迂回できてしまうため。
  it("作成できない", async () => {
    await assertFails(
      asA().doc("bugReports/report-1").set({
        rawText: "テスト",
        classification: "bug",
        status: "pending",
        createdBy: USER_A,
      }),
    );
  });

  it("自分の報告は読み取れる（送った報告の状況確認用）", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("bugReports/report-1").set({
        rawText: "テスト",
        classification: "bug",
        status: "pending",
        createdBy: USER_A,
      });
    });

    await assertSucceeds(asA().doc("bugReports/report-1").get());
  });

  it("他人の報告は読み取れない", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("bugReports/report-1").set({
        rawText: "テスト",
        classification: "bug",
        status: "pending",
        createdBy: USER_A,
      });
    });

    await assertFails(asB().doc("bugReports/report-1").get());
  });

  it("自分の報告でも更新はできない（statusをdoneに書き換える等）", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("bugReports/report-1").set({
        rawText: "テスト",
        classification: "bug",
        status: "pending",
        createdBy: USER_A,
      });
    });

    await assertFails(asA().doc("bugReports/report-1").update({ status: "done" }));
  });
});
