# 残課題（最終更新: 2026-08-18 / 基準ブランチ `develop`）

このファイルは「今どこまで出来ていて、何が残っているか」を1枚で把握するためのもの。
2026-08-14にNotion連携の自動更新（`notion-audit`スキル）は廃止した。今後はPRの中で
このファイルを手動またはエージェントが都度更新する。

## 検証できていること

実際に実行して確認した事実だけを書く。

| 対象 | コマンド | 結果 |
|---|---|---|
| Cloud Functions（判定ロジック） | `cd functions && npm test` | **26件すべて通過** |
| Cloud Functions（Firestore経路） | `cd functions && npm run test:integration` | **10件すべて通過**（エミュレータ上） |
| Cloud Functions の型 | `cd functions && npm run typecheck` | **通過**（テストコード込み） |
| セキュリティルール | `cd rules_test && npm test` | **45件すべて通過**（エミュレータ上、CIで確認） |
| Flutter 単体・ウィジェット | `flutter test` | **229件すべて通過**（CIで確認） |

テストの内訳:

```
test/services/gemini_reply_parser_test.dart      17   AI応答パース・失敗分類
test/utils/free_time_finder_test.dart            15   2人の空き時間検出・提案
test/widgets/event_datetime_fields_test.dart     15   日時入力ウィジェット
test/services/event_service_test.dart            18   予定CRUD・終日・期間クエリ・ゴミ箱
test/services/couple_service_test.dart           13   ペアリング・招待コード
test/utils/japan_holidays_test.dart              13   祝日計算
test/utils/recurring_events_test.dart            12   毎年繰り返しの展開
test/services/google_calendar_service_test.dart   8   Googleとの日時変換
test/models/aimaru_event_test.dart                7   モデルの変換
test/services/todo_service_test.dart              5   共有TODOのCRUD・並び順
test/services/expense_service_test.dart           4   割り勘・立て替え記録・精算記録のCRUD・並び順
test/services/theme_controller_test.dart          4   テーマ
test/utils/expense_balance_test.dart              8   割り勘の精算額計算・精算記録の相殺
test/screens/todos_screen_test.dart               3   やりたいことリストのロード・エラー・表示状態
test/screens/trash_screen_test.dart               4   ゴミ箱画面のロード・エラー・表示状態
test/screens/expenses_screen_test.dart            7   割り勘画面のロード・エラー・表示状態・精算額表示・精算する操作
test/utils/on_this_day_finder_test.dart           5   n年前の今日の振り返り抽出
test/screens/memories_screen_test.dart            5   思い出画面のロード・エラー・振り返り表示
test/utils/daily_question_picker_test.dart        3   デイリー質問の決定的な選択
test/services/question_service_test.dart          4   デイリー質問への回答のCRUD
test/screens/questions_screen_test.dart           5   ふたりの質問画面のロード・エラー・回答状態
test/widget_test.dart                             3   スモーク
integration_test/app_test.dart                    1   起動（実機必要・CIでは走らない）
functions/src/reminder_logic.test.ts             22   リマインダー判定・メンバー別送信済み管理
functions/src/trash_logic.test.ts                 4   ゴミ箱の保持期間判定
functions/src/reminders.integration.test.ts       9   Firestoreを読んで判定し書き戻す経路（ゴミ箱除外含む）
functions/src/trash.integration.test.ts           1   保持期限を過ぎた論理削除済み予定の完全削除
rules_test/firestore.test.js                     39   Firestoreルールのメンバー境界（todos・expenses・questionAnswers含む）
rules_test/storage.test.js                        6   Storageルールの画像アクセス制御
```

CI は3ジョブに分けている。落ちた場所から原因が一目で分かるようにするため。

| ジョブ | 内容 |
|---|---|
| Flutter | `analyze` / `test --coverage` |
| Cloud Functions | 型 / 単体 / 結合（エミュレータ）/ ビルド |
| Security rules | Firestore・Storage ルール（エミュレータ） |

`release-stg` へのマージでも同じ3系統を通してから配布する。ルールが緩んだ状態で
テスターに配ると、その端末から実データを触られる余地が残るため。

## 残っている課題

優先度は Notion の要件に準拠。**着手するときは必ず Notion 側の該当要件を正として読むこと。**

### P0 — 着手すべきもの

| # | 課題 | 対応する要件 / ケース | なぜ残っているか |
|---|---|---|---|
| 1 | **CI が GitHub の必須チェックになっていない** | REQ-027 / FEAT-052 / TC-094 | Settings → Branches → develop → Require status checks の設定が要る。**リポジトリ管理者権限が必要でエージェントからは実施できない** |
| 2 | **Gemini API キーがビルド成果物に埋まる** | REQ-026 / FEAT-046 / TC-087 | `--dart-define` はソースへの直書きを防ぐだけで、APK からは抽出できる。Cloud Functions の `onCall` へ移して Secret Manager に置く必要がある |
| 3 | **予定ごとの共有範囲が選べない** | REQ-022 / FEAT-041 | 全予定がペア双方に見える。モデル・Firestore ルール・通知の3経路に影響する |
| 4 | **ペア解消・退会・データエクスポートの導線が無い** | REQ-023 / REQ-024 / FEAT-039 / FEAT-040 | 関係の終わりを迎えるユーザーを扱えていない。個人情報の削除請求への対応義務もある |
| 5 | **`applicationId` が `com.example.aimaru` のまま** | REQ-029 / FEAT-036 | Play Store で `com.example` は避けるべき。変更すると Firebase のアプリ再登録と `google-services.json` 再取得が要る |
| 6 | **リリース署名鍵の SHA-1 が Firebase に未登録** | REQ-029 / TC-096 | リリースビルドで Google ログインが失敗する |
| 7 | **リポジトリで "Allow auto-merge" が有効になっていない** | CLAUDE.md「自動化の構成」 | `gh pr merge --auto` が `GraphQL: Auto merge is not allowed for this repository` で失敗する（本PR #21 で実際に発生）。CIが必須チェックとして設定されていても、auto-mergeが有効でなければ`propose-feature.yml`が作るPRは無人でマージされず、`develop`へも`release-stg`へも昇格しない。**Settings → General → Pull Requests → Allow auto-merge の有効化が要り、リポジトリ管理者権限が必要でエージェントからは実施できない**。PR #16・#20・#21 がCI green・コンフリクト無し（`mergeStateStatus: BLOCKED`）のまま止まっている実例 |

### P1 — 次に効くもの

旧9〜12（画像から予定を読み取る／2人の空き時間検出／共有TODO／他社アプリからの移行手段）は
それぞれ #9・free_time_finder・#11・#8 で実装済みのため表から外した。棚卸しのたびに
「新発見」として蒸し返さないよう、ここに記録しておく。

割り勘・立て替え（ExpensesScreen / ExpenseService、`couples/{coupleId}/expenses`）を追加した。
TimeTreeにはカレンダー機能しか無く、費用共有は他のカップル/夫婦アプリで比較される
要素のため差別化になる。2人のカップル前提で、支払い合計の差額の半分を精算額として自動計算する
（`lib/utils/expense_balance.dart`）。

割り勘画面に「精算する」操作を追加した（本PR）。Splitwiseなど専業の割り勘アプリは精算を記録して
残高をリセットできるが、従来のAIMARUは未精算額を都度計算するだけで記録する手段が無く、記録が
増え続けると見通しが悪くなっていた。精算は`ExpenseItem`に`isSettlement`フラグを立てて既存の
`expenses`コレクションにそのまま記録する形にし、新しいFirestoreコレクションやルール変更は
増やしていない。精算1件はpaidBy側の寄与を2倍で計算することで、以降の`calculateBalance`が
0円に戻る（`lib/utils/expense_balance.dart`）。履歴は削除せず「精算」ラベルで一覧に残す。

旧16（去年の今日の振り返り）は、思い出画面（MemoriesScreen）に「n年前の今日」セクションとして
実装済みのため表から外した（本PR）。サービス終了したPairyが持っていた「思い出を振り返る」体験の
穴埋め。新しいFirestoreクエリやCloud Functionsは追加せず、既存の予定購読ストリームから
クライアント側で抽出するだけにしてある（`lib/utils/on_this_day_finder.dart`）。課題8で指摘した
`collectionGroup` の新規索引リスクを避けるため、あえてプッシュ通知化はしていない。

「ふたりの質問」（QuestionsScreen / QuestionService、`couples/{coupleId}/questionAnswers`）を追加した
（本PR）。TimeTreeはカレンダー機能主体で「お互いを知る」体験を持たず、サービス終了した
Pairyの移行先として比較されるSumOne・Twinestが持つ質問カード機能に近い差別化要素。日付ごとに
固定の質問を1つ、乱数やサーバー状態を使わず決定的に選び（`lib/utils/daily_question_picker.dart`）、
2人とも回答するまでは相手の回答を伏せることで、相手の回答に引っ張られない素直な回答を引き出す。
回答は`request.resource.data.uid`で本人の分のみ書き込みを許可し、更新・削除は許可していない
（相手の回答を見た後に自分の回答を書き換える抜け道を防ぐため）。

| # | 課題 | 対応する要件 / ケース | 補足 |
|---|---|---|---|
| 8 | **`sendReminders` が `collectionGroup` の全件走査** | REQ-028 / FEAT-048 | `index.ts` の `processOneTimeEvents` / `processRecurringEvents`。ユーザー数に対して課金と実行時間が線形以上に伸びる。**注意**: `reminded`/`recurring` の等価条件を `date` の範囲条件に置き換えて絞り込む方向で直そうとすると、`collectionGroup` クエリは単一フィールド索引でも `queryScope: COLLECTION_GROUP` の明示的な索引（`firestore.indexes.json` の `fieldOverrides`）が要る。索引はルールと違い `release-stg.yml` がデプロイする経路が無い（`firebase deploy --only firestore:indexes` を回す仕組みが存在しない）ため、素朴に直すとエミュレータでは通って本番でクエリが失敗する状態になる。索引デプロイの経路を先に用意すること |
| 13 | **iOS が未整備** | REQ-030 / FEAT-049 | 片方が使えないとカップルアプリは価値がゼロになる |
| 14 | **AI 呼び出しのレート制限が無い** | REQ-018 / FEAT-046 | 2番（APIキー）と同時に実施するのが合理的 |

### P2 — 余力があれば

| # | 課題 | 対応する要件 |
|---|---|---|
| 17 | ペア未成立時の体験プレビュー | REQ-033 / FEAT-051 |
| 18 | 収益モデル | REQ-032 |

## 人間にしかできない作業

エージェントが着手しても完了できないもの。ここが詰まると後続が止まる。

- [ ] **CI を必須チェックに設定**（Settings → Branches → develop）— 課題1
- [ ] **"Allow auto-merge" を有効化**（Settings → General → Pull Requests）— 課題7。これが無いと`propose-feature.yml`が作るPRが無人でマージされない（PR #16・#20・#21 が滞留中）
- [ ] リリース署名鍵の SHA-1 を Firebase Console に登録 — 課題6
- [ ] Play Console でデベロッパーアカウント作成、手動で1度 AAB をアップロード — REQ-029
- [ ] `PLAY_STORE_SERVICE_ACCOUNT_JSON` シークレットの登録 — REQ-029
- [ ] Apple Developer 登録、APNs 認証鍵の作成 — 課題13
- [ ] OAuth 同意画面のテストユーザー登録（上限100人）または審査申請
- [ ] `android/app/release.keystore` のバックアップ（**紛失するとアプリを二度と更新できない**）
- [ ] `FIREBASE_SERVICE_ACCOUNT_KEY`のサービスアカウントにFirestoreルールデプロイ用のIAMロール（例: Firebase Rules Admin）をGCPコンソールで付与 — 未付与のため`release-stg.yml`の`Deploy Firestore rules`が403で失敗し続けている（`continue-on-error: true`でビルド・配布はブロックしていない）。それまでは`firestore.rules`変更時に`firebase deploy --only firestore:rules --project aimaru-7eb2e`をローカルから手動実行すること

## 既知だが直さない判断をしたもの

毎回の棚卸しで「新発見」として蒸し返さないよう記録しておく。

- **`couples` の読み取りルールが緩い**（認証済みなら他人のペアの `memberIds` / `anniversary` が読める）— 招待コード検索を成立させるための意図的な妥協。締めるなら `inviteCode` を別コレクションへ分離する設計変更が要る。TC-072 に記録済みで、`rules_test/firestore.test.js` の【既知】テストが現状を固定している（直したらそのテストが落ちて気づける）
- **「国民の休日」（祝日に挟まれた平日）が未対応** — 発生頻度が低いため
- **全面 E2E 暗号化は採用しない** — AI 機能と両立しないため。COUPPLY が訴求している点だが追従しない判断

## 自動化の構成

2026-08-14 に、実際には呼び出されていなかったNotion連携の`.claude/skills/`（scheduled-run /
notion-audit / notion-implement / market-brief / pr-review）を廃止し、GitHub Actions +
`claude-code-action`（`CLAUDE_CODE_OAUTH_TOKEN`認証、Claude Pro/Maxプランの利用枠を使う）
ベースの構成へ移行した。月間コストを抑えるため、Claudeを呼ぶのは「何か対応が要る時」だけに
絞っている（テストが全部greenの週やコンフリクトが無いリリースでは、Claude起動コストは
実質ゼロ）。

```
propose-feature.yml  週1回cron    コードベース分析 → Issue起票のみ（PR化しない）
test-report.yml      週2-3回cron  テスト実行（プレーンshell）→ 失敗時のみClaudeが分析してIssueへ
backmerge.yml         release-prd push契機  戻しマージPR自動作成 → コンフリクト時のみClaudeが分析コメント
claude-mention.yml    @claudeメンション（書き込み権限者限定） → 良い提案Issueを人間が選んで実装依頼
```

詳細は`CLAUDE.md`の「自動化の構成」、各ワークフローファイル、`.claude/commands/`を参照。

人間が能動的にやることは、良い提案Issueへの`@claude`での実装依頼、コンフリクト発生時の
最終判断、`release-stg` → `release-prd`への昇格（本番公開）、権限が要る作業。

## ブランチ運用

2026-08-12 に `main` / `release` を廃止し、3ブランチモデルへ移行した。

```
作業ブランチ → develop → release-stg → release-prd
```

| ブランチ | 役割 | 自動で走るもの |
|---|---|---|
| `develop` | 開発の起点。ここからブランチを切り、ここへマージする（デフォルトブランチ） | PR / push で CI（analyze・test・Cloud Functions の検査） |
| `release-stg` | テスター配布 | analyze / test を通してから App Distribution へ配布 |
| `release-prd` | 本番 | Play Store（internal）へアップロード。Play Console 側の準備待ち |

エージェントが作業するときは `develop` から切って `develop` へ PR を出す。
定期実行エージェント（backmerge等）は `develop` → `release-stg` の昇格までは自動で行ってよいが、
`release-stg` → `release-prd`（本番公開）は必ず人間が判断する。
