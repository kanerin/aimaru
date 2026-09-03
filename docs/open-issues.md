# 残課題（最終更新: 2026-09-03 / 基準ブランチ `develop`）

このファイルは「今どこまで出来ていて、何が残っているか」を1枚で把握するためのもの。
2026-08-14にNotion連携の自動更新（`notion-audit`スキル）は廃止した。今後はPRの中で
このファイルを手動またはエージェントが都度更新する。

## 検証できていること

実際に実行して確認した事実だけを書く。

| 対象 | コマンド | 結果 |
|---|---|---|
| Cloud Functions（判定ロジック） | `cd functions && npm test` | **111件すべて通過**（ローカルで確認、CIでも要確認） |
| Cloud Functions（Firestore・Storage経路） | `cd functions && npm run test:integration` | **53件すべて通過**（ローカルで確認。下記「既知の環境上の制約」参照——2026-08-20時点でこのエージェント実行環境はNode 22系になっており、制約は解消済み） |
| Cloud Functions の型 | `cd functions && npm run typecheck` | **通過**（テストコード込み） |
| セキュリティルール | `cd rules_test && npm test` | **85件すべて通過**（ローカルで確認。同上の理由で制約は解消済み） |
| Flutter 単体・ウィジェット | `flutter test` | **487件すべて通過**（ローカルで確認、CIでも要確認） |

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
test/services/todo_service_test.dart              7   共有TODOのCRUD・並び順・カレンダー登録済みマーク
test/services/theme_controller_test.dart          4   テーマ
test/screens/todos_screen_test.dart               8   やりたいことリストのロード・エラー・表示状態・カレンダー登録への遷移・削除・完了切替・登録済みバッジ
test/utils/chat_date_divider_test.dart            5   トーク画面の日付区切り線を出すかどうかの判定
test/services/google_calendar_cache_service_test.dart 6 Google予定のprivate指定とキャッシュへの反映
test/screens/trash_screen_test.dart               4   ゴミ箱画面のロード・エラー・表示状態
test/utils/daily_question_picker_test.dart        5   デイリー質問の決定的な選択・日付キーからの質問復元
test/services/question_service_test.dart          8   デイリー質問への回答のCRUD・過去分を含む直近の取得
test/screens/questions_screen_test.dart           9   ふたりの質問画面のロード・エラー・回答状態・過去分の履歴表示
test/widgets/pairing_preview_cards_test.dart      2   ペア未成立時の機能プレビューカードの表示・スクロール
test/services/anniversary_service_test.dart       3   複数記念日のCRUD
test/screens/anniversary_hub_screen_test.dart      6   記念日タブ（次に会う日・記念日・記念日リスト）のロード・エラー・並び順・空表示
test/screens/event_form_screen_test.dart          7   予定フォーム（新規作成・編集・バリデーション・保存失敗・公開範囲・Google同期・画像アップロード）
test/widget_test.dart                             3   スモーク
integration_test/app_test.dart                    1   起動（実機必要・CIでは走らない）
functions/src/reminder_logic.test.ts             22   リマインダー判定・メンバー別送信済み管理
functions/src/trash_logic.test.ts                 4   ゴミ箱の保持期間判定
functions/src/reminders.integration.test.ts      12   Firestoreを読んで判定し書き戻す経路（ゴミ箱除外・先読み幅の絞り込み・繰り返し予定のnextOccurrenceMs書き戻し含む）
functions/src/trash.integration.test.ts           1   保持期限を過ぎた論理削除済み予定の完全削除
functions/src/gemini_logic.test.ts               35   askGeminiのレート制限・メンバー確認・Gemini APIレスポンス分岐
functions/src/ask_gemini.integration.test.ts      8   Firestoreを読んだメンバー確認・レート制限のトランザクション
functions/src/bug_report_logic.test.ts           21   バグ報告フォームの入力検証・分類プロンプト組み立て・Gemini応答の厳格パース
functions/src/submit_bug_report.integration.test.ts 10 バグ報告専用レート制限（askGeminiと独立）・報告の書き込み（invalidも捨てずに見送りとして残す）
functions/scripts/feature_request_routing.test.mjs 15 機能要望のIssue起票対象の選別（status非依存・二重起票防止）とIssue本文の組み立て
functions/src/dissolve_couple.integration.test.ts 8   カップル解消時のFirestore再帰削除・Storage削除・メンバー確認
test/services/bug_report_service_test.dart       15   バグ報告送信サービス（入力検証・応答解釈・エラー分類・自分の報告一覧watchMyReports）
test/screens/bug_report_screen_test.dart         10   バグ報告フォーム画面（受理・拒否・入力検証・送信中表示・失敗時表示・送った報告一覧の表示/エラー）
rules_test/firestore.test.js                     79   Firestoreルールのメンバー境界（todos・questionAnswers・anniversaries・aiCallCount/reportCallMonth保護・bugReports自分の報告のみ読める・ペアの解消・googleEventVisibility自分のみ読み書き含む）
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
0にリセットしてレート制限を無効化できてしまうため）。`release-stg.yml`・`release.yml`は元々
`--dart-define=GEMINI_API_KEY`を渡していなかったが、`scripts/run_dev.sh`・
`scripts/build_release_apk.sh`（ローカル開発用）には渡す名残りのコードが残っていた。
2026-08-22にこの2ファイルから削除し（元のフェーズ4）、対応する`.env.local.example`・
`.gitignore`の`.env.local`エントリ、READMEの説明・GitHub Secrets一覧の該当行も合わせて
削除した（`GEMINI_API_KEY`はGitHub Actionsのシークレットとしては元々どのworkflowからも
参照されておらず、実体はCloud FunctionsのSecret Manager側にのみ存在する）。
`parseGeminiReply`・応答スキーマ・`describeGeminiFailure`は
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

課題5（`applicationId`が`com.example.aimaru`のまま、REQ-029 / FEAT-036）は
2026-08-21に実現可否を調査した上で、**Play Store提出の直前まで意図的に着手しない**
判断にした（表からは外した）。

理由: `applicationId`はFirebaseのアプリ登録（Android）と1:1で紐づいており、変更は
「既存アプリの改名」ではなく「新しいパッケージ名でのアプリ再登録」になる。具体的には
Firebase側で新しいAndroidアプリを登録し直し、新しい`google-services.json`を取得して
`GOOGLE_SERVICES_JSON_BASE64`シークレットを差し替え、`firebase_options.dart`も
再生成して`FIREBASE_OPTIONS_DART_BASE64`を差し替え、Google Sign-InのOAuthクライアント・
SHA-1登録もやり直す必要がある。何より、Androidはパッケージ名が変わると「別アプリ」
として扱うため、**今いるテスター全員が既存のアプリをアンインストールして入れ直す**
ことになる（アップデートとして上書きできない）。

この「テスターに入れ直してもらう」コストは、いつ変更しても必ず発生する一回限りの
コストなので、今すぐ払っても、Play Store提出の直前に払っても同じだけかかる。
一方、今すぐ払うと「まだPlay Store提出の予定が具体化していない段階で、テスターの
手元のアプリを一度壊す」ことになり、提出直前にまとめて払うほうが実害が小さい
（Play Store提出自体がPlay Consoleアカウント作成等の人間専用作業を必要とし、
このタイミングで一緒に段取りすれば二度手間にならない）。そのため、Play Store提出の
準備が具体的に動くタイミングまで意図的に先送りする。

課題3（予定ごとの共有範囲）はフェーズ1として`AimaruEvent`に`visibility`フィールドを追加し、
2026-08-21のフェーズ2で読み取り制限・UI・クエリ絞り込みまで実装したため表から外した
（REQ-022 / FEAT-041）。

- `firestore.rules`の`events`に、visibilityとcreatedByを見る読み取り/更新/削除ルールを追加した。
  `private`な予定は作成者本人だけが読み書きでき、`create`では`createdBy`が本人のuidであることを
  強制、`update`では`createdBy`の書き換えを禁止した（所有権の乗っ取り防止）。既存ドキュメント
  （フィールド自体が無い）は`resource.data.get('visibility', 'shared')`でsharedとして扱う。
  存在しないマップキーへの`.`アクセスはルール評価エラーになる（`resource.data.visibility`のような
  直接アクセスは不可）ため、必ず`.get(key, default)`を使うこと。
- Firestoreのlistクエリはドキュメント単位でルールにより結果をフィルタしてはくれない
  （`rules_test`で実測: `visibility`で絞り込まない素朴なクエリは、単発`get()`なら拒否される
  相手のprivateな予定も普通に返してしまう）。そのため`lib/services/event_service.dart`の
  全取得クエリ（`watchMonthEvents`/`watchUpcomingEvents`/`watchRecurringEvents`/
  `watchEventsAsMap`/`watchDeletedEvents`）に`Filter.or(visibility=='shared', Filter.and
  (visibility=='private', createdBy==自分))`を追加し、クライアント側のクエリ自体で
  見せてはいけないデータを確実に除外するようにした。
- 上記のOR分岐ごとに複合索引が要るため、`firestore.indexes.json`へ5件追加した
  （`(visibility,date)` `(visibility,createdBy,date)` `(recurring,visibility)`
  `(recurring,visibility,createdBy)` `(visibility,createdBy)`）。
- `Filter`によるOR絞り込みは、クエリ条件に`visibility`フィールドの存在を要求する。既存の
  イベントドキュメント（フィールドを持たない）は絞り込みクエリにマッチせずカレンダーから
  消えて見えるため、コードのデプロイ前に`functions/scripts/backfill-event-visibility.mjs`を
  本番へ一度だけ実行し、既存ドキュメントへ`visibility: 'shared'`を補完した。
- `event_form_screen.dart`に「自分だけに表示（相手には見えません）」トグルを追加し、
  `calendar_screen.dart`の一覧に鍵アイコンでprivateな予定を示すようにした。
- `rules_test/firestore.test.js`にvisibility関連のテストを追加（作成時のcreatedBy強制、
  update時のcreatedBy不変、shared/privateの読み書き境界、絞り込み無しクエリの漏洩実証、
  絞り込み済みクエリが正しく除外することの確認）。`test/services/event_service_test.dart`にも
  「予定の公開範囲（private）」グループを追加した。
  `event_form_screen.dart`/`calendar_screen.dart`自体は元々テストが無く（外部サービスへの
  直接依存が多く注入可能な構造になっていない）、このPRでもそこまでは着手していない。

2026-08-28、上記のうち`event_form_screen.dart`にウィジェットテストを追加した（reduce-debt枠、
本PR）。`EventService`/`StorageService`/`GoogleCalendarService`をコンストラクタから注入できる
ようにし（`bug_report_screen.dart`と同じ「serviceOverride + 遅延getter」パターン）、新規作成・
編集・タイトル未入力時のバリデーション・保存失敗時のエラー表示・「自分だけに表示」トグル・
Googleカレンダー同期・画像アップロードの7経路を`test/screens/event_form_screen_test.dart`で
確認した。`calendar_screen.dart`（756行、複数のFirestoreストリームとGoogleカレンダーキャッシュに
依存し規模が大きい）は今回のスコープに含めておらず、次回以降の課題として残っている。

2026-08-29、上記の残りだった`calendar_screen.dart`にウィジェットテストを追加した（reduce-debt枠、
本PR）。`EventService`/`GoogleCalendarService`/`GoogleCalendarCacheService`/`SettingsService`/
`CoupleService`をコンストラクタから注入できるようにし（既存の`serviceOverride` + 遅延getterと
同じ設計）、あわせて「今日」を固定する`nowOverride`（`anniversary_hub_screen.dart`と同じ設計）も
追加してテストを日付非依存にした。作業の過程で、この画面のメイン予定ストリーム
（`_eventsStream`のStreamBuilder）が`hasError`を一切見ておらず、権限エラー等でストリームが
失敗すると「予定が0件の空のカレンダー」に見えたまま固まる不具合を見つけたため、
todos_screen.dart等と同じ文言のエラー表示を追加した（CLAUDE.mdの当該ルール自体への違反箇所
だった）。`test/screens/calendar_screen_test.dart`でストリームエラー時の表示・データ表示・
日付タップでの選択表示切り替え・private予定の鍵アイコン・予定詳細/予定作成画面への遷移
（Firebase未初期化のテストではpushされたことのみ確認、todos_screen_test.dartと同じ設計）を
確認した。Googleカレンダー同期・メンバー名表示（`_loadMembers`が直接`FirebaseFirestore.instance`
を参照している経路）はスコープに含めていなかった。

2026-08-30、上記の残りだったGoogleカレンダー同期・メンバー名表示のテストを追加した
（reduce-debt枠、本PR）。`_loadMembers`が`FirebaseFirestore.instance`に直接触れていたため
既存の`coupleServiceOverride`を通しても差し込めなかった箇所を解消するため、`CoupleService`に
`getMemberProfiles`（既存の`getPartnerName`と同じ注入済みの`_db`経由）を新設し、
`calendar_screen.dart`側の生の`cloud_firestore`依存を削除した。
`test/screens/calendar_screen_test.dart`に、メンバーの表示名が予定のアバターへ反映されること、
パートナーの共有Googleカレンダー予定が📅アイコン付きで表示されること、パートナーがprivate
指定したGoogle予定はクライアント側フィルタリングで表示されないことの3件を追加した
（`GoogleCalendarService`本体は実際のGoogle Sign-Inプラグインを叩くため、`fetchEvents`だけ
差し替えるフェイクサブクラスをテスト内に用意した）。これで`calendar_screen.dart`の主要経路の
テスト整備は完了した。

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

フェーズ3（クエリ絞り込み）は2026-08-21に完了した。確認手段として
`functions/scripts/check-recurring-events-migration.mjs`を先に追加し
（`recurring == true`の予定のうち`nextOccurrenceMs`が未設定の件数を数える）、
本番で実行して`missing: 0`（2件とも移行済み）を確認した上で、
`processRecurringEvents`のクエリに`.where("nextOccurrenceMs", "<=", 先読みカットオフ)`
を追加した。上記の複合索引は既に本番でREADYになっていたためデプロイ待ちは無かった。

**新規作成分の考慮**: このフィールドで絞り込むと、フィールド自体を持たないドキュメントは
クエリに一切マッチしなくなる（Firestoreの仕様。既存分の移行だけでは足りず、今後新規に
作られる繰り返し予定も同じ問題を抱える）。そのため`lib/services/event_service.dart`の
`_freshReminderFields`（`addEvent`/`updateEvent`の両方で使われる）に
`nextOccurrenceMs: Timestamp.fromMillisecondsSinceEpoch(0)`を追加し、新規作成・更新の
たびに必ず絞り込みへ引っかかる過去日時を書き込むようにした。この値は次回の
`processRecurringEvents`実行で実際の発生日時へ上書きされる。
`functions/src/reminders.integration.test.ts`に、epoch値を持つドキュメントが正しく
書き戻る場合と、フィールド自体が無いドキュメントが絞り込みで一切拾われないことの
両方を確認するテストを追加した。

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

2026-08-21、バグ報告・機能要望フォームに画像添付（最大`MAX_BUG_REPORT_IMAGES = 5`件）を
追加した。`bugReports`は`submitBugReport`（Admin SDK）経由でしか書き込めない設計を
維持したまま画像だけ追加できるよう、次の2段階にした:
1. `submitBugReport`が受理（`accepted: true`）した場合、作成した`bugReports`
   ドキュメントのIDをレスポンスへ含めるようにした。
2. クライアントはそのIDを使い、画像を`Storage`の`bugReports/{reportId}/`へ直接
   アップロードする（`storage.rules`に`firestore.get()`でそのドキュメントの
   `createdBy`と一致する本人だけに許可する新しいmatchブロックを追加、
   `couples/{coupleId}/`と同じ設計）。アップロードが終わったら新設の
   `attachBugReportImages`（Cloud Functions、Admin SDK）を呼び、`imageUrls`を
   そのドキュメントへ書き戻す（作成者本人以外からの呼び出し・存在しない
   報告ID・上限超過はすべて拒否する）。
   画像のアップロード・添付は受理された後の追加ステップなので、そこだけ失敗しても
   テキストの報告自体は既に受け付けられている（別メッセージで案内し、送信全体が
   失敗したかのような誤解を避ける）。
- `StorageService`の`_storage`フィールドが`FirebaseStorage.instance`を生成時に
  即座に参照していたため、テスト用サブクラスを作るだけでFirebase未初期化のまま
  落ちる問題があった。他のサービス（`EventService`等）と同じ遅延getterパターンに直した。
- `BugReportScreen`に画像選択UI（`ImagePicker`、最大5件・個別に取り除ける）を追加した。
  実機の`ImagePicker`はテストから差し込めないため、`initialImagesForTest`という
  テスト専用の注入ポイントを追加し、「画像が選択済み」の状態から送信フローを検証できる
  ようにした（既存の`serviceOverride`等と同じ設計方針）。

2026-08-21、`fix-bug-reports.yml`のGemini分類・処理方針を見直した。「Googleカレンダーの
終日予定が9:00表示になる」報告を3回連続で`already_done`と誤って却下していた根本原因
（既存機能の話に引っ張られた誤判定）や、「バグ」という単語を含むだけで機能不足の指摘まで
`bug`に分類されてしまう問題、既存機能の削除を求める要望が普通に`feature_request`として
受理されてしまう問題を受けて、次の対応をした:
- `buildTriageContents`（Gemini分類プロンプト）に、単語ではなく実際の挙動で判定する
  よう明示し、誤判定した実例（「やりたいことリストがカレンダー登録されたか一覧画面から
  わからないバグがある」→本来はfeature_request）を具体的に埋め込んだ。既存機能の削除・
  無効化を求める要望（「ペア解消の機能がいらない」等）はinvalidにするよう明示した。
  判断に迷う場合はinvalid側に倒すよう指示した（この指示はただの機能要望まで
  invalidへ倒してしまうため、2026-09-02に撤回した。下の項を参照）。
- **`fix-bug-reports.yml`が自動実装するのは`classification: "bug"`の報告だけ**に絞った。
  機能追加は「あったほうがよいかもしれない」という製品判断そのものであり、バグ修正
  （既存の意図通りに戻すだけ）と違って無人・無レビューでdevelopへ入れるべきではない
  という判断。`route-feature-requests-to-issues.mjs`（Claude Codeを介さない決定的な
  スクリプト）が、ワークフローの中でClaude Codeの実行より前に機能要望をGitHub Issueへ
  起票し、`rejected`（`out_of_scope`）にする。人間がそのIssueへ`@claude`でメンションして
  初めて`claude-mention.yml`が実装する。`list-pending-bug-reports.mjs`に
  `--classification=bug|feature_request`の絞り込みを追加し、`.claude/commands/
  fix-bug-reports.md`は必ず`--classification=bug`を付けて呼ぶよう更新した。
- cronの頻度を1日2回から5時間おき（`0 */5 * * *`）へ変更した。
- 上記の変更前に受理されていた既存の報告のうち、実態に合わないものを手動で是正した:
  「やりたいことリストが...わからないバグがある」（`bug`→`feature_request`へ再分類し、
  Issue #69を起票）、「ペア解消機能の削除」「AIによる内容チェック機能の削除」（いずれも
  既存機能を残す方針のため`rejected`・`other`で却下、Issueは起票しない）。

2026-08-22、`route-feature-requests-to-issues.mjs`が起票した機能要望Issue5件
（#68・#69・#71・#72・#73）をユーザーの指示で対話的に実装した（本来は各Issueへ
`@claude`メンションして`claude-mention.yml`に個別対応させる想定だが、今回は
まとめて着手）。実質3件の作業に整理できた（#69と#72、#71と#73はそれぞれ
同一要望の重複だった）:
- **トーク画面の日付区切り線**（#68）: `lib/utils/chat_date_divider.dart`に
  `shouldShowDateDivider`を切り出し、日付が変わったメッセージの直前だけに
  センターラインの区切りを出す。
- **やりたいことリスト→カレンダー変換後も一覧に残す**（#69・#72）:
  以前はカレンダー登録と同時にTODO自体を削除していたため、一覧から突然
  消えて「登録されたか分からない」という報告だった。`TodoItem.addedToCalendar`
  を追加し、削除ではなくマークして一覧に残し「登録済み」バッジを表示する
  （再タップでの重複登録も防ぐ）。
- **Googleカレンダー予定にも「自分だけに表示」を追加**（#71・#73）:
  AIMARU作成の予定にはprivate/shared設定があるのに、Google由来の予定には
  無かった（Googleカレンダー自体にこの概念が無いため）。新設の
  `couples/{coupleId}/googleEventVisibility/{uid}`（自分だけ読み書き可、
  `googleCalendarCache`と違いメンバーでも他人の分は読めない）へ
  private指定したGoogle予定のIDを保存し、`GoogleCalendarCacheService.
  pushMyEvents`が同期のたびにその指定を`GCalEventSummary.visibility`へ
  焼き直す（Google側のfetchEventsは毎回取り直しでこの概念を持たないため）。
  パートナーの端末では`visibility == private`のGoogle予定をカレンダー画面の
  描画時点で除外する（Firestoreルールでの絞り込みではなくクライアント側の
  除外である点はAIMARU予定のprivateと異なる。Googleカレンダーキャッシュの
  設計上、パートナーは同じFirestoreドキュメントを丸ごと読める権限を元々
  持っているため、この機能は「アプリのUI上は見せない」という粒度に留まる）。

2026-08-26、市場動向調査（propose-feature）で設定画面に「アプリロック」（4桁PIN）を
追加した。カップルアプリのレビュー記事では「スマホを渡すときに覗かれない」ロック機能が
選定基準の一つとして挙げられており、TimeTreeにはこの概念自体が無い差別化要素。
`lib/services/app_lock_service.dart`（SharedPreferencesへPINと有効フラグを保存する
端末ローカルの永続化層）・`lib/services/app_lock_controller.dart`（`ThemeController`と
同じ「シングルトン + ChangeNotifier」で`enabled`/`locked`を保持するランタイム層）・
`lib/screens/app_lock_screen.dart`（PIN入力画面）・`lib/widgets/app_lock_settings_card.dart`
（設定画面のトグル・PIN設定/変更ダイアログ）を追加した。`lib/main.dart`の
`MaterialApp.router`の`builder`をルーティングより外側の`_AppLockGate`で包み、
`WidgetsBindingObserver`で`AppLifecycleState.paused`（バックグラウンドへ回った）を
検知するたびロックする。ログイン画面を含めどの画面にいてもロック対象になる。
Firestoreには一切保存しない端末ローカルの機能のため、`firestore.rules`・
Cloud Functionsの変更は無い。

2026-08-27、市場動向調査（propose-feature）で設定画面に「ふたりの日記」（`DiaryScreen` /
`DiaryService`、`couples/{coupleId}/diaryEntries`）を追加した。競合調査でBetween Us等が
2025年以降に強化してきた「共有日記」機能が差別化要素として挙がっており、既存の
「ふたりの質問」（QuestionService）とは異なり相手の回答を伏せる仕組みを持たない、
自由記述で書き直しもできる日記として設計した。ドキュメントIDは`questionAnswers`と同じ
`${dateKey}_$uid`（1人1日1件）だが、`firestore.rules`では自分の分に限り`update`/`delete`
も許可している（`uid`の書き換えだけは所有権の乗っ取りになるため引き続き禁止）。
一覧はdateKeyの降順で直近60件（2人分で30日相当）を`orderBy`+`limit`で取得するのみで、
複合索引は増やしていない。`DataExportService`のJSON書き出しにも`diaryEntries`を追加した。

2026-08-28、アプリ内フォーム経由の機能要望2件（Issue #87・#88）を実装した（本PR）。

Issue #87（ふたりの質問の過去分を見たい）は、`QuestionService.watchRecentAnswers`
（dateKey降順で直近60件、`orderBy`+`limit`のみで複合索引は増やしていない）を追加し、
`QuestionsScreen`の下に「これまでの質問」として日付ごとのカードを並べる形にした。
質問文はFirestoreに保存していない（日付から決定的に選ぶ設計）ため、履歴側では
`questionForDateKey`で日付キーから復元している。**過去分でも「自分が回答するまで
相手の回答は見えない」ルールはそのまま効かせている**——ここを緩めると、答えずに
待って相手の回答だけ読む、が成立してしまうため。`firestore.rules`の変更は無い
（`questionAnswers`はもともとメンバーなら全件読める）。

Issue #88（アプリロックの解除に指紋認証を使いたい）は`local_auth`を導入し、
`lib/services/biometric_service.dart`（`BiometricAuthenticator`インターフェースと
local_authを叩く実装）・`AppLockController`の`biometricEnabled`/`unlockWithBiometrics`
を追加した。**PINは常に残す**（指紋が濡れて反応しない・怪我をしたといった場面で
アプリを開けなくなるのを避けるため）ので、生体認証はPINの置き換えではなく上乗せの
解除手段になる。`AppLockScreen`は開いた直後に一度だけ自動で認証を求め、キャンセル
されてもPIN入力欄とやり直しボタンを残す。`AuthenticationOptions`は`biometricOnly: true`
にしてある——端末のパスコードへフォールバックすると、端末のロックを開けられる相手が
素通りできてしまい「端末を渡した相手に中身を見せない」という目的が崩れるため。

ネイティブ側は3点。Androidは`MainActivity`を`FlutterFragmentActivity`に変更し
（androidx.biometricのBiometricPromptがFragmentActivityを要求する。`FlutterActivity`の
ままだと認証ダイアログを出す時点で失敗する）、`AndroidManifest.xml`に
`android.permission.USE_BIOMETRIC`を追加。iOSは`Info.plist`に
`NSFaceIDUsageDescription`を追加した（未設定だとFace IDの初回利用でクラッシュする）。
local_authはプラットフォームチャネル越しの呼び出しで単体テストから実行できないため、
`AppLockController.biometrics`を`@visibleForTesting`で差し替え可能にし、
`test/helpers/fake_biometric_authenticator.dart`をテストから差し込んでいる。
端末が非対応・指紋未登録の場合は設定画面のトグル自体を出さない。
Firestoreには一切保存しない端末ローカルの機能なので、`firestore.rules`・
Cloud Functionsの変更は無い。

2026-08-28、市場動向調査（propose-feature）で設定画面に「家事分担」（`ChoresScreen` /
`ChoreService`、`couples/{coupleId}/chores`）を追加した。カップルアプリのレビュー記事で
家事分担・交換日記が人気機能として挙がっており、交換日記（DiaryScreen）は先に
実装済みだったため対になる機能として追加した。TimeTreeにはこの概念自体が無い
差別化要素。`todos`と同じくどちらのメンバーも自由に追加・完了切り替え・削除でき、
加えて担当者（自分/相手/どちらでも、`assignedTo`のuidまたはnull）を指定できる。
完了済みを一括で未完了に戻す`resetAllDone`（週次リセット想定）も追加した。
`firestore.rules`は`todos`と同一のメンバー境界ルールを追加しただけで、新しい
バリデーションは無い。`DataExportService`のJSON書き出しにも`chores`を追加した。

2026-08-29、市場動向調査（propose-feature）で設定画面に「買い物リスト」
（`ShoppingListScreen` / `ShoppingListService`、`couples/{coupleId}/shoppingItems`）を
追加した。夫婦・カップル向けアプリの比較記事で家事分担と並ぶ人気機能として
挙がっており、TimeTreeにはこの概念自体が無い差別化要素。`todos`・`chores`とは別に、
日用品・食材の買い出しを2人で共有する。`quantity`（「1本」「2個」等）は自由記述の
任意フィールド（数量の単位がアイテムによってバラバラなため構造化はしない）。
choresの`resetAllDone`（完了済みを未完了に戻す週次リセット）とは異なり、買い物リストは
購入済みになったら消したいものなので`clearDone`で一括削除する設計にした。
`firestore.rules`は`chores`と同一のメンバー境界ルールを追加しただけ。`DataExportService`の
JSON書き出しにも`shoppingItems`を追加した。

2026-09-01、市場動向調査（propose-feature）でカップル間チャット（`ChatScreen` /
`ChatService`）にメッセージへのリアクション（絵文字）機能を追加した。Between・Pairyなど
主要なカップルアプリはメッセージへのスタンプ的な反応を持つが、AIMARUのトークはテキストと
画像を送るだけだった（2026年9月時点の競合調査）。`ChatMessage`に`reactions`
（uid→絵文字、1人1つまで）を追加し、メッセージを長押しすると絵文字ピッカー（❤️😂😮😢👍🙏の
固定6種）が開く。既に付けた絵文字を選び直すと外れる（トグル）。バブルの下に絵文字ごとの
人数付きピルを表示し、ピルをタップしても同様にトグルできる。テキストメッセージの
長押しは従来「コピー」だったため、ピッカーの下に「コピー」の選択肢を残した（画像は
既存のダウンロードアイコンで保存できるため長押しはピッカー専用にした）。
`couples/{coupleId}/chats/{msgId}`は元々メンバーなら誰でも自由に書き込める設計
（`firestore.rules`の`allow read, write`）だったため、`firestore.rules`の変更は無い
（`reactions.$uid`だけを書き換える設計にしているが、ルール上は元々メッセージ全体を
書き換えられる）。`DataExportService`のJSON書き出しは対象外とした（リアクションは
一覧性より会話中の反応そのものに価値があるUI上の要素のため）。

2026-08-28、アプリから届いた機能要望が黙って消える経路を2つ塞いだ（本PR）。

1つ目は`submitBugReport`（`functions/src/index.ts`）。Geminiが`invalid`と判定した報告を
`{accepted:false}`で返すだけで**Firestoreへ一切書かずに捨てていた**。分類プロンプトは
「判断に迷う場合はinvalidに倒す」「既存機能の削除・無効化を求める要望はinvalid」と
意図的にinvalid寄りにしてあるため、正当な機能要望がinvalidへ落ちることは普通に起こる。
ドキュメントが無いのでIssueも起票されず、アプリの「送った報告」にも出ず、`logger`にも
残らないため、後から拾い直す手段が一切無かった。invalidも
`status: 'rejected'` / `rejectCategory: 'unclear'` として保存するようにして、
少なくとも本人が「送った報告」で確認でき、後から拾えるようにした。
**この修正より前に捨てられた報告は復元できない**（どこにも記録が残っていない）。

あわせて、そもそもinvalidへ落ちすぎないよう分類プロンプト（`buildTriageContents`）も
直した。「判断に迷う場合はinvalid側に倒してください」という指示が、ただの機能要望まで
invalidへ倒していたため、invalidは列挙した条件（スパム・アプリと無関係・指示文の埋め込み・
意味不明な文字列・個人情報の羅列・既存機能の削除や無効化を求める要望）に限り、
それ以外は多少曖昧でもfeature_request（実際に壊れているならbug）にするようにした。
機能要望は自動実装されずIssueとして人間の判断に回るので、曖昧なものを捨てるより
Issueに残すほうが望ましいという理由もプロンプトに書いてある。
「既存機能の削除・無効化を求める要望はinvalid」は、残すか削るかが製品判断そのものなので
従来どおり維持している。

2つ目は`functions/scripts/route-feature-requests-to-issues.mjs`。`status == 'pending'`の
機能要望だけをIssue化していたため、この仕組みが入る前（2026-08-21、PR #70）に届いた
機能要望や、先に`rejected`/`done`/`in_progress`へ動いていた機能要望は永久にIssueが
起票されないまま取り残されていた。statusではなく`issueNumber`（起票したら
ドキュメントへ書き戻す）の有無で判定するようにして、取り残しを拾いつつ二重起票も
防ぐようにした。あわせて、1件の`gh issue create`失敗でループごと止まって残りが
次回まで放置されていたのをtry/catchで続行するようにし、Issue本文に報告の原文
（信頼できない入力である旨を明記した上で引用）も載せるようにした。

Issue化を`fix-bug-reports.yml`（2日に1回、Claude Codeの実行とセット）だけに任せず、
`route-feature-requests.yml`（毎日＋`workflow_dispatch`での手動実行）としても回すように
した。Firestoreを読んで`gh`を叩くだけの軽い処理で、バグ修正の自動実装とは独立して
回せるべきものだったため。取り残しのバックフィルもこのワークフローの手動実行で行う。

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

- ~~`couples` の読み取りルールが緩い（認証済みなら他人のペアのmemberIds/anniversaryが読める）~~ — 2026-08-22解消（旧TC-072）。招待コード検索を新設の `inviteCodes/{code}` コレクション（coupleIdと参加者uidだけをミラーする最小限のドキュメント、ドキュメントID=コード自体）へ分離し、`couples/{coupleId}` の読み取りを `request.auth.uid in resource.data.memberIds`（メンバーのみ）へ締めた。
  - `inviteCodes`は`allow get`のみ許可し`list`は禁止（総当たり列挙を防ぐ）。`create`は自分1人だけのmemberIdsでのみ許可（定員の偽装を防ぐ）、`update`は自分を追加する場合かつ現在の人数が2人未満の場合のみ、`coupleId`の書き換えは拒否。実データ（anniversary等）はここには一切置かないため、この分離コレクション側のルールが多少緩くても実害は無く、`couples`側のcreate/updateルールが最終防衛線になる設計。
  - `lib/services/couple_service.dart`の`createInviteCode`/`joinWithCode`は、`couples`本体と`inviteCodes`ミラーの両方を`WriteBatch`で同時に書き込む（どちらか一方だけ反映される不整合を避けるため）。`joinWithCode`は`couples`本体を読まず`inviteCodes`ミラーだけを見て定員・二重参加を判定する（参加前はメンバーではないため`couples`本体を読めない）。
  - `functions/src/index.ts`の`dissolveCouple`は、`couples`本体をrecursiveDeleteする前に対応する`inviteCodes/{code}`も削除するようにした（`inviteCodes`は`couples`のサブコレクションではなく別のトップレベルコレクションのため、recursiveDeleteの対象に入らず孤立する）。この追加分はonCall関数のハンドラを直接叩くテストがリポジトリに元々無い（`askGemini`等の他のonCall関数も同様）ため、既存の慣習に合わせて専用テストは追加していない。
  - `rules_test/firestore.test.js`の【既知】テストは反転し、`rules_test/helpers.js`に`seedInviteCode`を追加した。`test/services/couple_service_test.dart`の`seedCouple`ヘルパーも`inviteCodes`ミラーを合わせて作るよう更新した。
- **全面 E2E 暗号化は採用しない** — AI 機能と両立しないため。COUPPLY が訴求している点だが追従しない判断
- ~~`functions`/`rules_test`のnpm audit（moderate、firebase-admin経由の間接依存のuuid関連）を今は解消しない~~ — 2026-08-22解消。`firebase-admin`を最新（14.3.0）まで上げても解消しないと判明した（原因はGoogle自身の`@google-cloud/storage`が内部で使う`teeny-request`のuuidピン止めで、firebase-adminのバージョンとは無関係）。メジャーバージョン更新はリスクの割にこの件を解消しないため見送り、`functions/package.json`の`overrides`で`uuid`だけを`^14.0.2`へ強制する形で解消した（`npm audit --omit=dev`が0件になったことを確認済み）。`rules_test`は元々`dependencies`が無く（全てdevDependencies）`--omit=dev`で0件だった。今後もし`overrides`無しでuuidを直接使う依存が増えたら、この対処が効かなくなる可能性がある点に留意
- **既存コードへの`dart format`の一括適用は見送ったまま** — 2026-08-21、CIにフォーマットチェックを追加しようとした際に判明。このリポジトリのDartコードの多くは値を縦に揃える手書きの独自整形（例: `id:          doc.id,`）を使っており、`dart format`の標準スタイルとは異なる。一括で機械整形をかけると、一部の`if`文（例: `lib/screens/calendar_screen.dart`の`if (mounted) setState(...)`）で中かっこが外れる。一括整形自体は見た目だけの大きな差分で実利が薄いため見送ったままだが（CIのフォーマットチェックは引き続き`continue-on-error: true`）、**そこで見つかった「中かっこが外れると将来のバグを誘発する」というリスクだけは2026-08-22に別途対処した**: `analysis_options.yaml`へ`curly_braces_in_flow_control_structures: true`を追加した。現状のコードはこのlintに違反していない（＝今は中かっこが外れた単文ifは無い）ため個別修正は不要だったが、`flutter analyze`はCI/配布のどちらでも必須（blocking）ステップのため、今後誰か（人間・自動実装エージェントのどちらも）が単文ifの中かっこを省略したり、将来`dart format`の一括適用に踏み切って中かっこが外れたりした場合、その場でCIが落ちて気づける
- **設定画面の「ペアを解消する」単体ボタンは廃止した**（issue #102、2026-09-03）。ペアだけ解消して両者のアカウントは残すという中間状態はほぼ使われておらず、誤操作でパートナーとの記録（予定・チャット・写真等）が消えるリスクの方が大きいという判断。ただし`dissolveCouple`自体（`CoupleService`のメソッド・Cloud Function）は削除していない。「アカウントを削除する（退会）」フローが、ペアを組んでいる場合の後始末として内部的にそのまま呼び続けているため（設定画面のボタンをそのまま消すと退会機能自体が壊れる）。
- **トークのメッセージ通知を追加した**（issue #111、2026-09-03）。`onEventCreated`と同じパターンで`couples/{coupleId}/chats/{messageId}`にonDocumentCreatedトリガー（`onChatMessageCreated`）を追加し、送信者以外のメンバーへFCM通知を送る。本文の切り詰め（`buildChatNotificationBody`、40文字超は`…`で省略、画像のみの場合は「写真を送りました」）は`chat_notification_logic.ts`に純粋関数として切り出し単体テスト済み。設定画面に「トークのメッセージ通知」のON/OFFスイッチ（`notifyOnNewChatMessage`、デフォルトtrue）を追加した。`isAi: true`のメッセージ（現状クライアントからは常にfalseだが将来のbot発言に備えたフィールド）は通知しない。トリガー本体（Firestoreエミュレータでの結合テスト）は、同じパターンの`onEventCreated`が元々一切テストされていない既存の慣習に合わせ、専用テストは追加していない。
- **AIチャットから通知設定・買い物リストへの追加ができるようにした**（issue #110、2026-09-03）。`gemini_service.dart`に`GeminiReplyKind.action`を追加し、「通知をオフにして」「リマインダーは30分前にして」「買い物リストに牛乳を追加して」のような自然言語の指示を、予定追加(events)と同じ「確認カード→ボタンで実行」の流れで処理できるようにした。対象は`notifyOnNewEvent`・`notifyOnNewChatMessage`・`remindersEnabled`・`reminderMinutesBefore`（設定画面と同じ15/30/60/180/1440分のみ許可）・買い物リストへの追加（1〜20件、各50文字以内）に限定している。アプリロックやペア解消のような不可逆・安全に関わる設定は、誤解釈で実行されたときの実害が大きいため対象外にした（ユーザー本人の判断でスコープを決定済み）。「次に会える日」を変更したいという要望は、既存の予定追加(events)がそのままカバーする（次に会える日は最も近い将来の予定から自動計算される値で、独立した設定項目ではないため）。

2026-09-03、市場動向調査（propose-feature）で「ふたりの質問」（QuestionsScreen）に
デイリー質問のリマインダー通知を追加した。サービス終了したPairyの移行先として比較
されるSumOne/Twinestは毎日決まった時刻にプロンプト通知を送る体験を持つが、AIMARUの
「ふたりの質問」は画面を自分から開かない限り、その日の質問に気づかず日が変わって
終わることが多かった。新設のスケジュール関数`sendDailyQuestionReminder`
（`0 20 * * *`、Asia/Tokyo、既存の`sendReminders`とは走査対象が全く異なるため
15分間隔のスケジュールとは分けた）が毎晩20時に全カップルを走査し、その日の質問に
まだ回答していないメンバーだけへFCM通知を送る。判定は`question_reminder_logic.ts`
の純粋関数（`tokyoDateKey`・`resolveQuestionReminderTargets`）に切り出し、
`questionAnswers`のドキュメントID（`${dateKey}_$uid`）と同じdateKeyの導出になる
よう、Cloud Functionsの実行環境のタイムゾーンに依存しないUTCベースの計算にした
（ホストがAsia/Tokyo以外で動いていても、クライアント側の`DateFormat('yyyy-MM-dd')`
と同じ日付キーになる）。設定画面に「ふたりの質問のリマインダー通知」のON/OFF
スイッチ（`notifyOnDailyQuestion`、デフォルトtrue）を追加した。全カップルを
1日1回`db.collection("couples").get()`で走査するだけの軽い処理のため、課題8で
問題になったような複合索引やクエリ絞り込みは不要（`firestore.rules`の変更もない
——`users/{uid}`は元々`notifyOnNewEvent`等と同列の任意フィールドを書き込める）。

## 自動化の構成

2026-08-14 に、実際には呼び出されていなかったNotion連携の`.claude/skills/`（scheduled-run /
notion-audit / notion-implement / market-brief / pr-review）を廃止し、GitHub Actions +
`claude-code-action`（`CLAUDE_CODE_OAUTH_TOKEN`認証、Claude Pro/Maxプランの利用枠を使う）
ベースの構成へ移行した。その後 `propose-feature.yml` は「調査してIssue起票のみ」から
「実装してPRを作りCI成功のみを条件にauto-mergeする」方式へ変わり（2026-08-14）、
その後既存課題の消化に絞った `reduce-debt.yml` を朝枠として追加し、2026-08-20には
アプリ内バグ報告・機能要望フォームから届く内容を処理する `fix-bug-reports.yml`
を新設した（下記の一覧は現状に更新済み）。`test-report.yml` / `backmerge.yml` /
`claude-mention.yml` は引き続き、月間コストを抑えるため「何か対応が要る時」だけ
Claudeを呼ぶ設計のまま（テストが全部greenの週やコンフリクトが無いリリースでは、
Claude起動コストは実質ゼロ）。

2026-08-21、`fix-bug-reports.yml`の役割を「バグ修正のみ」に絞った。無人・無レビューで
developへ入れてよいのはバグ修正（既存の意図通りに戻すだけ）に限り、機能追加は
「あったほうがよいかもしれない」という製品判断そのものであるため、人間の承認を
必須にした。`classification: feature_request`の報告は、Claude Codeの判断を介さない
決定的なスクリプト（`functions/scripts/route-feature-requests-to-issues.mjs`）が
GitHub Issueへ起票してrejected（out_of_scope）にする。人間がそのIssueへ`@claude`で
メンションして初めて`claude-mention.yml`が実装する。cronの頻度も1日2回から
5時間おきへ変更した。

```
reduce-debt.yml       1日1回cron（朝）   docs/open-issues.mdのP0/P1のうちコード変更だけで完結するものを1つ実装 → develop へPR → CI成功でauto-merge
propose-feature.yml   1日1回cron（夜）   市場動向調査 → 改善を1つ実装 → develop へPR → CI成功でauto-merge
fix-bug-reports.yml   5時間おきcron      Firestoreのbug報告ストックから未着手のバグ報告1件を実装 → develop へPR → CI成功でauto-merge（機能要望はIssue化のみ、人間承認制）
test-report.yml       週2-3回cron        テスト実行（プレーンshell）→ 失敗時のみClaudeが分析してIssueへ
backmerge.yml          release-prd push契機  戻しマージPR自動作成 → コンフリクト時のみClaudeが分析コメント
claude-mention.yml     @claudeメンション（書き込み権限者限定） → 良い提案Issueを人間が選んで実装依頼（fix-bug-reports.ymlが起票した機能要望Issueもここに含まれる）
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
