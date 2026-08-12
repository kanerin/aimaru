# Notion 反映待ちリスト（AIMARU 開発ハブ）

前セッションで Notion 上に「AIMARU 開発ハブ」を構築したあと、コード側の修正で
判明した訂正・ステータス更新が未反映のまま残っている。セッション途中で Notion の
MCP サーバーが切断され、書き込めなくなったため。

このファイルは**そのまま実行できる作業指示**として書いてある。上から順に適用すれば
反映が完了する。完了したらこのファイルは削除してよい。

対応するコード変更は `claude/notion-reference-feature-posjwr` ブランチの
コミット `d9da4f1` に入っている。

---

## 0. 対象の Notion ページ

| 名前 | URL |
|---|---|
| AIMARU 開発ハブ（親ページ） | https://app.notion.com/p/3b97e232272681c0b0b5c1e46c6b3906 |
| 要件一覧 | https://app.notion.com/p/5219f100bca24ef39c7bc170ceb36343 |
| 機能一覧 | https://app.notion.com/p/e02947d5146c45d3b8d1255356d1d6b4 |
| テスト項目・観点一覧 | https://app.notion.com/p/d386ff38e549483a8192ee34735b94a4 |
| テストケース | https://app.notion.com/p/904382c5a1064f749534c13b6486504a |

データソース ID（新規行の作成に使う）:

- 要件一覧: `a09f810e-c9fe-45de-84a5-cf295a5dc4c7`
- 機能一覧: `c1080ef2-77c7-4d6a-97be-14ee29a92681`
- テスト項目・観点一覧: `e68966a4-2a93-41fb-8df0-68b90b2e6146`
- テストケース: `fda5d476-403e-44a2-a307-701d7482c341`

4つの DB は `要件 ⇄ 機能 ⇄ 観点 ⇄ ケース` の双方向リレーションで繋がっている。

---

## 1. 誤りの訂正（最優先）

### 1-1. REQ-015 の記述が事実と違う

https://app.notion.com/p/3b97e2322726818a871aea247a374a09

前セッションで「AIが返した予定に承認ステップが無く、登録できてしまう」と書いたが、
**これは誤り**。`lib/screens/ai_chat_screen.dart` には AI PARSE カードと
`追加する` / `変更する` ボタンがあり、押すまで Firestore には登録されない。

ユーザーからも「AIチャットの承認は、追加ボタンと一緒に出すでよい」と確認済みで、
現状の設計のままでよい。

- ページ本文の赤いコールアウト（「登録前のユーザー確認ステップは無く…」という趣旨の
  もの）を削除し、代わりに次の内容に差し替える:
  > 承認は AI PARSE カードの `追加する` ボタンが担っている。押すまで Firestore には
  > 登録されない。別途の確認ダイアログは設けない方針（2026-08-12 決定）。
- プロパティ `ステータス`: `実装中` → `実装済み`

### 1-2. TC-047 の期待結果と注記が事実と違う

https://app.notion.com/p/3b97e232272681cea6d7e2fbf604ad1a

- `ケース名`: `AIが提示した予定は追加ボタンを押すまで登録されない`
- `期待結果`: 「予定候補カードが `追加する` / `変更する` ボタン付きで提示され、
  `追加する` を押すまで Firestore に登録されない」
  （**「現状未対応のため失敗する見込み」という記述は削除する。実装済み**）
- `優先度`: `P0 必須` のまま
- `自動化状態`: `未自動化` のまま（ウィジェットテスト未着手）

### 1-3. TC-065 の期待結果が間違っている

https://app.notion.com/p/3b97e2322726811c9435d231a06c6a9f

`formatRelative(1439)` は「1日後」ではなく **「24時間後」** が正しい
（`1439 >= 1440` は偽なので時間表示に落ちる）。実装のテストで確認済み。

- `期待結果`: 「59 → 59分後 / 60 → 1時間後 / 90 → 2時間後 / 1439 → 24時間後 /
  1440 → 1日後 / 2880 → 2日後」

### 1-4. 日本語の表記ミス3件

| ページ | プロパティ | 変更前 | 変更後 |
|---|---|---|---|
| [REQ-020](https://app.notion.com/p/3b97e232272681bbb382edadab585ae4) | 受入基準 | デフォル**と**60分 | デフォル**トの**60分 |
| [REQ-026](https://app.notion.com/p/3b97e23227268171a3fec4308bde8655) | ユーザーストーリー | **悠久**に使われる | **永久**に使われる |
| [REQ-026](https://app.notion.com/p/3b97e23227268171a3fec4308bde8655) | ユーザーストーリー | 課金を**背負する**のは | 課金を**背負う**のは |
| [REQ-033](https://app.notion.com/p/3b97e232272681e8ba6aef921462457d) | ユーザーストーリー | 相手を**誨う**前に / 恋人を**誨う**のは | 相手を**誘う**前に / 恋人を**誘う**のは |

---

## 2. 新規に追加する行

### 2-1. 要件を1件追加（データソース `a09f810e-c9fe-45de-84a5-cf295a5dc4c7`）

コードを読んで見つかった実際の脆弱性で、既存のどの要件にも当てはまらなかった。

| プロパティ | 値 |
|---|---|
| 要件名 | 招待コードが第三者に推測できない |
| 要件ID | REQ-034 |
| カテゴリ | プライバシー・信頼 |
| 優先度 | P0 必須 |
| ステータス | 実装済み |
| ユーザーストーリー | ペアを作った側として、招待コードを知らない人が勝手にペアへ入ってこないと保証されていてほしい。なぜなら招待コードは「まだ相手が決まっていないペア」への参加キーそのものだから。 |
| 市場根拠 | カップルアプリはペアリングが唯一の入口で、そこを突破されると予定・チャット・写真のすべてが第三者に共有される。加えて `couples` の読み取りルールが招待コード検索のため `request.auth != null` まで緩められており（REQ-025 参照）、コードが推測可能だと総当たりの成功率が実用的な水準まで上がる。 |
| 受入基準 | 招待コードが暗号論的乱数から生成され、連続生成しても文字表の連番や規則的な並びにならない。同一プロセスで連続生成した200件に重複が出ない。 |
| 関連機能 | FEAT-015（ペアリングサービス）にリレーション |

ページ本文に入れる内容:

> **修正前の実装（コミット `d9da4f1` 以前）**
> `chars[(DateTime.now().microsecondsSinceEpoch + インデックス) % 32]` で1文字ずつ
> 選んでいたため、6文字が文字表の連番（`ABCDEF` のような並び）になっていた。
> `Random.secure()` に置き換え済み。回帰は TC-008 で監視する。

### 2-2. テストケースを1件追加（データソース `fda5d476-403e-44a2-a307-701d7482c341`）

| プロパティ | 値 |
|---|---|
| ケース名 | 選択日・当日の丸が予定ドットと重ならない |
| ケースID | TC-097 |
| 親観点 | TV-011（カレンダー全体表示の描画）https://app.notion.com/p/3b97e232272681438341da3470a518c9 |
| 前提条件 | 選択表示のミニカレンダーで、選択中の日と当日の両方に予定が1件以上ある |
| 手順 | 1. カレンダー画面を選択表示で描画する<br>2. 選択日セルの丸の描画領域とマーカードットの描画領域を取得する |
| 期待結果 | 丸の下端とドットの上端が重ならない（`cellMargin` 下側に確保したドット帯の中にドットが収まる） |
| 優先度 | P1 重要 |
| 自動化状態 | 未自動化 |
| テストコード | test/screens/calendar_screen_test.dart（想定） |
| 結果 | 未実行 |

ページ本文に入れる内容:

> **原因**: table_calendar はカスタム `markerBuilder` を渡すと
> `markerSize` / `markerMargin` / `markersAnchor` を一切参照せず、返した Widget を
> `Stack(alignment: markersAlignment)` にそのまま置く。一方で日付の丸は
> 「セル − `cellMargin`」いっぱいに描かれるため、両者が同じ下端を奪い合っていた。
> `cellMargin` の下側に 14px のドット帯を確保して丸を上へ逃がすことで解消（`d9da4f1`）。

---

## 3. テストケースのステータス更新

### 3-1. 実行して**成功を確認済み**（8件）

`自動化状態` → `自動化済み`、`結果` → `成功`、`テストコード` → 下記の通り。
Cloud Functions のテストは `cd functions && npm test` で実行し、17件全通過を確認した。

| ケース | URL | テストコード |
|---|---|---|
| TC-053 | https://app.notion.com/p/3b97e2322726817499d5c9c1a4571029 | functions/src/reminder_logic.test.ts「窓の境界（ちょうど8分前後）は送信対象に含む」 |
| TC-054 | https://app.notion.com/p/3b97e232272681808f14c2d8a36b4f03 | functions/src/reminder_logic.test.ts「窓の外（8分超え）は送信対象に含まない」 |
| TC-055 | https://app.notion.com/p/3b97e232272681fd8036dcf71fdba6f3 | functions/src/reminder_logic.test.ts「15分間隔の実行で、どの送信予定時刻も必ず一度は窓に入る」 |
| TC-060 | https://app.notion.com/p/3b97e232272681a9b073f3b57de2b08b | functions/src/reminder_logic.test.ts「今年の発生日が十分過ぎていれば来年へ送る」 |
| TC-061 | https://app.notion.com/p/3b97e2322726817294a3f8ff03919b40 | functions/src/reminder_logic.test.ts「過ぎて24時間以内なら今年扱いのままにする」 |
| TC-062 | https://app.notion.com/p/3b97e232272681929694c6d6c1b0dd9a | functions/src/reminder_logic.test.ts「2月29日の記念日を平年に評価しても3月へ滑らない」 |
| TC-064 | https://app.notion.com/p/3b97e232272681b18012eb233d4b16fb | functions/src/reminder_logic.test.ts「未設定なら既定値を使う」 |
| TC-065 | https://app.notion.com/p/3b97e2322726811c9435d231a06c6a9f | functions/src/reminder_logic.test.ts「分・時間・日で表現が切り替わる」 |

**TC-062 は期待結果も書き換える。** 修正済みなので「失敗する見込み」の記述を消す:

> `期待結果`: 平年に評価しても2月のまま月末（2/28）で頭打ちになり、3月へ繰り上がらない。
> 閏年（2028年など）なら 2/29 のままになる。

### 3-2. テストは書いたが**未実行**（21件）

この環境に Flutter SDK が無く実行できていない。初回の実行は CI になる。
`自動化状態` → `自動化済み`、`結果` → `未実行` のまま、`テストコード` を実在パスへ更新。

| ケース | URL | テストコード |
|---|---|---|
| TC-007 | https://app.notion.com/p/3b97e232272681c3ab46f59e9b7cee35 | test/services/couple_service_test.dart「6桁で紛らわしい文字を含まない」 |
| TC-008 | https://app.notion.com/p/3b97e232272681f4b5cdd27a9dadc847 | test/services/couple_service_test.dart「連番にならず、連続生成しても重複しない」 |
| TC-009 | https://app.notion.com/p/3b97e2322726813f8c04d5fd7648a83e | test/services/couple_service_test.dart「存在しないコードでは参加できない」 |
| TC-010 | https://app.notion.com/p/3b97e2322726816cba32eea7bd9629ff | test/services/couple_service_test.dart「すでに2名いるペアには参加できない」 |
| TC-011 | https://app.notion.com/p/3b97e232272681e6a73fced3f3a98b0d | test/services/couple_service_test.dart「自分が作ったペアには参加できない」 |
| TC-012 | https://app.notion.com/p/3b97e232272681a593f9d87ad1ed12ab | test/services/couple_service_test.dart「小文字・前後空白付きのコードでも参加できる」 |
| TC-017 | https://app.notion.com/p/3b97e232272681cfb750fb0393954f17 | test/services/event_service_test.dart「createdByに操作者が入り、リマインダー用フィールドが初期化される」 |
| TC-018 | https://app.notion.com/p/3b97e232272681768a7ffeb94c34954a | test/services/event_service_test.dart「GeminiParsedEvent経由でも通常の追加と同じ状態になる」 |
| TC-019 | https://app.notion.com/p/3b97e23227268135b186e2263d2486dc | test/services/event_service_test.dart「削除するとドキュメントが消える」 |
| TC-020 | https://app.notion.com/p/3b97e232272681b0adf2c69b9e38416a | test/services/event_service_test.dart「日時を変えるとリマインダーの送信済み状態がリセットされる」 |
| TC-022 | https://app.notion.com/p/3b97e232272681cc97d8ee05897dd02a | test/services/event_service_test.dart「月初00:00と月末23:59の予定を取りこぼさない」 |
| TC-023 | https://app.notion.com/p/3b97e2322726814eb0b9fca14894dac0 | test/services/event_service_test.dart「12月を指定しても翌年1月の計算が破綻しない」 |
| TC-037 | https://app.notion.com/p/3b97e232272681e9a802c9659b3bf8fc | test/services/gemini_reply_parser_test.dart「kind=events の応答を予定候補へ変換できる」 |
| TC-038 | https://app.notion.com/p/3b97e232272681a496faff787f7ae3a6 | test/services/gemini_reply_parser_test.dart「コードブロック囲い付きのJSONでもパースできる」 |
| TC-039 | https://app.notion.com/p/3b97e23227268114a161c35209eb1a68 | test/services/gemini_reply_parser_test.dart「複数件のevents配列をすべて返す」 |
| TC-040 | https://app.notion.com/p/3b97e2322726817caa70ca6b62b36e3c | test/services/gemini_reply_parser_test.dart「kind=text の応答をそのまま返す」 |
| TC-041 | https://app.notion.com/p/3b97e2322726813ca8a4d22eac33873b | test/services/gemini_reply_parser_test.dart「JSONとして不正な応答では予定を作らない」 |
| TC-042 | https://app.notion.com/p/3b97e232272681a98f5bfc29173d5536 | test/services/gemini_reply_parser_test.dart「JSONがオブジェクトでない場合は聞き返す」 |
| TC-043 | https://app.notion.com/p/3b97e232272681b997ffcf5391807673 | test/services/gemini_reply_parser_test.dart「eventsが空配列なら予定を作らずtextへ倒す」 |
| TC-044 | https://app.notion.com/p/3b97e232272681448a20cb9cad7be5ba | test/services/gemini_reply_parser_test.dart「dateがパースできない値でも予定を作らない」 |
| TC-045 | https://app.notion.com/p/3b97e2322726815aa7e1d8f77f6d383f | test/services/gemini_reply_parser_test.dart「未知のtype値は plan にフォールバックする」 |

### 3-3. 変更しないもの（誤解防止のため明記）

- **TC-056 / TC-057 / TC-058 / TC-063** — 判定ロジックは純粋関数化したが、
  Firestore への `reminded` 書き込みや `remindersEnabled` の読み取りは未検証。
  `未自動化` のままにする。
- **TC-059**（メンバーの片方だけが窓に入ると、もう片方の通知が永久に失われる）—
  **未修正のまま**。予定単位の `reminded` をメンバー単位に変える必要があり、
  今回のスコープ外。`未自動化` / 「失敗する見込み」の記述もそのまま残す。

---

## 4. 機能一覧のステータス更新

| 機能 | URL | 変更内容 |
|---|---|---|
| FEAT-015 ペアリングサービス | https://app.notion.com/p/3b97e23227268119b48ed484c1e01abb | `実装状況`: `要改修` → `実装済み`。`概要` の末尾に「招待コードは `Random.secure()` で生成する（旧実装は連番になっていた）。テストのために `firestore` / `uid` をコンストラクタで差し込める」を追記 |
| FEAT-016 予定CRUD | https://app.notion.com/p/3b97e23227268107b2fdfaed5dcb9618 | `概要` の末尾に「テストのために `firestore` / `uid` をコンストラクタで差し込める」を追記 |
| FEAT-017 Gemini応答サービス | https://app.notion.com/p/3b97e2322726814a8b48e900130431bd | `実装状況`: `要改修` のまま（APIキーのサーバ移譲が未了）。`概要` の末尾に「応答のパースは `parseGeminiReply()` として `GenerativeModel` 非依存の純粋関数へ切り出し済み」を追記 |
| FEAT-031 単発リマインダー判定 | https://app.notion.com/p/3b97e2322726811f937bfbc0dc022942 | `実装状況`: `要改修` のまま（クエリ最適化とメンバー別 `reminded` が未了）。`実装ファイル` に `functions/src/reminder_logic.ts` を追記 |
| FEAT-032 繰り返しリマインダー判定 | https://app.notion.com/p/3b97e23227268127ba9eeb445ad54c14 | `実装状況`: `要改修` のまま。`実装ファイル` に `functions/src/reminder_logic.ts` を追記。`概要` に「2/29 の記念日を平年に評価すると3/1へ滑る不具合は修正済み（月末で頭打ち）」を追記 |
| FEAT-005 カレンダー選択表示 | https://app.notion.com/p/3b97e2322726814b896ee2e5a5c1752c | `実装状況`: `実装済み` のまま。ページ本文に TC-097 と同じ原因メモを追記 |

### 機能を1件追加

| プロパティ | 値 |
|---|---|
| 機能名 | CI（analyze / test の必須チェック） |
| 機能ID | FEAT-052 |
| レイヤ | インフラ・CI/CD |
| 実装状況 | 一部実装 |
| 概要 | PR で `flutter analyze` / `flutter test` と Cloud Functions の typecheck / test / build を実行する。**GitHub 側で必須チェックに設定する作業は未了**（Settings → Branches → main → Require status checks、リポジトリ管理者権限が必要） |
| 実装ファイル | .github/workflows/ci.yml |
| 関連要件 | REQ-027（主要導線が自動テストで守られている） |

---

## 5. 要件一覧のステータス更新

| 要件 | URL | 変更内容 |
|---|---|---|
| REQ-015 | https://app.notion.com/p/3b97e2322726818a871aea247a374a09 | `ステータス`: `実装中` → `実装済み`（1-1 参照） |
| REQ-027 主要導線が自動テストで守られている | https://app.notion.com/p/3b97e23227268170be6ac04b3f0101a8 | `ステータス`: `実装中` のまま。ページ本文の「現状の自動テストは3ファイルのみ」のリストを次に差し替える |

REQ-027 の本文に入れる現状:

> **着手済み（コミット `d9da4f1`）**
> - `functions/src/reminder_logic.test.ts` — リマインダー判定 17件（実行して全通過）
> - `test/services/gemini_reply_parser_test.dart` — AI応答パース（未実行）
> - `test/services/couple_service_test.dart` — ペアリング（未実行）
> - `test/services/event_service_test.dart` — 予定CRUD・期間クエリ（未実行）
> - `.github/workflows/ci.yml` — PR で analyze / test を実行
>
> **残っている領域**
> - Firestore セキュリティルールのテスト（`rules_test/` は README に記載があるが実在しない）
> - ウィジェットテスト（カレンダー描画・タブ切替時の状態保持）
> - Cloud Functions の Firestore 側（`reminded` の書き込み、通知設定の反映）
> - GitHub 側で CI を必須チェックに設定する（管理者権限が必要）

---

## 6. ハブページの更新

https://app.notion.com/p/3b97e232272681c0b0b5c1e46c6b3906

「AIMARU の現在地」の表の**技術的負債**の行を差し替える:

> 自動テストはリマインダー判定（Cloud Functions、17件・通過確認済み）、AI応答パース、
> ペアリング、予定CRUD まで整備済み。Firestore ルールとウィジェットテストは未着手。
> `sendReminders` が `collectionGroup` の全件走査でスケールしない点は未修正。

**弱み**の行から「招待コードが推測可能」に類する記述は無いので変更不要だが、
新設する REQ-034 は解決済みとして扱う。
