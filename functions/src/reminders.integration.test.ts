import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import {
  DEFAULT_REMINDER_MINUTES_BEFORE,
  isStale,
  nextOccurrence,
  QUERY_LOOKAHEAD_MS,
  resolveMinutesBefore,
  resolveReminderTargets,
  shouldRemindNow,
} from "./reminder_logic";

// リマインダーの「Firestore を読んで、判定して、書き戻す」経路のテスト。
//
// reminder_logic.test.ts は判定そのものを純粋関数として検証している。
// こちらが見るのはその外側で、実際のドキュメント構造から正しく値を取り出せるか、
// 送信済みフラグが期待どおり書き戻るか。ここが壊れると、判定が正しくても
// 通知が二重に飛ぶか永久に来なくなる。
//
// FIRESTORE_EMULATOR_HOST が無い場合はスキップする（純粋関数のテストは
// エミュレータ無しでも回したいため、実行を止めない）。
const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;

const COUPLE_ID = "couple-x";
const USER_A = "user-a";
const USER_B = "user-b";

let app: ReturnType<typeof initializeApp> | undefined;
let db: FirebaseFirestore.Firestore;

const MINUTE = 60000;

/** 本番の processOneTimeEvents と同じ順序で、単発予定の送信対象を数える。 */
async function collectOneTimeTargets(nowMs: number) {
  const lookaheadCutoff = Timestamp.fromMillis(nowMs + QUERY_LOOKAHEAD_MS);
  const snap = await db
    .collectionGroup("events")
    .where("reminded", "==", false)
    .where("date", "<=", lookaheadCutoff)
    .get();
  const sent: Array<{ eventId: string; uid: string; minutesBefore: number }> = [];
  const cleanedUp: string[] = [];

  for (const doc of snap.docs) {
    const data = doc.data() as {
      date: Timestamp;
      recurring?: boolean;
      title: string;
      deletedAt?: Timestamp | null;
    };
    if (data.recurring) continue;
    if (data.deletedAt) continue;

    const eventMs = data.date.toDate().getTime();
    if (isStale(eventMs, nowMs)) {
      cleanedUp.push(doc.id);
      continue;
    }

    const coupleId = doc.ref.parent.parent?.id;
    if (!coupleId) continue;
    const memberIds: string[] =
      (await db.collection("couples").doc(coupleId).get()).data()?.memberIds ?? [];

    for (const uid of memberIds) {
      const user = (await db.collection("users").doc(uid).get()).data() as
        | { remindersEnabled?: boolean; reminderMinutesBefore?: number }
        | undefined;
      if (!user || user.remindersEnabled === false) continue;

      const minutesBefore = resolveMinutesBefore(user.reminderMinutesBefore);
      if (!shouldRemindNow(eventMs, minutesBefore, nowMs)) continue;
      sent.push({ eventId: doc.id, uid, minutesBefore });
    }
  }

  return { sent, cleanedUp };
}

/**
 * 本番の processOneTimeEvents と同じ順序・同じ書き戻しロジックで、
 * 1回ぶんの実行をシミュレートする。collectOneTimeTargets と違い、
 * remindedUids / reminded を実際にFirestoreへ書き戻すので、
 * 「1回目の実行の結果が2回目の実行にどう影響するか」を検証できる。
 */
async function runOneTimeEventsPass(nowMs: number) {
  const lookaheadCutoff = Timestamp.fromMillis(nowMs + QUERY_LOOKAHEAD_MS);
  const snap = await db
    .collectionGroup("events")
    .where("reminded", "==", false)
    .where("date", "<=", lookaheadCutoff)
    .get();
  const sent: Array<{ eventId: string; uid: string }> = [];

  for (const doc of snap.docs) {
    const data = doc.data() as {
      date: Timestamp;
      recurring?: boolean;
      remindedUids?: string[];
      deletedAt?: Timestamp | null;
    };
    if (data.recurring) continue;
    if (data.deletedAt) continue;

    const eventMs = data.date.toDate().getTime();
    if (isStale(eventMs, nowMs)) {
      await doc.ref.update({ reminded: true });
      continue;
    }

    const coupleId = doc.ref.parent.parent?.id;
    if (!coupleId) continue;
    const memberIds: string[] =
      (await db.collection("couples").doc(coupleId).get()).data()?.memberIds ?? [];
    const alreadyRemindedUids = new Set(data.remindedUids ?? []);

    const members = await Promise.all(
      memberIds.map(async (uid) => {
        const user = (await db.collection("users").doc(uid).get()).data() as
          | { remindersEnabled?: boolean; reminderMinutesBefore?: number }
          | undefined;
        return {
          uid,
          alreadyReminded: alreadyRemindedUids.has(uid),
          remindersEnabled: !!user && user.remindersEnabled !== false,
          minutesBefore: resolveMinutesBefore(user?.reminderMinutesBefore),
        };
      }),
    );

    const { toRemind, fullySettled } = resolveReminderTargets(members, eventMs, nowMs);
    for (const uid of toRemind) sent.push({ eventId: doc.id, uid });

    if (toRemind.length > 0 || fullySettled) {
      await doc.ref.update({
        remindedUids: [...alreadyRemindedUids, ...toRemind],
        reminded: fullySettled,
      });
    }
  }

  return sent;
}

/**
 * 本番の processRecurringEvents と同じ順序・同じ書き戻しロジックで、
 * 毎年繰り返す予定の1回ぶんの実行をシミュレートする。
 *
 * nextOccurrenceMs は課題8フェーズ3（クエリの絞り込み）向けの準備で、
 * このフェーズではまだクエリを絞り込まず全件走査したうえで書き戻すだけ
 * （docs/open-issues.md 参照）。既存ドキュメントに値が無くても、
 * 次に processRecurringEvents が回ったタイミングで自然に埋まる
 * （バックフィルのための移行スクリプトを別途用意する必要がない）ことを、
 * このテストで確認する。
 */
async function runRecurringEventsPass(nowMs: number) {
  const snap = await db.collectionGroup("events").where("recurring", "==", true).get();
  const sent: Array<{ eventId: string; uid: string }> = [];

  for (const doc of snap.docs) {
    const data = doc.data() as {
      date: Timestamp;
      deletedAt?: Timestamp | null;
      remindedUids?: string[];
      remindedYear?: number | null;
      remindedUidsYear?: number | null;
      nextOccurrenceMs?: Timestamp | null;
    };
    if (data.deletedAt) continue;

    const occurrence = nextOccurrence(data.date.toDate(), nowMs);
    const occurrenceYear = occurrence.getFullYear();
    const occurrenceMs = occurrence.getTime();
    const needsOccurrenceRefresh = data.nextOccurrenceMs?.toMillis() !== occurrenceMs;

    if (data.remindedYear === occurrenceYear) {
      if (needsOccurrenceRefresh) {
        await doc.ref.update({ nextOccurrenceMs: Timestamp.fromMillis(occurrenceMs) });
      }
      continue;
    }

    const coupleId = doc.ref.parent.parent?.id;
    if (!coupleId) continue;
    const memberIds: string[] =
      (await db.collection("couples").doc(coupleId).get()).data()?.memberIds ?? [];

    const alreadyRemindedUids =
      data.remindedUidsYear === occurrenceYear ? new Set(data.remindedUids ?? []) : new Set<string>();

    const members = await Promise.all(
      memberIds.map(async (uid) => {
        const user = (await db.collection("users").doc(uid).get()).data() as
          | { remindersEnabled?: boolean; reminderMinutesBefore?: number }
          | undefined;
        return {
          uid,
          alreadyReminded: alreadyRemindedUids.has(uid),
          remindersEnabled: !!user && user.remindersEnabled !== false,
          minutesBefore: resolveMinutesBefore(user?.reminderMinutesBefore),
        };
      }),
    );

    const { toRemind, fullySettled } = resolveReminderTargets(members, occurrenceMs, nowMs);
    for (const uid of toRemind) sent.push({ eventId: doc.id, uid });

    if (toRemind.length > 0 || fullySettled || needsOccurrenceRefresh) {
      await doc.ref.update({
        ...(toRemind.length > 0 || fullySettled
          ? {
              remindedUids: [...alreadyRemindedUids, ...toRemind],
              remindedUidsYear: occurrenceYear,
              remindedYear: fullySettled ? occurrenceYear : null,
            }
          : {}),
        nextOccurrenceMs: Timestamp.fromMillis(occurrenceMs),
      });
    }
  }

  return sent;
}

describe("リマインダーのFirestore経路", { skip: EMULATOR ? false : "エミュレータ未起動" }, () => {
  before(() => {
    app = initializeApp({ projectId: "aimaru-test" }, `it-${Date.now()}`);
    db = getFirestore(app);
    db.settings({ ignoreUndefinedProperties: true });
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  afterEach(async () => {
    for (const path of ["users", "couples"]) {
      const docs = await db.collection(path).listDocuments();
      await Promise.all(docs.map((d) => db.recursiveDelete(d)));
    }
  });

  async function seed({
    eventDate,
    recurring = false,
    reminded = false,
    deletedAt = null,
    users,
    extra = {},
  }: {
    eventDate: Date;
    recurring?: boolean;
    reminded?: boolean;
    deletedAt?: Timestamp | null;
    users: Record<string, { remindersEnabled?: boolean; reminderMinutesBefore?: number }>;
    // 既に一部処理が進んだ状態（remindedYear等）を再現するための上書き用。
    extra?: Record<string, unknown>;
  }) {
    await db.collection("couples").doc(COUPLE_ID).set({
      memberIds: Object.keys(users),
      inviteCode: "A3K9PZ",
    });
    for (const [uid, settings] of Object.entries(users)) {
      await db.collection("users").doc(uid).set({ displayName: uid, fcmToken: `token-${uid}`, ...settings });
    }
    await db.collection("couples").doc(COUPLE_ID).collection("events").doc("event-1").set({
      coupleId: COUPLE_ID,
      title: "デート",
      date: Timestamp.fromDate(eventDate),
      type: "date",
      createdBy: USER_A,
      recurring,
      reminded,
      remindedYear: null,
      deletedAt,
      ...extra,
    });
  }

  it("各メンバーの設定に応じて送信対象を決める", async () => {
    const nowMs = Date.now();
    await seed({
      eventDate: new Date(nowMs + 60 * MINUTE),
      users: {
        [USER_A]: { reminderMinutesBefore: 60 },
        [USER_B]: { reminderMinutesBefore: 1440 },
      },
    });

    const { sent } = await collectOneTimeTargets(nowMs);

    assert.deepEqual(
      sent.map((s) => s.uid),
      [USER_A],
      "60分前設定のAだけが対象。1日前設定のBはまだ",
    );
  });

  it("remindersEnabled が false のメンバーは対象外", async () => {
    const nowMs = Date.now();
    await seed({
      eventDate: new Date(nowMs + 60 * MINUTE),
      users: {
        [USER_A]: { reminderMinutesBefore: 60, remindersEnabled: false },
        [USER_B]: { reminderMinutesBefore: 60 },
      },
    });

    const { sent } = await collectOneTimeTargets(nowMs);

    assert.deepEqual(sent.map((s) => s.uid), [USER_B]);
  });

  it("reminderMinutesBefore 未設定なら既定値が使われる", async () => {
    const nowMs = Date.now();
    await seed({
      eventDate: new Date(nowMs + DEFAULT_REMINDER_MINUTES_BEFORE * MINUTE),
      users: { [USER_A]: {} },
    });

    const { sent } = await collectOneTimeTargets(nowMs);

    assert.equal(sent.length, 1);
    assert.equal(sent[0].minutesBefore, DEFAULT_REMINDER_MINUTES_BEFORE);
  });

  it("reminded が true の予定はクエリに乗らない", async () => {
    const nowMs = Date.now();
    await seed({
      eventDate: new Date(nowMs + 60 * MINUTE),
      reminded: true,
      users: { [USER_A]: { reminderMinutesBefore: 60 } },
    });

    const { sent } = await collectOneTimeTargets(nowMs);

    assert.deepEqual(sent, [], "送信済みの予定を二度拾わない");
  });

  it("ゴミ箱に入っている（論理削除済みの）予定は通知しない", async () => {
    const nowMs = Date.now();
    await seed({
      eventDate: new Date(nowMs + 60 * MINUTE),
      deletedAt: Timestamp.fromMillis(nowMs - MINUTE),
      users: { [USER_A]: { reminderMinutesBefore: 60 } },
    });

    const { sent } = await collectOneTimeTargets(nowMs);

    assert.deepEqual(sent, [], "復元されるかもしれない間はリマインダーを送らない");
  });

  it("大きく過ぎた予定は通知せず片付け対象になる", async () => {
    const nowMs = Date.now();
    await seed({
      eventDate: new Date(nowMs - 48 * 60 * MINUTE),
      users: { [USER_A]: { reminderMinutesBefore: 60 } },
    });

    const { sent, cleanedUp } = await collectOneTimeTargets(nowMs);

    assert.deepEqual(sent, []);
    assert.deepEqual(cleanedUp, ["event-1"]);
  });

  it("先読み幅を超えて先の予定はクエリの絞り込みで対象外になる", async () => {
    const nowMs = Date.now();
    await seed({
      eventDate: new Date(nowMs + QUERY_LOOKAHEAD_MS + 60 * MINUTE),
      users: { [USER_A]: { reminderMinutesBefore: 60 } },
    });

    const { sent, cleanedUp } = await collectOneTimeTargets(nowMs);

    assert.deepEqual(sent, [], "先読み幅より先の予定はまだ拾わない");
    assert.deepEqual(cleanedUp, [], "片付け対象でもない（クエリに乗っていないだけ）");
  });

  it("recurring の予定は単発の経路では拾わない", async () => {
    const nowMs = Date.now();
    await seed({
      eventDate: new Date(nowMs + 60 * MINUTE),
      recurring: true,
      users: { [USER_A]: { reminderMinutesBefore: 60 } },
    });

    const { sent } = await collectOneTimeTargets(nowMs);

    assert.deepEqual(sent, [], "繰り返しは processRecurringEvents の担当");
  });

  it("Timestamp から復元した日付で発生日を算出できる", async () => {
    const nowMs = new Date(2026, 7, 12, 10, 0).getTime();
    await seed({
      eventDate: new Date(2020, 2, 1, 12, 0),
      recurring: true,
      users: { [USER_A]: {} },
    });

    const doc = await db.collection("couples").doc(COUPLE_ID).collection("events").doc("event-1").get();
    const stored = (doc.data()!.date as Timestamp).toDate();

    assert.equal(nextOccurrence(stored, nowMs).getFullYear(), 2027, "今年は過ぎているので来年");
  });

  // 課題8フェーズ3（クエリの絞り込み）向けの準備。既存の繰り返し予定には
  // nextOccurrenceMsが無いが、移行スクリプトを別途走らせなくても
  // processRecurringEvents が回るたびに自然に埋まることを確認する。
  it("nextOccurrenceMsが無い繰り返し予定は、送信対象が無くてもスキャン時に書き込まれる", async () => {
    const nowMs = new Date(2026, 7, 12, 10, 0).getTime();
    await seed({
      eventDate: new Date(2020, 2, 1, 12, 0),
      recurring: true,
      // 発生日（来年3月）はまだ遠いので、誰にも送信タイミングは来ない
      users: { [USER_A]: { reminderMinutesBefore: 60 } },
    });

    const sent = await runRecurringEventsPass(nowMs);
    assert.deepEqual(sent, [], "送信対象は無い");

    const doc = await db.collection("couples").doc(COUPLE_ID).collection("events").doc("event-1").get();
    const expectedMs = nextOccurrence(new Date(2020, 2, 1, 12, 0), nowMs).getTime();
    assert.equal((doc.data()?.nextOccurrenceMs as Timestamp).toMillis(), expectedMs);
    assert.equal(doc.data()?.remindedYear, null, "送信状態そのものは変えない");
  });

  it("送信済みの年のまま発生日が翌年へ切り替わったら、nextOccurrenceMsだけを更新して送信状態は保つ", async () => {
    const original = new Date(2020, 2, 1, 12, 0);
    const settledOccurrence = new Date(2026, 2, 1, 12, 0); // 2026年3月1日分は送信済み
    await seed({
      eventDate: original,
      recurring: true,
      users: { [USER_A]: { reminderMinutesBefore: 60 } },
      extra: {
        remindedYear: 2026,
        remindedUidsYear: 2026,
        remindedUids: [USER_A],
        nextOccurrenceMs: Timestamp.fromDate(settledOccurrence),
      },
    });

    // 2026年3月分の発生からもう十分に日が経ち、次の発生日（2027年3月）を
    // 見るべきタイミング。
    const nowMs = new Date(2026, 7, 12, 10, 0).getTime();
    const sent = await runRecurringEventsPass(nowMs);
    assert.deepEqual(sent, [], "2027年3月はまだ遠いので送信対象は無い");

    const doc = await db.collection("couples").doc(COUPLE_ID).collection("events").doc("event-1").get();
    const expectedMs = nextOccurrence(original, nowMs).getTime();
    assert.equal((doc.data()?.nextOccurrenceMs as Timestamp).toMillis(), expectedMs, "翌年の発生日へ進む");
    assert.equal(doc.data()?.remindedYear, 2026, "2026年分の送信済み記録はそのまま残す");
    assert.deepEqual(doc.data()?.remindedUids, [USER_A]);
  });

  // メンバーごとに送信タイミングが異なる場合でも、両方が通知を受け取れることの確認。
  // reminded を予定単位のフラグのままにすると、先にタイミングが来たメンバーへ
  // 送った時点でフラグが立ち、もう片方の通知が永久に失われる不具合があった
  // （remindedUids でメンバー別に管理することで修正した）。
  it("メンバーごとに送信タイミングが違っても、両方が別々のタイミングで通知を受け取れる", async () => {
    const nowMs = Date.now();
    // 予定は1日後。Aは「23時間前」設定なのでnowMs+60分後に、
    // Bは「1時間前」設定なのでnowMs+1380分後に、それぞれタイミングを迎える。
    await seed({
      eventDate: new Date(nowMs + 1440 * MINUTE),
      users: {
        [USER_A]: { reminderMinutesBefore: 1380 },
        [USER_B]: { reminderMinutesBefore: 60 },
      },
    });

    // 1回目の実行（Aのタイミング）: Aだけが拾われる
    const firstPass = await runOneTimeEventsPass(nowMs + 60 * MINUTE);
    assert.deepEqual(firstPass.map((s) => s.uid), [USER_A]);

    const afterFirstPass = await db
      .collection("couples")
      .doc(COUPLE_ID)
      .collection("events")
      .doc("event-1")
      .get();
    assert.equal(afterFirstPass.data()?.reminded, false, "Bがまだ残っているのでreminded=trueにしない");
    assert.deepEqual(afterFirstPass.data()?.remindedUids, [USER_A]);

    // 2回目の実行（Bのタイミング）: 修正前は reminded=true で除外され、
    // Bの通知が永久に失われていた。修正後はremindedUidsで判定するので拾われる。
    const secondPass = await runOneTimeEventsPass(nowMs + 1380 * MINUTE);
    assert.deepEqual(secondPass.map((s) => s.uid), [USER_B]);

    const afterSecondPass = await db
      .collection("couples")
      .doc(COUPLE_ID)
      .collection("events")
      .doc("event-1")
      .get();
    assert.equal(afterSecondPass.data()?.reminded, true, "両方に送り終えたので完了扱いになる");
    assert.deepEqual(new Set(afterSecondPass.data()?.remindedUids), new Set([USER_A, USER_B]));
  });
});
