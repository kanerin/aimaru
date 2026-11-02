import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Timestamp } from "firebase-admin/firestore";

import {
  budgetNotificationTargets,
  buildBudgetPlanNotification,
  classifyBudgetPlanChange,
  contentChanged,
  stableStringify,
} from "./budget_notification_logic";

const activePlan = (overrides: Record<string, unknown> = {}) => ({
  name: "確定プラン",
  isActive: true,
  members: [{ memberId: "a", displayName: "A", monthlyTakeHome: 180000, bonuses: [] }],
  sharedExpenses: [{ id: "rent", label: "家賃", monthlyAmount: 110000, category: "housing" }],
  savingsGoal: {
    targetAmount: 8000000,
    deadline: Timestamp.fromDate(new Date("2029-10-31T00:00:00+09:00")),
  },
  createdBy: "a",
  updatedBy: "a",
  updatedAt: Timestamp.fromMillis(1000),
  ...overrides,
});

describe("classifyBudgetPlanChange", () => {
  it("確定プランとして新しく作られたら created", () => {
    assert.equal(classifyBudgetPlanChange(undefined, activePlan()), "created");
  });

  it("シミュレーションが確定プランになったら activated", () => {
    assert.equal(
      classifyBudgetPlanChange(activePlan({ isActive: false }), activePlan({ updatedBy: "b" })),
      "activated",
    );
  });

  it("確定プランの中身が変わったら updated", () => {
    const after = activePlan({
      sharedExpenses: [{ id: "rent", label: "家賃", monthlyAmount: 120000, category: "housing" }],
      updatedBy: "b",
      updatedAt: Timestamp.fromMillis(2000),
    });
    assert.equal(classifyBudgetPlanChange(activePlan(), after), "updated");
  });

  it("期限（Timestamp）が変わっても updated", () => {
    const after = activePlan({
      savingsGoal: {
        targetAmount: 8000000,
        deadline: Timestamp.fromDate(new Date("2030-03-31T00:00:00+09:00")),
      },
    });
    assert.equal(classifyBudgetPlanChange(activePlan(), after), "updated");
  });

  it("更新者・更新日時だけが変わった書き込みでは通知しない", () => {
    const after = activePlan({ updatedBy: "b", updatedAt: Timestamp.fromMillis(5000) });
    assert.equal(classifyBudgetPlanChange(activePlan(), after), null);
  });

  it("シミュレーションの作成・変更では通知しない", () => {
    assert.equal(classifyBudgetPlanChange(undefined, activePlan({ isActive: false })), null);
    assert.equal(
      classifyBudgetPlanChange(activePlan({ isActive: false }), activePlan({ isActive: false, name: "案2" })),
      null,
    );
  });

  it("確定から外れた書き込み（別のプランを確定にしたとき）では通知しない", () => {
    assert.equal(classifyBudgetPlanChange(activePlan(), activePlan({ isActive: false })), null);
  });

  it("削除では通知しない", () => {
    assert.equal(classifyBudgetPlanChange(activePlan({ isActive: false }), undefined), null);
  });
});

describe("contentChanged / stableStringify", () => {
  it("キーの順序が違うだけなら変わっていない扱い", () => {
    assert.equal(
      contentChanged({ a: 1, b: { c: 2, d: 3 } }, { b: { d: 3, c: 2 }, a: 1 }),
      false,
    );
  });

  it("配列の順序（並び替え）は変更として扱う", () => {
    assert.equal(contentChanged({ list: [1, 2] }, { list: [2, 1] }), true);
  });

  it("Timestampはミリ秒で比べる", () => {
    assert.equal(stableStringify(Timestamp.fromMillis(123)), stableStringify(Timestamp.fromMillis(123)));
    assert.notEqual(stableStringify(Timestamp.fromMillis(123)), stableStringify(Timestamp.fromMillis(124)));
  });
});

describe("budgetNotificationTargets", () => {
  it("変更した本人には通知しない", () => {
    assert.deepEqual(budgetNotificationTargets(["a", "b"], "a"), ["b"]);
  });

  it("相手がまだいない（1人だけの）カップルなら宛先なし", () => {
    assert.deepEqual(budgetNotificationTargets(["a"], "a"), []);
  });
});

describe("buildBudgetPlanNotification", () => {
  it("変更の種類ごとに、誰が・どのプランをかを伝える", () => {
    assert.deepEqual(buildBudgetPlanNotification("updated", "あい", "確定プラン"), {
      title: "確定プランが更新されました",
      body: "あいさんが確定プラン「確定プラン」を変更しました",
    });
    assert.deepEqual(buildBudgetPlanNotification("activated", "まる", "家賃上げた場合"), {
      title: "確定プランが変わりました",
      body: "まるさんが「家賃上げた場合」を確定プランにしました",
    });
    assert.equal(
      buildBudgetPlanNotification("created", "あい", "確定プラン").title,
      "家計プランが作成されました",
    );
  });

  it("プラン名が空なら「家計プラン」と表示する", () => {
    assert.equal(
      buildBudgetPlanNotification("updated", "あい", "  ").body,
      "あいさんが確定プラン「家計プラン」を変更しました",
    );
  });
});
