# AIMARU で踏みやすい設計上の地雷

実際に踏んだ／踏みかけたものだけを書いている。新しく見つけたら追記すること。
ここに書いておけば、次のエージェントが同じ穴に落ちずに済む。

## Flutter / UI

### table_calendar のカスタム markerBuilder は CalendarStyle をほぼ無視する

`calendarBuilders.markerBuilder` を渡すと、返した Widget が
`Stack(alignment: markersAlignment)` の子として**そのまま**置かれる。
`markerSize` / `markerMargin` / `markersAnchor` は一切参照されない。

一方で日付の丸（`todayDecoration` / `selectedDecoration`）は「セル −
`cellMargin`」いっぱいに描かれる。つまり両者が同じ下端を奪い合う。

対処は `cellMargin` の下側にマーカー用の帯を確保して丸を上へ逃がすこと。
`lib/screens/calendar_screen.dart` の `_miniCellMargin` がそれ。
マーカーの位置を変えたくなったら `CalendarStyle` ではなく `markerBuilder` の中を触る。

### 全体表示では「選択中の日」を作らない

`_buildExpandedView` で `selectedDayPredicate` が true を返す日を作ると、
`todayBuilder` などが適用されずデフォルト描画へフォールバックし、**当日の予定が
消えて見える**。過去に実際に起きた不具合なので、全体表示に選択状態を持ち込まない。

### ホームの4タブは IndexedStack で全部マウントし続けている

`lib/main.dart` の `_HomeShell` は `IndexedStack` を使っている。
`pages[_index]` のように切り替えるとタブを離れた画面が破棄され、**AIチャットの
会話がタブ切り替えのたびに消える**。パフォーマンスを理由に変えたくなっても、
状態保持が要件（TC-048）なので変えない。

## Firestore

### create 時は resource が null

セキュリティルールで `create` を書くとき、`resource` はまだ存在せず null になる。
`resource.data` ではなく `request.resource.data` で判定する。

### ルールが参照するフィールドとクエリの絞り込みが一致しないと常に拒否される

招待コードでの参加は `inviteCode` で検索するが、ルールは `memberIds` を見たい。
Firestore はこの組み合わせを「証明」できず、常に拒否になる。

そのため `couples` の read は `request.auth != null` まで緩めてあり、
**認証済みなら他人のペアの `memberIds` や `anniversary` が読めてしまう**
（TC-072 に記録済み）。安全性は write 側（create / update / delete）で担保している。
ここを締めるなら `inviteCode` を別コレクションへ分離する設計変更が要る。

### Storage ルールがリポジトリに無い

`firestore.rules` は管理されているが、Storage のルールは README に記載があるだけで
`storage.rules` ファイルが存在しない（TC-077）。Storage 周りを触るなら先にこれを
ファイル化する。

## Cloud Functions

### reminded は予定単位で、メンバー単位ではない

`reminded` / `remindedYear` は予定ドキュメントのフィールド。誰か1人に送った時点で
true になるため、**メンバーの通知設定が違う（60分前と1日前など）と、片方の通知が
永久に失われる**（TC-059）。未修正の既知バグ。リマインダー周りを触るなら、
メンバー単位の送信済み管理への変更を検討する。

### 判定ロジックは reminder_logic.ts に集約してある

`functions/src/reminder_logic.ts` が純粋関数だけを持ち、`index.ts` が I/O と
組み合わせる。判定を変えるときは `reminder_logic.ts` を触ってテストを足す。
`index.ts` に判定を書き戻すとテストできなくなる。

### JavaScript の Date は存在しない日付を繰り上げる

`new Date(2026, 1, 29)` は 3/1 になる。2/29 の記念日を平年に評価すると月が飛ぶ。
`occurrenceInYear` が月末で頭打ちにして対処済み。同種の日付計算を足すときは注意。

### テストファイルはビルド成果物から除外している

`functions/tsconfig.json` が `src/**/*.test.ts` を `exclude` している。
型チェックは `npm run typecheck`（`tsconfig.test.json` 経由、テスト込み）で行う。
新しくテストを足しても `npm run build` の出力には入らない。

### collectionGroup の全件走査でスケールしない

`sendReminders` は `reminded == false` と `recurring == true` で全件走査し、
ループ内から `couples` と `users` を1件ずつ取っている。ユーザー数に対して
課金と実行時間が線形以上に伸びる（REQ-028 / FEAT-048）。未修正。

## サービス層

### コンストラクタで Firestore と uid を差し込める

`CoupleService` / `EventService` は `({FirebaseFirestore? firestore, String? uid})`
を受ける。引数なしなら本番の Firebase を使うので既存の呼び出しはそのまま。
テストでは `fake_cloud_firestore` と固定 uid を渡して Firebase に触れずに検証する。

他のサービスにも同じ形を足すと、そのままテストできるようになる。

### Gemini の応答パースは純粋関数

`parseGeminiReply(String)` が `GenerativeModel` に依存しない形で切り出してある。
プロンプトを変えるときも、パースの契約（壊れた応答から予定を作らない）は
`test/services/gemini_reply_parser_test.dart` が守っている。

## モデル

`AimaruEvent` には**終日フラグと共有範囲の概念が無い**。

- 終日: `GCalEventSummary` には `allDay` があるのにアプリ自前のモデルには無く、
  Google 同期で時刻が捏造される（REQ-013 / FEAT-043）
- 共有範囲: すべての予定がペア双方に見える。「予定ありのみ」「非公開」が選べない
  （REQ-022 / FEAT-041）

どちらも追加するとカレンダー描画・Google 同期・リマインダー判定の3経路すべてに
影響する。片方だけ直すと不整合が出る。

## ビルド・配布

### Gemini API キーはビルド成果物に埋まる

`--dart-define=GEMINI_API_KEY=...` はソースへの直書きは防ぐが、**APK からは
抽出できる**。ソースに無いことと安全であることは別（REQ-026 / FEAT-046）。
根本対処は Cloud Functions の `onCall` へ移して Secret Manager に置くこと。

### OAuth 同意画面が「テスト中」

`calendar.events` は機密スコープのため同意画面はテスト中ステータスで運用している。
**テストユーザーとして登録した Google アカウントしかログインできない**（上限100人）。
ログインが通らないという報告が来たら、まずここを疑う。

### リリース署名鍵の SHA-1 が Firebase に未登録

デバッグキーの SHA-1 しか登録されていないため、リリースビルドでは Google ログインが
失敗する（TC-096）。`android/app/release.keystore` は `.gitignore` 済みで、
**紛失すると Play Store のアプリを二度と更新できない**。

### Cloud Functions は Blaze プラン必須

通知系（`onEventCreated` / `sendReminders`）は従量課金プランでないと動かない。
