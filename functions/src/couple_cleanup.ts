// ── カップルの削除と、残った「自分だけのカップル」の片付け ─────────
// ペアの解消（dissolveCouple）と定期の片付け（cleanupLeftoverCouples）で
// 同じ削除処理を使う。Firestore と Storage を引数で受け取るので、結合テスト
// からエミュレータを渡して本番と同じ関数をそのまま検証できる。

import { Firestore } from "firebase-admin/firestore";
import { Storage } from "firebase-admin/storage";
import { logger } from "firebase-functions/v2";

import { findLeftoverSoloCouples } from "./couple_cleanup_logic";

export type StorageBucket = ReturnType<Storage["bucket"]>;

/**
 * couples/{coupleId} を、配下のサブコレクション・招待コードのミラー・
 * Storageの写真ごと削除する。
 */
export async function deleteCoupleData(
  db: Firestore,
  bucket: StorageBucket,
  coupleId: string,
): Promise<void> {
  // Storageの写真はFirestoreと別の保管先なので、個別に消す必要がある。
  // 写真が1枚も無いカップルでも空振りするだけでエラーにはならない。
  await bucket.deleteFiles({ prefix: `couples/${coupleId}/`, force: true });

  // inviteCodes/{code} は couples のサブコレクションではなく別の
  // トップレベルコレクションなので、recursiveDeleteの対象に入らない。
  // 消し忘れると、解消済みのcoupleIdを指すミラーだけが孤立して残り、
  // そのコードで参加しようとした人が「couplesドキュメントが無いのに
  // 更新しようとして失敗する」という分かりにくいエラーになる。
  // couples本体を消す前にinviteCodeを読み、対応するミラーも合わせて消す。
  const coupleSnap = await db.collection("couples").doc(coupleId).get();
  const inviteCode = coupleSnap.data()?.inviteCode as string | undefined;
  if (inviteCode) {
    await db.collection("inviteCodes").doc(inviteCode).delete();
  }

  // couples/{coupleId} とその配下（events/chats/todos/
  // questionAnswers/googleCalendarCache）をまとめて削除する。
  await db.recursiveDelete(db.collection("couples").doc(coupleId));
}

/**
 * ペアに入っている人に残った、自分だけのカップルを削除する。
 *
 * 予定などのデータが入っているものは消さずにログへ残す（以前のアプリは
 * どちらのカップルを開くかが不定だったため、残った方で使っていた可能性が
 * ある。アプリは今はペアの方を開くので、残しておいても表には出ない）。
 *
 * @returns 削除したカップルのID
 */
export async function cleanupLeftoverSoloCouples(
  db: Firestore,
  deleteCouple: (coupleId: string) => Promise<void>,
): Promise<string[]> {
  const couplesSnap = await db.collection("couples").get();
  const leftovers = findLeftoverSoloCouples(
    couplesSnap.docs.map((doc) => ({ id: doc.id, memberIds: doc.data().memberIds ?? [] })),
  );

  const deleted: string[] = [];
  for (const { coupleId, uid } of leftovers) {
    const ref = db.collection("couples").doc(coupleId);

    // 一覧を読んでから今までの間に誰かが招待コードで参加していたら、
    // もう自分だけのカップルではないので消さない。
    const memberIds: string[] = (await ref.get()).data()?.memberIds ?? [];
    if (memberIds.length !== 1 || memberIds[0] !== uid) continue;

    const subcollections = await ref.listCollections();
    const hasData = (
      await Promise.all(subcollections.map(async (col) => !(await col.limit(1).get()).empty))
    ).some(Boolean);
    if (hasData) {
      logger.warn(
        `cleanupLeftoverSoloCouples: ${coupleId}（${uid}だけのカップル）にデータがあるため削除しません`,
      );
      continue;
    }

    await deleteCouple(coupleId);
    logger.info(`cleanupLeftoverSoloCouples: ${uid}に残っていた${coupleId}を削除しました`);
    deleted.push(coupleId);
  }
  return deleted;
}
