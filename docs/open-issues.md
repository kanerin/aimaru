# 残課題（最終更新: 2026-08-19 / 基準ブランチ `develop`）

このファイルは「今どこまで出来ていて、何が残っているか」を1枚で把握するためのもの。
2026-08-14にNotion連携の自動更新（`notion-audit`スキル）は廃止した。今後はPRの中で
このファイルを手動またはエージェントが都度更新する。

## 検証できていること

実際に実行して確認した事実だけを書く。

| 対象 | コマンド | 結果 |
|---|---|---|
| Cloud Functions（判定ロジック） | `cd functions && npm test` | **61件すべて通過**（ローカルで確認、CIでも要確認） |
| Cloud Functions（Firestore経路） | `cd functions && npm run test:integration` | **19件すべて通過**（エミュレータ上、ローカルで確認、CIでも要確認） |
| Cloud Functions の型 | `cd functions && npm run typecheck` | **通過**（テストコード込み） |
| セキュリティルール | `cd rules_test && npm test` | **確認中**（マージ後に再計測して更新） |
| Flutter 単体・ウィジェット | `flutter test` | **確認中**（マージ後に再計測して更新） |

テストの内訳:

```
test/services/gemini_reply_parser_test.dart      17   AI応答パース・失敗分類
test/services/gemini_service_test.dart           12   askGemini呼び出し(coupleId・contents)とエラー分類
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
test/widgets/pairing_preview_cards_test.dart      2   ペア未成立時の機能プレビューカードの表示・スクロール
test/services/anniversary_service_test.dart       3   複数記念日のCRUD
test/screens/anniversaries_screen_test.dart        4   記念日リスト画面のロード・エラー・並び順・空表示
test/widget_test.dart                             3   スモーク
integration_test/app_test.dart                    1   起動（実機必要・CIでは走らない）
functions/src/reminder_logic.test.ts             22   リマインダー判定・メンバー別送信済み管理
functions/src/trash_logic.test.ts                 4   ゴミ箱の保持期間判定
functions/src/reminders.integration.test.ts      10   Firestoreを読んで判定し書き戻す経路（ゴミ箱除外・先読み幅の絞り込み含む）
functions/src/trash.integration.test.ts           1   保持期限を過ぎた論理削除済み予定の完全削除
functions/src/gemini_logic.test.ts               35   askGeminiのレート制限・メンバー確認・Gemini APIレスポンス分岐
functions/src/ask_gemini.integration.test.ts      8   Firestoreを読んだメンバー確認・レート制限のトランザクション
rules_test/firestore.test.js                     確認中   Firestoreルールのメンバー境界（todos・expenses・questionAnswers・anniversaries・aiCallCount保護含む）
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

旧1（CIが必須チェックになっていない）・旧7（"Allow auto-merge"が無効）は、2026-08-18に
`gh api repos/kanerin/aimaru/rulesets` と `gh api repos/kanerin/aimaru --jq .allow_auto_merge`
で実地確認し、どちらも解決済み（Rulesetの必須チェック名は`ci.yml`のジョブ名と一致、
`allow_auto_merge: true`）と分かったため表から外した。

旧6（リリース署名鍵のSHA-1が未登録）も2026-08-18に検証した。Firebaseには元々SHA-1が2件
登録されており、うち1件（`551232a9...`）は`ANDROID_KEYSTORE_BASE64`（実際のリリース署名鍵）
から`keytool`で算出したフィンガープリントと完全一致した。**リリース鍵のSHA-1は既に登録済み**
ということになる。検証は実機ではなく、PRの`pull_request`トリガーを使った使い捨てワークフロー
（マージはせずクローズ）で、鍵の中身ではなくフィンガープリントだけをログに出す形で行った
（`android/app/*.keystore`の中身は読んでいない）。それでもテスター端末でGoogleログインが
失敗する場合は、SHA-1未登録ではなく別の原因（配布中のAPKに同梱された`google-services.json`が
このフィンガープリント登録より古い、OAuth同意画面の設定、等）を疑うこと。実機での再現確認は
まだ行っていないので、失敗が実際に起きているかどうかも含めて要確認。

課題2（Gemini APIキーがビルド成果物に埋まる）・課題14（AI呼び出しのレート制限が無い）は
まとめて着手した（本PR）。Cloud Functionsに`askGemini`（`onCall`）を新設し、キーはSecret
Manager（`firebase functions:secrets:set GEMINI_API_KEY`）に置くようにした。`lib/services/gemini_service.dart`
は`FirebaseFunctions.instance.httpsCallable`を呼ぶだけになり、`String.fromEnvironment('GEMINI_API_KEY')`
はもう読まない。呼び出しは認証済み・該当カップルのメンバーであることを検証し（非メンバーからの
呼び出しを拒否）、1日あたりの呼び出し回数を`users/{uid}`の`aiCallDate`/`aiCallCount`で制限する
（`AI_DAILY_CALL_LIMIT`、`functions/src/gemini_logic.ts`に定数化、既定50回/日）。このカウント
フィールドは`firestore.rules`でクライアントからの直接書き換えを禁止した（許してしまうと自分で
0にリセットしてレート制限を無効化できてしまうため）。ビルドの`--dart-define=GEMINI_API_KEY`は
Dart側がもう読まないため実質無害だが、`release-stg.yml`/`release.yml`/`scripts/*.sh`からの削除
（元のフェーズ4）はまだ行っていない。`parseGeminiReply`・応答スキーマ・`describeGeminiFailure`は
一切変更していない（`test/services/gemini_reply_parser_test.dart`の17件は無改変のまま通過）。

| # | 課題 | 対応する要件 / ケース | なぜ残っているか |
|---|---|---|---|
| 3 | **予定ごとの共有範囲が選べない** | REQ-022 / FEAT-041 | 全予定がペア双方に見える。モデル・Firestore ルール・通知の3経路に影響する。フェーズ1（下記）着手済み |
| 4 | **ペア解消・退会・データエクスポートの導線が無い** | REQ-023 / REQ-024 / FEAT-039 / FEAT-040 | 関係の終わりを迎えるユーザーを扱えていない。個人情報の削除請求への対応義務もある |
| 5 | **`applicationId` が `com.example.aimaru` のまま** | REQ-029 / FEAT-036 | Play Store で `com.example` は避けるべき。変更すると Firebase のアプリ再登録と `google-services.json` 再取得が要る |

課題3（予定ごとの共有範囲）はフェーズ1として、`AimaruEvent`に`visibility`（`shared`/既定 or `private`）
フィールドだけを追加した（本PR、`lib/models/models.dart`）。既存ドキュメントに無ければ`shared`へ
フォールバックする。UIでの切り替え・Firestoreルールでの読み取り制限は**まだ実装していない**
（全予定が引き続きペア双方に見える）。

**フェーズ2が着手できない理由**: `private`を実際に隠すには、Firestoreのセキュリティルールが
`resource.data`（このケースでは`visibility`・`createdBy`）を見て判定する必要があるが、`list`
クエリ（`watchMonthEvents`等、カレンダーの主要な取得経路はすべてこれ）に対する読み取りルールは
「クエリの`where`句だけから安全性が判定できる」ことが必須で、`visibility`を`where`に含めない限り
クエリ全体が拒否される。つまり`visibility`で絞り込む`where`句を全ての取得クエリに追加する必要が
あり、これは新しい複合索引（`firestore.indexes.json`）を要求する。ところが索引の本番デプロイは
課題8と同じ理由（`FIREBASE_SERVICE_ACCOUNT_KEY`のIAM未付与）で失敗し続けており、この状態で
カレンダーの主要クエリに新しい索引前提の絞り込みを入れると、IAMが解決するまでの間**本番の
全ユーザーでカレンダー画面がFAILED_PRECONDITIONになる**（課題8の対象はバックグラウンドの
リマインダー処理だけだったが、こちらは主要画面そのものが壊れるため影響がより大きい）。
「人間にしかできない作業」のIAMロール付与が終わってから着手すること。

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

課題8（`sendReminders` の `collectionGroup` 全件走査）はフェーズ1に着手した（本PR）。
まず `release-stg.yml` に `firebase deploy --only firestore:indexes` のステップを追加し
（rulesと同じ手順で並べた）、`processOneTimeEvents`（単発予定）のクエリに
`reminded == false` に加えて `date <= 先読み幅` の範囲条件を足した。先読み幅は
`QUERY_LOOKAHEAD_MS`（`functions/src/reminder_logic.ts`、3日）で、設定できる
リマインダーの最大値（`lib/screens/settings_screen.dart` の `_reminderOptions`、
現状1日前）より長く取ってある。これで、何ヶ月も先の一回限りの予定まで毎回
ユーザー数分読み込む問題は解消した。複合索引 `firestore.indexes.json` の
`indexes`（`reminded` ASC, `date` ASC, `queryScope: COLLECTION_GROUP`）を追加した。

**残っている範囲（フェーズ2）**: `processRecurringEvents`（毎年繰り返す予定）は今回
narrowingしていない。`date` フィールドは予定の**作成時点の年**を持つため、
「今年の発生日」を求める `nextOccurrence`（月日だけを見る）とは単純な範囲比較が
噛み合わず、素朴な `date` 範囲条件では絞り込めない。narrowingするなら
「次の発生日」を別フィールドとして保持するスキーマ変更が要りそうで、今回のPRの
範囲を超えるため見送った。また、索引デプロイ自体は課題2隣接のIAM未付与
（rulesと同じ原因）により本番では引き続き失敗する想定で、`continue-on-error: true`
のまま可視化のみ行っている。IAMロールが付与されたら自動的に効くようになる。

| # | 課題 | 対応する要件 / ケース | 補足 |
|---|---|---|---|
| 13 | **iOS が未整備** | REQ-030 / FEAT-049 | 片方が使えないとカップルアプリは価値がゼロになる |

設定画面に「次に会う日」カード（`NextMeetingCard`）を追加した（本PR）。遠距離・多忙で
頻繁に会えないカップル向けのトレンド（次に会える日までのカウントダウン）に対応する、
記念日カードと対になる機能。既存の`anniversary`と同じ形（`couples/{coupleId}`の1フィールド）
で`nextMeetingDate`を持たせているため、新しいFirestoreコレクションやルール変更は増やして
いない。過ぎた日付は「予定の日を過ぎています」と表示するだけで自動クリアはしない
（ユーザーが明示的にクリア・更新するまで直近の予定として残す）。

設定画面の「記念日」（付き合い始めた日、`AnniversaryCard`）は1件しか持てなかったが、
「記念日リスト」（`AnniversariesScreen` / `AnniversaryService`、`couples/{coupleId}/anniversaries`）
を追加した（本PR）。プロポーズ・入籍・初デートなど、付き合い始めた日以外にも複数の記念日を
登録し、次の周年までの日数でカウントダウン表示する。TimeTreeにはこの概念自体が無く、
サービス終了したPairyの移行先として比較されるBetween・Twinest等が持つ複数記念日管理に
近い差別化要素（2026年8月時点の競合調査）。表示ロジックは既存の`lib/utils/anniversary_calculator.dart`
の`summarizeAnniversary`をそのまま再利用しており、新しい計算式は増やしていない。
Firestoreのクエリは絞り込み無しの単純な購読（`snapshots()`）で、並び替え（次の記念日が近い順）は
クライアント側で行うため、課題8・課題3フェーズ2で問題になった新しい複合索引は要らない。

旧17（ペア未成立時の体験プレビュー）は、ペアリング画面（PairingScreen）に招待コード/QRの
上に「ペアになるとできること」カード（`lib/widgets/pairing_preview_cards.dart`）を追加し、
実装済みのため表から外した（本PR）。招待コードだけが表示される待機中の画面は離脱されやすく、
Pairyからの移行検討ユーザーは他アプリと比較検討中であることが多いため、機能を先に見せて
招待を最後まで送ってもらう／相手に参加してもらう後押しにする。静的なコンテンツのみで
Firestore・Cloud Functionsへの新しい依存は追加していない。

### P2 — 余力があれば

| # | 課題 | 対応する要件 |
|---|---|---|
| 18 | 収益モデル | REQ-032 |

## 人間にしかできない作業

エージェントが着手しても完了できないもの。ここが詰まると後続が止まる。

- [x] ~~CI を必須チェックに設定~~（Settings → Branches → develop）— 2026-08-18確認、設定済み
- [x] ~~"Allow auto-merge" を有効化~~（Settings → General → Pull Requests）— 2026-08-18確認、有効
- [x] ~~リリース署名鍵の SHA-1 を Firebase Console に登録~~ — 2026-08-18確認、既に登録済み（上記参照）
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
ベースの構成へ移行した。その後 `propose-feature.yml` は「調査してIssue起票のみ」から
「実装してPRを作りCI成功のみを条件にauto-mergeする」方式へ変わり（2026-08-14）、
その後既存課題の消化に絞った `reduce-debt.yml` を朝枠として追加した
（下記の一覧は現状に更新済み）。`test-report.yml` / `backmerge.yml` / `claude-mention.yml` は
引き続き、月間コストを抑えるため「何か対応が要る時」だけClaudeを呼ぶ設計のまま
（テストが全部greenの週やコンフリクトが無いリリースでは、Claude起動コストは実質ゼロ）。

```
reduce-debt.yml       1日1回cron（朝）   docs/open-issues.mdのP0/P1のうちコード変更だけで完結するものを1つ実装 → develop へPR → CI成功でauto-merge
propose-feature.yml   1日1回cron（夜）   市場動向調査 → 改善を1つ実装 → develop へPR → CI成功でauto-merge
test-report.yml       週2-3回cron        テスト実行（プレーンshell）→ 失敗時のみClaudeが分析してIssueへ
backmerge.yml          release-prd push契機  戻しマージPR自動作成 → コンフリクト時のみClaudeが分析コメント
claude-mention.yml     @claudeメンション（書き込み権限者限定） → 良い提案Issueを人間が選んで実装依頼
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
