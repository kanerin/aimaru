# 残課題（最終更新: 2026-08-12 / 基準ブランチ `develop`）

このファイルは「今どこまで出来ていて、何が残っているか」を1枚で把握するためのもの。
`notion-audit` スキルが棚卸しのたびにここを更新する。Notion の各 DB が詳細の正で、
ここはその要約という位置づけ。

## 検証できていること

実際に実行して確認した事実だけを書く。

| 対象 | コマンド | 結果 |
|---|---|---|
| Cloud Functions | `cd functions && npm test` | **17件すべて通過** |
| Cloud Functions の型 | `cd functions && npm run typecheck` | **通過**（テストコード込み） |
| Flutter 単体・ウィジェット | `flutter test` | **106件**（別セッションが実 SDK で通過を確認済み。この作業環境には Flutter SDK が無く再確認はしていない） |

テストの内訳:

```
test/services/gemini_reply_parser_test.dart      17   AI応答パース・失敗分類
test/widgets/event_datetime_fields_test.dart     15   日時入力ウィジェット
test/services/event_service_test.dart            14   予定CRUD・終日・期間クエリ
test/services/couple_service_test.dart           13   ペアリング・招待コード
test/utils/japan_holidays_test.dart              13   祝日計算
test/utils/recurring_events_test.dart            12   毎年繰り返しの展開
test/services/google_calendar_service_test.dart   8   Googleとの日時変換
test/models/aimaru_event_test.dart                7   モデルの変換
test/services/theme_controller_test.dart          4   テーマ
test/widget_test.dart                             3   スモーク
integration_test/app_test.dart                    1   起動（実機必要・CIでは走らない）
functions/src/reminder_logic.test.ts             17   リマインダー判定
```

## 残っている課題

優先度は Notion の要件に準拠。**着手するときは必ず Notion 側の該当要件を正として読むこと。**

### P0 — 着手すべきもの

| # | 課題 | 対応する要件 / ケース | なぜ残っているか |
|---|---|---|---|
| 1 | **CI が GitHub の必須チェックになっていない** | REQ-027 / FEAT-052 / TC-094 | Settings → Branches → develop → Require status checks の設定が要る。**リポジトリ管理者権限が必要でエージェントからは実施できない** |
| 2 | **Firestore / Storage セキュリティルールのテストが無い** | REQ-025 / REQ-027 / TC-068〜TC-079 | README にある `rules_test/` が実在しない。`@firebase/rules-unit-testing` での構築が必要 |
| 3 | **`storage.rules` がリポジトリに無い** | REQ-025 / FEAT-034 / TC-077 | README に内容の記載があるだけで、ファイル化もデプロイ対象化もされていない |
| 4 | **Gemini API キーがビルド成果物に埋まる** | REQ-026 / FEAT-046 / TC-087 | `--dart-define` はソースへの直書きを防ぐだけで、APK からは抽出できる。Cloud Functions の `onCall` へ移して Secret Manager に置く必要がある |
| 5 | **予定ごとの共有範囲が選べない** | REQ-022 / FEAT-041 | 全予定がペア双方に見える。モデル・Firestore ルール・通知の3経路に影響する |
| 6 | **ペア解消・退会・データエクスポートの導線が無い** | REQ-023 / REQ-024 / FEAT-039 / FEAT-040 | 関係の終わりを迎えるユーザーを扱えていない。個人情報の削除請求への対応義務もある |
| 7 | **`applicationId` が `com.example.aimaru` のまま** | REQ-029 / FEAT-036 | Play Store で `com.example` は避けるべき。変更すると Firebase のアプリ再登録と `google-services.json` 再取得が要る |
| 8 | **リリース署名鍵の SHA-1 が Firebase に未登録** | REQ-029 / TC-096 | リリースビルドで Google ログインが失敗する |

### P1 — 次に効くもの

| # | 課題 | 対応する要件 / ケース | 補足 |
|---|---|---|---|
| 9 | **リマインダーの `reminded` が予定単位で、メンバー単位でない** | TC-059 | メンバーの通知設定が違うと（60分前と1日前など）片方の通知が**永久に失われる**。`functions/src/index.ts` の133行目・172行目 |
| 10 | **`sendReminders` が `collectionGroup` の全件走査** | REQ-028 / FEAT-048 | `index.ts` 97行目・139行目。ユーザー数に対して課金と実行時間が線形以上に伸びる |
| 11 | **画像から予定を読み取れない** | REQ-016 / FEAT-044 | TimeTree が実装済み。カップルの予定は他アプリのスクショが出どころ |
| 12 | **2人の空き時間の検出・提案が無い** | REQ-017 / FEAT-045 | **競合が構造的に持てない優位性**。必要なデータ（自前の予定＋双方のGCalキャッシュ）は既に揃っている |
| 13 | **共有TODO・やりたいことリストが無い** | REQ-012 / FEAT-042 | 日付未定のアイデアの置き場が無く、「予定を書く道具」で止まっている |
| 14 | **他社アプリからの移行手段が無い** | REQ-003 / FEAT-038 | Pairy 終了で移行先を探す層が市場に出ている。獲得の窓は永続しない |
| 15 | **iOS が未整備** | REQ-030 / FEAT-049 | 片方が使えないとカップルアプリは価値がゼロになる |
| 16 | **AI 呼び出しのレート制限が無い** | REQ-018 / FEAT-046 | 4番と同時に実施するのが合理的 |
| 17 | **論理削除・バックアップが無い** | REQ-031 / FEAT-050 | 誤削除した思い出を戻せない |

### P2 — 余力があれば

| # | 課題 | 対応する要件 |
|---|---|---|
| 18 | 去年の今日の振り返り通知 | REQ-021 / FEAT-047 |
| 19 | ペア未成立時の体験プレビュー | REQ-033 / FEAT-051 |
| 20 | 収益モデル | REQ-032 |

## 人間にしかできない作業

エージェントが着手しても完了できないもの。ここが詰まると後続が止まる。

- [ ] **CI を必須チェックに設定**（Settings → Branches → develop）— 課題1
- [ ] リリース署名鍵の SHA-1 を Firebase Console に登録 — 課題8
- [ ] Play Console でデベロッパーアカウント作成、手動で1度 AAB をアップロード — REQ-029
- [ ] `PLAY_STORE_SERVICE_ACCOUNT_JSON` シークレットの登録 — REQ-029
- [ ] Apple Developer 登録、APNs 認証鍵の作成 — 課題15
- [ ] OAuth 同意画面のテストユーザー登録（上限100人）または審査申請
- [ ] `android/app/release.keystore` のバックアップ（**紛失するとアプリを二度と更新できない**）

## 既知だが直さない判断をしたもの

毎回の棚卸しで「新発見」として蒸し返さないよう記録しておく。

- **`couples` の読み取りルールが緩い**（認証済みなら他人のペアの `memberIds` / `anniversary` が読める）— 招待コード検索を成立させるための意図的な妥協。締めるなら `inviteCode` を別コレクションへ分離する設計変更が要る。TC-072 に記録済み
- **「国民の休日」（祝日に挟まれた平日）が未対応** — 発生頻度が低いため
- **全面 E2E 暗号化は採用しない** — AI 機能と両立しないため。COUPPLY が訴求している点だが追従しない判断

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
`release-stg` / `release-prd` へ直接触らない。
