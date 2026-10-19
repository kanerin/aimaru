// ── 残った「自分だけのカップル」の判定（純粋関数のみ）───────────
// Firestore に触れないため、エミュレータ無しで単体テストできる。
// 読み書きは couple_cleanup.ts が受け持つ。
//
// ペアリング画面は開いた時点で自分の招待コード（自分だけのカップル）を
// 作るため、相手のコードで参加した側にはそれが残っていた（アプリ側の
// joinWithCodeで参加時に片付けるようにしたが、それ以前に残ったものや、
// 片付けに失敗したもの、古いアプリから参加したものがある）。

export interface CoupleMembers {
  id: string;
  memberIds: string[];
}

export interface LeftoverCouple {
  coupleId: string;
  uid: string;
}

/**
 * メンバーが1人だけで、その人が別の（2人以上の）カップルにも入っている
 * カップルを返す。まだ相手が参加していないだけの招待中のカップル
 * （その人が他のペアに入っていない）は対象にしない。
 */
export function findLeftoverSoloCouples(couples: CoupleMembers[]): LeftoverCouple[] {
  const pairedUids = new Set(
    couples.filter((c) => c.memberIds.length >= 2).flatMap((c) => c.memberIds),
  );
  return couples
    .filter((c) => c.memberIds.length === 1 && pairedUids.has(c.memberIds[0]))
    .map((c) => ({ coupleId: c.id, uid: c.memberIds[0] }));
}
