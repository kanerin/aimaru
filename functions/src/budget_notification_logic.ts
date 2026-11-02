// ── 家計プラン（確定プラン）の変更通知を判定する純粋関数 ───────────
// Firestoreや外部APIに触れないため、エミュレータ無しで単体テストできる。
// index.ts の onBudgetPlanWritten はここから import して、I/O と組み合わせるだけにする。
//
// 通知するのは「確定プラン」が変わったときだけ。シミュレーション（仮案）を
// いじるたびに相手へ通知が飛ぶと、試しに金額を動かすだけで相手のスマホが鳴る。

export type BudgetPlanChangeKind =
  | "created"   // 確定プランとして新しく作られた
  | "activated" // シミュレーションが確定プランになった
  | "updated";  // 確定プランの中身が変わった

type DocData = Record<string, unknown>;

// 「中身が変わったか」の比較から外すメタ情報。updatedAt/updatedByだけが
// 変わった書き込み（中身は同じ）で通知しないようにする。
const META_FIELDS = new Set(["createdAt", "createdBy", "updatedAt", "updatedBy"]);

export function classifyBudgetPlanChange(
  before: DocData | undefined,
  after: DocData | undefined,
): BudgetPlanChangeKind | null {
  // 削除、またはシミュレーションのまま／確定から外れた書き込みは通知しない
  // （別のプランを確定にすると、元の確定プランはisActive=falseに更新される。
  // その書き込みでは通知せず、新しく確定になった側の書き込みで1回だけ通知する）。
  if (!after || after.isActive !== true) return null;
  if (!before) return "created";
  if (before.isActive !== true) return "activated";
  return contentChanged(before, after) ? "updated" : null;
}

export function contentChanged(before: DocData, after: DocData): boolean {
  return stableStringify(withoutMeta(before)) !== stableStringify(withoutMeta(after));
}

function withoutMeta(data: DocData): DocData {
  const result: DocData = {};
  for (const [key, value] of Object.entries(data)) {
    if (!META_FIELDS.has(key)) result[key] = value;
  }
  return result;
}

// キーの順序に依存しない文字列化。Firestoreから読んだMapはキーの順序が
// 保証されないため、そのままJSON.stringifyすると同じ内容でも食い違う。
// Timestamp（toMillisを持つ値）はミリ秒に直して比べる。
export function stableStringify(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value === "object" && typeof (value as { toMillis?: unknown }).toMillis === "function") {
    return `{"__ts":${(value as { toMillis: () => number }).toMillis()}}`;
  }
  if (value instanceof Date) return `{"__ts":${value.getTime()}}`;
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (typeof value === "object") {
    const entries = Object.entries(value as DocData)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([k, v]) => `${JSON.stringify(k)}:${stableStringify(v)}`);
    return `{${entries.join(",")}}`;
  }
  return JSON.stringify(value);
}

// 通知の宛先: 変更した本人以外のメンバー
export function budgetNotificationTargets(memberIds: string[], actorId: string): string[] {
  return memberIds.filter((id) => id !== actorId);
}

export function buildBudgetPlanNotification(
  kind: BudgetPlanChangeKind,
  actorName: string,
  planName: string,
): { title: string; body: string } {
  const name = planName.trim().length > 0 ? planName.trim() : "家計プラン";
  switch (kind) {
    case "created":
      return {
        title: "家計プランが作成されました",
        body: `${actorName}さんが家計プラン「${name}」を作成しました`,
      };
    case "activated":
      return {
        title: "確定プランが変わりました",
        body: `${actorName}さんが「${name}」を確定プランにしました`,
      };
    case "updated":
      return {
        title: "確定プランが更新されました",
        body: `${actorName}さんが確定プラン「${name}」を変更しました`,
      };
  }
}
