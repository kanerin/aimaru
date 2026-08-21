# 残課題（最終更新: 2026-08-20 / 基準ブランチ `develop`）

このファイルは「今どこまで出来ていて、何が残っているか」を1枚で把握するためのもの。
2026-08-14にNotion連携の自動更新（`notion-audit`スキル）は廃止した。今後はPRの中で
このファイルを手動またはエージェントが都度更新する。

## 検証できていること

実際に実行して確認した事実だけを書く。

| 対象 | コマンド | 結果 |
|---|---|---|
| Cloud Functions（判定ロジック） | `cd functions && npm test` | **87件すべて通過**（ローカルで確認、CIでも要確認） |
| Cloud Functions（Firestore・Storage経路） | `cd functions && npm run test:integration` | **41件すべて通過**（ローカルで確認。下記「既知の環境上の制約」参照——2026-08-20時点でこのエージェント実行環境はNode 22系になっており、制約は解消済み） |
| Cloud Functions の型 | `cd functions && npm run typecheck` | **通過**（テストコード込み） |
| セキュリティルール | `cd rules_test && npm test` | **58件すべて通過**（ローカルで確認。同上の理由で制約は解消済み） |
| Flutter 単体・ウィジェット | `flutter test` | **335件すべて通過**（ローカルで確認、CIでも要確認） |

テストの内訳:

```
test/services/gemini_reply_parser_test.dart      17   AI応答パース・失敗分類
test/services/gemini_service_test.dart           12   askGemini呼び出し(coupleId・contents)とエラー分類
test/utils/free_time_finder_test.dart            15   2人の空き時間検出・提案
test/widgets/event_datetime_fields_test.dart     15   日時入力ウィジェット
test/services/event_service_test.dart            18   予定CRUD・終日・期間クエリ・ゴミ箱
test/services/couple_service_test.dart           17   ペアリング・招待コード・ペアの解消（dissolveCouple呼び出し）
test/services/data_export_service_test.dart       7   データエクスポート(予定・チャット・TODO等のJSON化)
test/utils/japan_holidays_test.dart              13   祝日計算
test/utils/recurring_events_test.dart            12   毎年繰り返しの展開
test/services/google_calendar_service_test.dart   8   Googleとの日時変換
test/models/aimaru_event_test.dart                7   モデルの変換
test/services/todo_service_test.dart              5   共有TODOのCRUD・並び順
test/services/theme_controller_test.dart          4   テーマ
test/screens/todos_screen_test.dart               6   やりたいことリストのロード・エラー・表示状態・カレンダー登録への遷移・削除・完了切替
test/screens/trash_screen_test.dart               4   ゴミ箱画面のロード・エラー・表示状態
test/utils/daily_question_picker_test.dart        3   デイリー質問の決定的な選択
test/services/question_service_test.dart          4   デイリー質問への回答のCRUD
test/screens/questions_screen_test.dart           5   ふたりの質問画面のロード・エラー・回答状態
test/widgets/pairing_preview_cards_test.dart      2   ペア未成立時の機能プレビューカードの表示・スクロール
test/services/anniversary_service_test.dart       3   複数記念日のCRUD
test/screens/anniversary_hub_screen_test.dart      6   記念日タブ（次に会う日・記念日・記念日リスト）のロード・エラー・並び順・空表示
test/widget_test.dart                             3   スモーク
integration_test/app_test.dart                    1   起動（実機必要・CIでは走らない）
functions/src/reminder_logic.test.ts             22   リマインダー判定・メンバー別送信済み管理
functions/src/trash_logic.test.ts                 4   ゴミ箱の保持期間判定
functions/src/reminders.integration.test.ts      12   Firestoreを読んで判定し書き戻す経路（ゴミ箱除外・先読み幅の絞り込み・繰り返し予定のnextOccurrenceMs書き戻し含む）
functions/src/trash.integration.test.ts           1   保持期限を過ぎた論理削除済み予定の完全削除
functions/src/gemini_logic.test.ts               35   askGeminiのレート制限・メンバー確認・Gemini APIレスポンス分岐
functions/src/ask_gemini.integration.test.ts      8   Firestoreを読んだメンバー確認・レート制限のトランザクション
functions/src/bug_report_logic.test.ts           21   バグ報告フォームの入力検証・分類プロンプト組み立て・Gemini応答の厳格パース
functions/src/submit_bug_report.integration.test.ts 7 バグ報告専用レート制限（askGeminiと独立）・受理された報告の書き込み
functions/src/dissolve_couple.integration.test.ts 8   カップル解消時のFirestore再帰削除・Storage削除・メンバー確認
test/services/bug_report_service_test.dart       15   バグ報告送信サービス（入力検証・応答解釈・エラー分類・自分の報告一覧watchMyReports）
test/screens/bug_report_screen_test.dart         10   バグ報告フォーム画面（受理・拒否・入力検証・送信中表示・失敗時表示・送った報告一覧の表示/エラー）
rules_test/firestore.test.js                     58   Firestoreルールのメンバー境界（todos・questionAnswers・anniversaries・aiCallCount/reportCallMonth保護・bugReports自分の報告のみ読める・ペアの解消含む）
rules_test/storage.test.js                        6   Storageルールの画像アクセス制御
```

CI は5ジョブに分けている。落ちた場所から原因が一目で分かるようにするため。

| ジョブ | 内容 |
|---|---|
| Secret scan | gitleaksによるシークレット漏洩チェック（2026-08-21追加） |
| Flutter | `analyze` / フォーマットチェック（可視化のみ） / `test --coverage` |
| Cloud Functions | 依存関係監査（high/critical） / 型 / 単体 / 結合（エミュレータ）/ ビルド |
| Security rules | 依存関係監査（high/critical） / Firestore・Storage ルール（エミュレータ） |
| Integration test | Androidエミュレータ上の実機結合テスト |

`release-stg` へのマージでも同じ3系統を通してから配布する。ルールが緩んだ状態で
テスターに配ると、その端末から実データを触られる余地が残るため。

**既知の環境上の制約 → 2026-08-20に解消済み**: 以前はローカルのエージェント実行環境が
Node 20系で、`rules_test`・`functions`の`test:integration`はどちらも`firebase-tools`
経由で`firebase emulators:exec`を呼ぶが、`firebase-tools`が依存する
`universal-analytics`がESM専用になった`uuid`パッケージを`require()`しており、
Node 20では`ERR_REQUIRE_ESM`で起動時に落ちていた（両パッケージともpackage.jsonの
`engines`はNode 22指定）。2026-08-20時点でこのエージェント実行環境がNode 22系
（`node -v` で `v22.23.2`）になっていることを確認し、`cd functions && npm run
test:integration`・`cd rules_test && npm test` とも実際にローカルで実行して
全件通過することを確認した。以後はCIだけでなくローカルでもこの2系統を実行して
確認できる。

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

課題4（ペア解消・退会・データエクスポートの導線が無い）は実装した（本PR）。
設定画面に3つの導線を追加した。
- **ペアを解消する**（`CoupleService.dissolveCouple` → Cloud Functionsの`dissolveCouple`）:
  共有してきたデータ（予定・チャット・写真・TODO・ふたりの質問への回答）を**両方のぶん
  まとめて完全に削除する**。当初は「自分だけ抜けて相手のデータは残す」設計だったが、レビューで
  「良くない」と指摘を受け、解消＝共有の終わりとして両者ともペア無しの状態に戻す仕様へ変更した。
  `questionAnswers`はクライアントからは削除できない設計（`firestore.rules`に`allow delete`が無い。
  相手の回答を見た後に自分の回答を書き換える抜け道を防ぐため）のため、複数コレクションにまたがる
  削除はCloud Functions（Admin SDK経由）に寄せている。`couples/{coupleId}`とその配下は
  `db.recursiveDelete()`でまとめて削除し、Storageの写真は`bucket.deleteFiles({prefix})`で削除する。
- **アカウントを削除する**（`AuthService.deleteAccount`）: ペアを組んでいれば上と同じ`dissolveCouple`
  を先に呼ぶ（パートナー側のデータも含めて完全に削除される）うえで、Firebase Authのアカウントと
  `users/{uid}`の自分のプロフィールを削除する。`requires-recent-login`（サインインから時間が
  経っている場合の保護）はGoogle再ログインを挟んで1回だけ再試行する。
- **データをエクスポート**（`DataExportService`）: カップルの予定・思い出（写真付きの予定）・
  チャット・やりたいことリスト・ふたりの質問への回答をJSONにまとめ、`share_plus`の
  共有シートで書き出す。ゴミ箱（論理削除済み）の予定は対象外。「ペアを解消する」「アカウントを
  削除する」のどちらも実行前にこのエクスポートを案内している。

相手側の端末で無限ローディングやクラッシュにならないことを確認した:
`memberIds`が1人になった後にアクセスする既存コード（`calendar_screen.dart`の`_loadMembers`、
`couple_service.dart`の`getPartnerName`、`questions_screen.dart`のパートナー回答表示）は、
いずれも既に「相手がいない」ケースを安全に扱っていた（新規の不具合は見つからなかった）。

破壊的な変更のため当初は他のPRと違いauto-mergeせず人間のレビューを必須にしていたが、
2026-08-20にユーザー本人がこのPRを確認した上でauto-mergeを有効化した。

| # | 課題 | 対応する要件 / ケース | なぜ残っているか |
|---|---|---|---|
| 3 | **予定ごとの共有範囲が選べない** | REQ-022 / FEAT-041 | 全予定がペア双方に見える。モデル・Firestore ルール・通知の3経路に影響する。フェーズ1（下記）着手済み |
| 5 | **`applicationId` が `com.example.aimaru` のまま** | REQ-029 / FEAT-036 | Play Store で `com.example` は避けるべき。変更すると Firebase のアプリ再登録と `google-services.json` 再取得が要る |

課題3（予定ごとの共有範囲）はフェーズ1として、`AimaruEvent`に`visibility`（`shared`/既定 or `private`）
フィールドだけを追加した（本PR、`lib/models/models.dart`）。既存ドキュメントに無ければ`shared`へ
フォールバックする。UIでの切り替え・Firestoreルールでの読み取り制限は**まだ実装していない**
（全予定が引き続きペア双方に見える）。

**フェーズ2の注意点**: `private`を実際に隠すには、Firestoreのセキュリティルールが
`resource.data`（このケースでは`visibility`・`createdBy`）を見て判定する必要があるが、`list`
クエリ（`watchMonthEvents`等、カレンダーの主要な取得経路はすべてこれ）に対する読み取りルールは
「クエリの`where`句だけから安全性が判定できる」ことが必須で、`visibility`を`where`に含めない限り
クエリ全体が拒否される。つまり`visibility`で絞り込む`where`句を全ての取得クエリに追加する必要が
あり、これは新しい複合索引（`firestore.indexes.json`）を要求する。索引・ルールの自動デプロイは
`FIREBASE_SERVICE_ACCOUNT_KEY`のIAM未付与により`release-stg.yml`からは引き続き失敗するが
（2026-08-19時点も未解決）、**リポジトリオーナーのアカウントでログインしたFirebase CLIからは
手動デプロイができる**（2026-08-19、`firebase deploy --only firestore:rules,firestore:indexes
--project aimaru-7eb2e`で実際に本番反映できることを確認した）。フェーズ2に着手する場合は、
コード変更とあわせて新しい索引の手動デプロイを忘れずに行うこと（自動実装エージェント
`reduce-debt.yml`/`propose-feature.yml`はこの手動デプロイ権限を持たないため、この課題に
自動着手させるのは避け、人間が同席するセッションで対応すること）。

### P1 — 次に効くもの

旧9〜12（画像から予定を読み取る／2人の空き時間検出／共有TODO／他社アプリからの移行手段）は
それぞれ #9・free_time_finder・#11・#8 で実装済みのため表から外した。棚卸しのたびに
「新発見」として蒸し返さないよう、ここに記録しておく。

旧: 割り勘・立て替え（ExpensesScreen / ExpenseService、`couples/{coupleId}/expenses`）を
追加していたが、2026-08-19にユーザーの判断で機能ごと削除した。画面・サービス・
`ExpenseItem`モデル・`firestore.rules`の`expenses`ルール・対応するテストをすべて削除している。
既存のFirestore上の`expenses`データがもし残っていても、ルール削除によりクライアントからは
今後読み書きできない（データ自体の削除は行っていない）。

旧16（去年の今日の振り返り）は、思い出画面（MemoriesScreen）に「n年前の今日」セクションとして
実装していたが、思い出機能自体を2026-08-19にユーザーの判断でメニューごと削除した（本PR）。
`lib/screens/memories_screen.dart`・`lib/utils/on_this_day_finder.dart`とそれぞれのテスト、
`lib/main.dart`のボトムナビ5番目のタブを削除している。カレンダー・AI・チャット・
やりたいことリストの4タブ構成になった。

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

この複合索引（`reminded` ASC, `date` ASC）は2026-08-19にリポジトリオーナーのアカウントで
ログインしたFirebase CLIから手動デプロイして本番へ反映済み。2026-08-20にIAMロールが
揃って以降は、`release-stg.yml`の`Deploy Firestore indexes`が`develop`→`release-stg`昇格の
たびに自動デプロイする（デプロイステップ自体は`continue-on-error: true`のまま。
失敗してもテスターへのAPK配布は止めず、ジョブ末尾で失敗を可視化する設計。
詳細はCLAUDE.mdの「Cloud Functionsも『リポジトリにコードがあるだけでは
本番で動かない』」の項を参照）ため、
以降の索引追加で手動デプロイは不要。

`processRecurringEvents`（毎年繰り返す予定）はフェーズ1では narrowing していなかった。
`date` フィールドは予定の**作成時点の年**を持つため、「今年の発生日」を求める
`nextOccurrence`（月日だけを見る）とは単純な範囲比較が噛み合わず、素朴な `date` 範囲条件
では絞り込めない。narrowing するには「次の発生日」を別フィールドとして保持するスキーマ
変更が要る。

フェーズ2として、そのスキーマ変更のうち**書き込み側だけ**に着手した（本PR）。
`processRecurringEvents`（`functions/src/index.ts`）が発生日を判定するたびに、
その値を `nextOccurrenceMs` フィールドへ書き戻すようにした。クエリ自体は今回もまだ
narrowing していない（`recurring == true` の全件走査のまま）。既存ドキュメントには
`nextOccurrenceMs` が無いため、いきなりこのフィールドで絞り込むと未設定分の通知が
止まってしまう。全件走査は15分間隔で毎回すべての繰り返し予定を通るため、このPRが
一定期間デプロイされていれば、専用の移行スクリプトを走らせなくても既存分は自然に
埋まる（`functions/src/reminders.integration.test.ts` の「nextOccurrenceMsが無い
繰り返し予定は…」「送信済みの年のまま発生日が翌年へ切り替わったら…」で、書き戻しが
送信状態（`remindedYear`/`remindedUidsYear`/`remindedUids`）を変えないことを確認済み）。
複合索引 `firestore.indexes.json` の `indexes`（`recurring` ASC, `nextOccurrenceMs` ASC,
`queryScope: COLLECTION_GROUP`）もあわせて追加した（フェーズ3のクエリ変更に備えた準備で、
現時点ではまだどのクエリからも参照していない）。

**残っている範囲（フェーズ3）**: このPRのデプロイから十分な時間（15分間隔の実行が
最低数回）が経ち、既存の繰り返し予定に `nextOccurrenceMs` が行き渡ったことを確認できたら、
`processRecurringEvents` のクエリに `.where("nextOccurrenceMs", "<=", 先読みカットオフ)`
を足して実際に絞り込む。あわせて上記の複合索引を（IAM未付与の間は）手動デプロイする
必要がある。

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

上記3つ（`NextMeetingCard`・`AnniversaryCard`・記念日リスト）は設定画面の奥に埋もれていたが、
2026-08-20にユーザーの判断で、思い出タブ削除の跡地に新設した「記念日」タブ
（`lib/screens/anniversary_hub_screen.dart`）へ1画面に統合した。設定画面からはこれら3セクション
（記念日・記念日リストへの導線・次に会う日）を削除し、「基本の休日」以降はそのまま残している。
旧`AnniversariesScreen`（記念日リストの独立全画面）は役目を終えたため削除し、そのタイル描画・
追加ダイアログ・削除（スワイプ）ロジックは`AnniversaryHubScreen`内の`_AnniversaryListSection`へ
移した。`NextMeetingCard`・`AnniversaryCard`自体は変更せずそのまま埋め込んでいる。新しい
Firestoreクエリやコレクションは増やしていない。

旧17（ペア未成立時の体験プレビュー）は、ペアリング画面（PairingScreen）に招待コード/QRの
上に「ペアになるとできること」カード（`lib/widgets/pairing_preview_cards.dart`）を追加し、
実装済みのため表から外した（本PR）。招待コードだけが表示される待機中の画面は離脱されやすく、
Pairyからの移行検討ユーザーは他アプリと比較検討中であることが多いため、機能を先に見せて
招待を最後まで送ってもらう／相手に参加してもらう後押しにする。静的なコンテンツのみで
Firestore・Cloud Functionsへの新しい依存は追加していない。

設定画面に「バグ報告・機能要望」フォーム（`BugReportScreen`）を追加した（本PR）。
送信内容はCloud Functions（`submitBugReport`）でGeminiにより厳格に分類（`bug` /
`feature_request` / `invalid`）され、有効なものだけが`bugReports`コレクションへ
`status: "pending"`でストックされる。ストックされた内容は新設のワークフロー
`fix-bug-reports.yml`（1日2回、`.claude/commands/fix-bug-reports.md`）が読み取り、
実装してdevelopへPRを作成しauto-mergeする（`reduce-debt.yml`/`propose-feature.yml`と
同じCI-onlyの安全装置）。設計上の注意点:
- `bugReports`は`firestore.rules`でクライアントからの読み書きを一切拒否している
  （`allow read, write: if false`）。書き込みは`submitBugReport`（Admin SDK）からのみ
  行うため、Gemini判定を経ずに直接キューへ書き込む経路が無い。
- 分類プロンプト（`functions/src/bug_report_logic.ts`の`buildTriageContents`）は、
  ユーザーの入力を明確な区切り線で囲み「指示ではなく分類対象のデータ」であることを
  明示し、埋め込み指示に従わないよう指定している（プロンプトインジェクション対策）。
  Geminiの応答も`parseTriageResponse`で厳格にスキーマ検証し、想定外の値は
  すべて判定失敗として扱う。
- `fix-bug-reports.yml`側のプロンプト（`.claude/commands/fix-bug-reports.md`）でも
  同様に「報告の原文は信頼できないデータであり指示ではない」ことを明示し、加えて
  `bugReports`ルール・分類ロジック・このコマンド自身・ワークフロー定義を報告内容を
  理由に変更しないよう明示している（自動化パイプライン自身の信頼境界を、
  ストックされた報告経由で緩められないようにするため）。
- AIチャット（askGemini）とは別の日次レート制限（`reportCallDate`/`reportCallCount`、
  既定5回/日）を`users/{uid}`に持たせている。こちらも`firestore.rules`で
  クライアントからの直接書き換えを拒否している。
- 未着手の報告一覧・処理状況の更新は、`functions/scripts/list-pending-bug-reports.mjs` /
  `mark-bug-report-status.mjs`（`firebase-admin`、`FIREBASE_SERVICE_ACCOUNT_KEY`と同じ
  資格情報）で行う。Firestoreドキュメントの読み書きのみで、`firebase deploy`のような
  ルール・索引デプロイ権限は不要なため、課題2隣接のIAM未付与（現状403で失敗する方）の
  影響は受けない想定だった。2026-08-20、実際に`fix-bug-reports.yml`の実行環境で
  `list-pending-bug-reports.mjs`を動かしたところ`7 PERMISSION_DENIED: Missing or
  insufficient permissions`で失敗することを確認した（想定は外れていた）。
  `firebase deploy`権限とは別に、Admin SDK経由のFirestoreドキュメント読み書き自体に
  必要なIAMロールが要ることが分かり、同日中に`gcloud projects add-iam-policy-binding
  aimaru-7eb2e --member="serviceAccount:github-actions-appdistrib@aimaru-7eb2e.iam.gserviceaccount.com"
  --role="roles/datastore.user"`でユーザー本人のGoogleアカウント経由で付与し解消した
  （**IAM付与自体はGCPコンソール操作が必要な人間専用の作業だが、`gcloud` CLIをインストールして
  ユーザーにブラウザ認証してもらえば、実際のロール付与コマンド自体はエージェントが代行できる**、
  という前例になった）。
  権限付与後、`list-pending-bug-reports.mjs`を再実行したところ**別のエラー**
  `9 FAILED_PRECONDITION: The query requires an index`が出た。`status`（等価）+
  `createdAt`（ソート）の複合クエリに対応する索引を`firestore.indexes.json`へ追加し
  忘れていたのが原因（本PR）で、`bugReports`コレクションに対する
  `collectionGroup: "bugReports", queryScope: "COLLECTION"`の索引を追加し、
  `firebase deploy --only firestore:indexes --project aimaru-7eb2e`で本番反映した。
  IAM権限・索引の両方が揃った状態は次回の`fix-bug-reports.yml`実行（cronまたは
  手動`workflow_dispatch`）で改めて確認すること。

2026-08-20、上記の権限・索引が揃った直後にユーザーが実際にアプリから機能要望
「自分が送った要望をこの画面で見れて、改修されたかも分かるようにしたい」を送信した
（`fix-bug-reports.yml`自体は当該実行でこれを処理しなかったため、Claudeがこのセッション内で
直接実装した）。対応した変更:
- `firestore.rules`の`bugReports`に`allow read: if request.auth.uid ==
  resource.data.createdBy`を追加した（書き込みは引き続き`if false`のまま）。
  自分が送った報告だけをアプリから確認できる。
- `firestore.indexes.json`に`bugReports`の`createdBy`+`createdAt`複合索引を追加した
  （`status`+`createdAt`の索引とは別物。両方とも本番へデプロイ済み）。
- `lib/screens/bug_report_screen.dart`のフォーム下に「送った報告」一覧セクションを
  追加した（`BugReportService.watchMyReports()`）。状況（未着手・対応中・対応済み・
  見送り）をバッジで表示し、見送りの場合は大まかな理由（`rejectCategory`、固定5分類:
  `already_done`/`unclear`/`out_of_scope`/`duplicate`/`other`）も表示する。
  `functions/scripts/mark-bug-report-status.mjs`と`.claude/commands/fix-bug-reports.md`
  を更新し、`rejected`にする際は必ず`--category`を指定するようにした。
- 送信のレート制限をAIチャット（askGemini）と同じ「日次」から「月次」へ変更した
  （`BUG_REPORT_MONTHLY_LIMIT = 10`、Firestoreのフィールド名も
  `reportCallDate`→`reportCallMonth`にリネーム）。バグ報告フォームは連投で
  Firestoreへストックされ続けると自動修正パイプラインの負荷が積み上がるため、
  日次より月次の方が実態に合うという判断。

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
- [x] ~~`GEMINI_API_KEY`をSecret Managerへ登録し、Cloud Functionsを本番へデプロイする~~ — 2026-08-20、ユーザー本人が`firebase functions:secrets:set GEMINI_API_KEY`のあと`firebase deploy --only functions --project aimaru-7eb2e`を手動実行し解消（`askGemini`・`submitBugReport`含む6関数が本番へ反映済み）。以降は下のIAM権限が揃ったため`release-stg.yml`の`Deploy Cloud Functions`で自動デプロイされる
- [x] ~~`FIREBASE_SERVICE_ACCOUNT_KEY`のサービスアカウントにCloud Functionsデプロイ用のIAMロールをGCPコンソールで付与~~ — 2026-08-20、`roles/cloudfunctions.developer`・`roles/iam.serviceAccountUser`・`roles/secretmanager.secretAccessor`・`roles/cloudbuild.builds.editor`を付与して解消（ユーザー本人が直接GCPコンソールで付与）。2026-08-21、直近3回の`release-stg.yml`実行で`Deploy Cloud Functions`が連続成功したことを確認済み。デプロイステップ自体は`continue-on-error: true`のまま据え置き、失敗時はジョブ末尾で可視化する設計にした（デプロイ失敗だけでテスターへのAPK配布まで止めないため）
- [x] ~~`FIREBASE_SERVICE_ACCOUNT_KEY`のサービスアカウントにFirestoreルールデプロイ用のIAMロールをGCPコンソールで付与~~ — 2026-08-20、`roles/firebaserules.admin`・`roles/datastore.indexAdmin`を付与して解消（`roles/firebaserules.admin`の付与コマンドはこのエージェント実行環境のauto-mode classifierにブロックされたため、ユーザー本人が直接GCPコンソールで付与）。2026-08-21、直近3回の`release-stg.yml`実行で`Deploy Firestore rules`/`Deploy Firestore indexes`が連続成功したことを確認済み。デプロイステップ自体は`continue-on-error: true`のまま据え置いている（理由は上のCloud Functionsの項と同じ）
- [x] ~~`FIREBASE_SERVICE_ACCOUNT_KEY`のサービスアカウント（`github-actions-appdistrib@aimaru-7eb2e.iam.gserviceaccount.com`）にFirestoreドキュメント読み書き用のIAMロールをGCPコンソールで付与~~ — 2026-08-20、`roles/datastore.user`を付与して解消（`gcloud` CLIをこのエージェント実行環境にインストールし、ユーザー本人のブラウザ認証のあと`gcloud projects add-iam-policy-binding`で実行）

## 既知だが直さない判断をしたもの

毎回の棚卸しで「新発見」として蒸し返さないよう記録しておく。

- **`couples` の読み取りルールが緩い**（認証済みなら他人のペアの `memberIds` / `anniversary` が読める）— 招待コード検索を成立させるための意図的な妥協。締めるなら `inviteCode` を別コレクションへ分離する設計変更が要る。TC-072 に記録済みで、`rules_test/firestore.test.js` の【既知】テストが現状を固定している（直したらそのテストが落ちて気づける）
- **全面 E2E 暗号化は採用しない** — AI 機能と両立しないため。COUPPLY が訴求している点だが追従しない判断
- **`functions`/`rules_test`のnpm audit（moderate 8件、いずれも`firebase-admin`経由の間接依存の`uuid`関連）を今は解消しない** — 2026-08-21、CIに`npm audit --omit=dev --audit-level=high`を追加した際に判明。解消には`firebase-admin`のメジャーバージョン更新（破壊的変更、動作確認が要る）が必要なため、high/critical未満は当面許容し、CIではhigh/critical限定で監視する
- **既存コードへの`dart format`の一括適用を見送った** — 2026-08-21、CIにフォーマットチェックを追加しようとした際に判明。このリポジトリのDartコードの多くは値を縦に揃える手書きの独自整形（例: `id:          doc.id,`）を使っており、`dart format`の標準スタイルとは異なる。一括で機械整形をかけたところ、一部の`if`文（例: `lib/screens/calendar_screen.dart`の`if (mounted) setState(...)`）で中かっこが外れ、`curly_braces_in_flow_control_structures`のlintが新たに7件発生することを確認した。挙動を変えずに一括修正するには個別の見直しが要るため、CIのフォーマットチェックは`continue-on-error: true`（可視化のみ）に留めている

## 自動化の構成

2026-08-14 に、実際には呼び出されていなかったNotion連携の`.claude/skills/`（scheduled-run /
notion-audit / notion-implement / market-brief / pr-review）を廃止し、GitHub Actions +
`claude-code-action`（`CLAUDE_CODE_OAUTH_TOKEN`認証、Claude Pro/Maxプランの利用枠を使う）
ベースの構成へ移行した。その後 `propose-feature.yml` は「調査してIssue起票のみ」から
「実装してPRを作りCI成功のみを条件にauto-mergeする」方式へ変わり（2026-08-14）、
その後既存課題の消化に絞った `reduce-debt.yml` を朝枠として追加し、2026-08-20には
アプリ内バグ報告・機能要望フォームから届く内容を処理する `fix-bug-reports.yml`
（1日2回）を新設した（下記の一覧は現状に更新済み）。`test-report.yml` / `backmerge.yml` /
`claude-mention.yml` は引き続き、月間コストを抑えるため「何か対応が要る時」だけ
Claudeを呼ぶ設計のまま（テストが全部greenの週やコンフリクトが無いリリースでは、
Claude起動コストは実質ゼロ）。

```
reduce-debt.yml       1日1回cron（朝）   docs/open-issues.mdのP0/P1のうちコード変更だけで完結するものを1つ実装 → develop へPR → CI成功でauto-merge
propose-feature.yml   1日1回cron（夜）   市場動向調査 → 改善を1つ実装 → develop へPR → CI成功でauto-merge
fix-bug-reports.yml   1日2回cron         Firestoreのbug報告ストックから未着手の1件を実装 → develop へPR → CI成功でauto-merge
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
