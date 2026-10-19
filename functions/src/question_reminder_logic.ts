// ── デイリー質問（ふたりの質問）のリマインダー判定ロジック（純粋関数のみ）──
// Firestore や FCM に触れないため、エミュレータ無しで単体テストできる。
// index.ts はここから import して、I/O と組み合わせるだけにする。
//
// TimeTreeなど競合のカレンダー機能には無い「ふたりの質問」だが、開いて
// 気づかない限り答え忘れたまま日が変わって終わってしまう。サービス終了した
// Pairyの移行先として比較されるSumOne/Twinestが持つ「毎日のプロンプト通知」
// に近い体験として、その日まだ回答していないメンバーだけに1日1回リマインドする。

const TOKYO_OFFSET_MS = 9 * 60 * 60 * 1000;

/**
 * nowMs を Asia/Tokyo の日付として 'yyyy-MM-dd' 形式に変換する。
 *
 * lib/utils/daily_question_picker.dart の dateKey（端末のローカル時刻を
 * DateFormat('yyyy-MM-dd')で整形したもの）と一致させる必要がある
 * （questionAnswers のドキュメントIDが `${dateKey}_$uid` のため）。
 * Cloud Functions の実行環境は必ずしも Asia/Tokyo とは限らないため、
 * ホストのタイムゾーンに依存しないよう UTC のフィールドから組み立てる。
 */
export function tokyoDateKey(nowMs: number): string {
  const tokyo = new Date(nowMs + TOKYO_OFFSET_MS);
  const year = tokyo.getUTCFullYear();
  const month = String(tokyo.getUTCMonth() + 1).padStart(2, "0");
  const day = String(tokyo.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/** メンバー1人ぶんの、デイリー質問リマインダー判定に要る情報。 */
export interface QuestionReminderMember {
  uid: string;
  /** 今日の質問にすでに回答済みか */
  answered: boolean;
  notifyOnDailyQuestion: boolean;
}

/**
 * 今日まだ回答しておらず、通知が有効なメンバーだけを、1人1回に絞り込む。
 *
 * members には全カップルぶんのメンバーを並べて渡す。同じuidが複数の
 * カップルに入っていることがある（ペアリング画面で自分の招待コードを
 * 作ってから相手のコードで参加すると、作った側の1人だけのカップルが
 * 残る）。カップルごとに判定していた頃は、そういう人にだけ通知が2通届き、
 * しかもアプリが見ていない方のカップルでは回答が永久に無いので、回答
 * 済みの日にも通知が届いていた。どれか1つのカップルで回答していれば
 * 回答済みとみなし、通知は1人1通にする。
 */
export function resolveQuestionReminderTargets(members: QuestionReminderMember[]): string[] {
  const answeredUids = new Set(members.filter((m) => m.answered).map((m) => m.uid));
  const targets = new Set<string>();
  for (const member of members) {
    if (!answeredUids.has(member.uid) && member.notifyOnDailyQuestion) targets.add(member.uid);
  }
  return [...targets];
}
