# AIMARU — セットアップ手順

## 0. プラットフォームフォルダの補完

このリポジトリは `lib/` と `pubspec.yaml` のみのFlutterプロジェクトで、`flutter create` が生成する `android/` `ios/` などのプラットフォームフォルダを含んでいません。Flutter SDK導入後、プロジェクトルートで一度だけ実行してください（既存の `lib/` `pubspec.yaml` は上書きされません）。

```bash
flutter create --platforms=android,ios --org com.example .
```

## 1. Flutter環境

```bash
# Flutter SDKインストール（未導入の場合）
# https://docs.flutter.dev/get-started/install

flutter --version  # 3.x.x 以上を確認
```

## 2. Firebaseプロジェクト作成

1. https://console.firebase.google.com → 新規プロジェクト作成
2. 「Authentication」→ 「Google」を有効化
3. 「Firestore Database」→ 作成（テストモードで開始）
4. 「Storage」→ 有効化

### FlutterFire CLI でFirebase接続

```bash
dart pub global activate flutterfire_cli
flutterfire configure
# → firebase_options.dart が自動生成される
```

### Firebase設定ファイルの非公開化

`android/app/google-services.json` / `ios/Runner/GoogleService-Info.plist` / `lib/firebase_options.dart` はAPIキーを含むため`.gitignore`済みで、リポジトリにはコミットしない（`flutterfire configure`で毎回ローカルに生成される想定）。

- **ローカル開発**: 上記の `flutterfire configure` を実行すれば3ファイルとも自動生成される。`GoogleService-Info.plist`（iOS）はCIでは使わないため、他の開発者と共有する場合は署名鍵（後述）と同様にパスワードマネージャーの添付ファイル機能などで安全にコピーすること。
- **CI/CD**: `firebase_options.dart` と `google-services.json` はGitHub Secrets（`FIREBASE_OPTIONS_DART_BASE64` / `GOOGLE_SERVICES_JSON_BASE64`、それぞれ`base64 -i <file> | tr -d '\n'`で生成）から復元してビルドする（`.github/workflows/`の各workflow参照）。値を更新した場合はSecretsも再登録すること。

## 3. Gemini APIキー取得

1. https://aistudio.google.com/apikey → 「APIキーを作成」
2. **重要**: 課金（Blazeプラン）が有効なGoogle Cloudプロジェクト（Firebase用のプロジェクトなど）を選ぶと、そのプロジェクトのGemini APIは無料枠が使えず「最初のトークンから課金」扱いになる（前払いクレジット¥0だと`prepayment credits are depleted`エラー）。無料枠を使うなら、プルダウンから「＋ プロジェクトを作成」で**課金が紐付いていない新規プロジェクト**を作り、そちらでキーを発行する
3. 無料枠の対象は Flash / Flash-Lite系のみ（Proモデルは対象外、2026年4月時点）。`gemini_service.dart` は `gemini-flash-lite-latest` を使用（`gemini-flash-latest`は無料枠が1日20リクエストしかなく枯渇しやすいため避けている。クォータ切れの場合はAPIが`429 RESOURCE_EXHAUSTED`を返す）
4. **キーはソースコードに書かず、ローカルの `.env.local` に置く**（GitHubにpushされないよう`.gitignore`済み）

```bash
cp .env.local.example .env.local
# .env.local を開いて GEMINI_API_KEY=発行したキー を設定
```

起動・ビルドは通常の `flutter run` / `flutter build apk` の代わりに、キーを読み込む付属スクリプトを使う：

```bash
./scripts/run_dev.sh                 # flutter run 相当
./scripts/build_release_apk.sh        # flutter build apk --release 相当
```

（直接 `flutter run` する場合は `--dart-define=GEMINI_API_KEY=xxx` を手動で付ける。`gemini_service.dart` は `String.fromEnvironment('GEMINI_API_KEY')` でこれを読む）

## 4. Google Calendar API（カレンダー同期）

1. https://console.cloud.google.com → Firebaseプロジェクトと同じGCPプロジェクトを選択
2. 「APIとサービス」→「ライブラリ」→ **Google Calendar API** を有効化
3. 「APIとサービス」→「OAuth同意画面」→ スコープに `.../auth/calendar.events` を追加
4. アプリはログイン時に `lib/services/auth_service.dart` の `GoogleSignIn(scopes: [...])` で `calendar.events` スコープを要求し、`lib/services/google_calendar_service.dart` が予定の作成・更新・削除を同期します（予定詳細画面のトグルでON/OFF）
5. **重要**: `calendar.events` は機密性の高いスコープのため、OAuth同意画面は「テスト中」ステータスのまま運用する（Google Cloud Console →「対象」）。この状態では**テストユーザーとして登録したGoogleアカウントしかログインできない**。Google Cloud Console →「対象」→「テストユーザー」→「Add users」から、自分と彼女のGoogleアカウントの両方を登録すること（上限100人、審査不要）
6. Androidで実機/エミュレータ実行する場合は、デバッグ/リリース用のSHA-1証明書フィンガープリントをFirebase Console →「プロジェクトの設定」→ Androidアプリ →「フィンガープリントを追加」で登録する必要がある（未登録だとGoogleログインが失敗する）。デバッグ用は次のコマンドで取得できる:
   ```bash
   keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android
   ```

## 5. Firestore / Storage セキュリティルール

Firestoreのルールは [`firestore.rules`](firestore.rules) を正としてリポジトリで管理しています（`firebase deploy --only firestore:rules` でデプロイ）。`rules_test/`ディレクトリ（Node.js + `@firebase/rules-unit-testing`）でユニットテスト可能です。

ハマりどころ:
- `create`時は`resource`がまだ存在せず`null`になるため、`resource.data`ではなく`request.resource.data`で判定すること
- `inviteCode`でのクエリ（招待コード参加）のように、ルールが参照するフィールド（`memberIds`）とクエリの絞り込み条件が一致しないクエリは、Firestoreがルールを"証明"できずに常に拒否される。読み取りは`request.auth != null`まで緩め、書き込み側（create/update/delete）で安全性を担保している

Storage（`storage_service.dart` が `couples/{coupleId}/...` 配下に画像を保存するため、カップルのメンバーのみ読み書きできるようにする）:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /couples/{coupleId}/{allPaths=**} {
      allow read, write: if request.auth != null &&
        request.auth.uid in firestore.get(/databases/(default)/documents/couples/$(coupleId)).data.memberIds;
    }
  }
}
```

## 6. 依存パッケージインストール

```bash
flutter pub get
```

## 7. main.dart の修正

```dart
// コメントアウトを解除
import 'firebase_options.dart';

await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

## 8. 起動

```bash
flutter run
```

## 9. プッシュ通知（Cloud Functions）

「パートナーが予定を追加したら通知」と「予定のリマインダー通知」はCloud Functions（`functions/`ディレクトリ）で動いています。**Blazeプラン（従量課金）が必須**です。Firebase Console →「使用量と請求額」からアップグレードしてください（Gemini APIですでにBlazeにしている場合は不要）。

```bash
# firebase-tools が未導入の場合
npm install -g firebase-tools
firebase login

# 依存パッケージインストール
cd functions
npm install
cd ..

# デプロイ（Functions本体 + collectionGroupクエリ用インデックス）
firebase deploy --only functions,firestore:indexes
```

仕組み:
- `onEventCreated`: `couples/{coupleId}/events/{eventId}` が作成されたら、作成者以外のメンバーへ「◯◯さんが予定を追加しました」というプッシュ通知を送る（`users/{uid}.notifyOnNewEvent` がfalseの人には送らない）
- `sendReminders`: 15分おきに実行されるスケジュール関数。各メンバーの `users/{uid}.reminderMinutesBefore`（設定画面で変更可、デフォルト60分）に応じて、開始前の予定をプッシュ通知する。`recurring: true` の予定（記念日など）は毎年の発生日を計算して繰り返し通知する

通知のON/OFFやタイミングはアプリの「設定」画面（⚙️）から変更できます。

### iOS でプッシュ通知を使う場合

1. Apple Developer で APNs認証キー（.p8）を作成
2. Firebase Console →「プロジェクトの設定」→「Cloud Messaging」→ APNs認証キーをアップロード
3. Xcode で `ios/Runner` に「Push Notifications」と「Background Modes → Remote notifications」の Capability を追加

### 通知が届かないとき

- 端末側で通知の許可（初回起動時のダイアログ）を許可しているか確認
- `users/{uid}` ドキュメントに `fcmToken` が保存されているかFirestoreコンソールで確認（ログインし直すと再取得されます）
- `firebase functions:log` でCloud Functions側のエラーを確認

---

## テスト

```bash
# ユニットテスト・ウィジェットテスト（祝日計算、テーマカラー切り替えなど）
flutter test

# 結合テスト（実際にFirebaseへ接続してアプリを起動し、画面遷移を確認する。
# 接続済みの実機/エミュレータが必要）
flutter test integration_test/app_test.dart -d <device-id>
```

## 配布・CI/CD

このリポジトリは3つのブランチで運用する。`release-stg` / `release-prd` は push すると自動でCI/CDが走る（`.github/workflows/`）。

- **`develop`** → 開発の起点。ここからブランチを切り、ここへマージする。PR で `flutter analyze` / `flutter test` とCloud Functionsの検査が走る。

- **`release-stg`** → push すると自動で `flutter build apk --release` → Firebase App Distributionへアップロードし、テスターに通知が届く。**動作確認済み。**
- **`release-prd`** → push すると自動で `flutter build appbundle --release` → Google Play Store（internalトラック）へアップロード。**Play Console側の準備が必要（下記）。**

開発の流れ:

```
作業ブランチ → develop → release-stg → release-prd
```

`develop` から作業ブランチを切って `develop` へマージ → `release-stg` へマージして App Distribution で実機確認 → 問題なければ `release-prd` へマージして Play Store へ。

### テスターに届くリリースノート

`release-stg.yml` は配布のたびに、**前回テスターに配布した地点からの変更履歴**を組み立ててApp Distributionのリリースノートに載せる。テスター側のアプリ一覧では、こう表示される:

```
1.0.0 (31)

■ 新機能
- 2人の空き時間検出・提案機能を追加 (#5)

■ 修正
- やりたいことリストが無限ローディングになる不具合を修正

commit ab34b59
```

- 起点は `stg-distributed` タグ（前回**配布に成功した**コミットを指す）。配布まで到達しなかった実行ではタグを進めないので、その回の変更は次の配布ノートに引き継がれる。
- 見出しの振り分けはコミットメッセージの接頭辞による（`feat:` → 新機能、`fix:` → 修正、それ以外 → その他）。テスターが読むのはここなので、コミットメッセージは「何が変わったか」が分かる日本語で書くこと。
- 40件を超える場合は新しい方から40件＋「ほか N 件の変更」に丸める。
- 配布前に中身を確認したいときは、GitHub Actionsの実行ページのサマリに同じ内容が出ている。

### バージョン番号の付き方

`1.0.0 (31)` の左がバージョン名、括弧内がビルド番号。**バージョン名は配布のたびに、含まれるコミットの種類に応じて自動で上がる**（`--build-name` に渡している）。

| 配布に含まれる変更 | 上がり方 | 例 |
|---|---|---|
| `feat:` が1つでもある | マイナー | 1.0.3 → 1.1.0 |
| `fix:` やその他だけ | パッチ | 1.0.3 → 1.0.4 |
| `feat!:` など破壊的変更、または本文に `BREAKING CHANGE` | メジャー | 1.0.3 → 2.0.0 |
| 変更なし（再ビルドのみ） | 据え置き（ビルド番号だけ進む） | 1.0.3 (35) → 1.0.3 (36) |

- **リリース済みバージョンの正はGitタグ `v1.0.4`**。配布に成功した時にだけ打つので、失敗した回で番号が飛ぶことはない。
- `pubspec.yaml` の `version:` は出発点としてだけ使う（初回リリースの値）。CIはここを書き換えないので、リポジトリ上の値は据え置きのままになる。**タグより新しい値を手で書けばそちらが優先される**ので、区切りとして `2.0.0` を宣言したい時などはpubspecを書き換えてマージすればよい。
- ビルド番号（括弧内）はCIの実行番号。Firebaseが「同じリリースの上書き」と判定してテスターに通知が飛ばなくなるのを防ぐため、毎回必ず変わる値にしている。
- `release-prd`（Play Store）は、そのコミットに付いている `v*` タグをそのままバージョン名に使う。stgで確認した番号とストアの番号が食い違わないようにするため。

### 必要なGitHub Secrets

いずれもリポジトリの Settings → Secrets and variables → Actions で登録する。値そのものはコミットしない。

| Secret名 | 用途 | 状態 |
|---|---|---|
| `FIREBASE_OPTIONS_DART_BASE64` | `lib/firebase_options.dart` をbase64化したもの（CIで復元） | 設定済み |
| `GOOGLE_SERVICES_JSON_BASE64` | `android/app/google-services.json` をbase64化したもの（CIで復元） | 設定済み |
| `GEMINI_API_KEY` | ビルド時にGemini APIキーを埋め込む | 設定済み |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | App Distributionへのアップロード認証（サービスアカウントJSON） | 設定済み |
| `FIREBASE_ANDROID_APP_ID` | 対象のFirebase Androidアプリ | 設定済み |
| `FIREBASE_PROJECT_ID` | Firebaseプロジェクト | 設定済み |
| `APP_DISTRIBUTION_TESTERS` | 通知するテスターのメール（カンマ区切り） | 設定済み |
| `ANDROID_KEYSTORE_BASE64` | リリース署名鍵（keystoreをbase64化したもの） | 設定済み |
| `ANDROID_KEYSTORE_PASSWORD` | 署名鍵のストアパスワード | 設定済み |
| `ANDROID_KEY_ALIAS` | 署名鍵のエイリアス（`aimaru`） | 設定済み |
| `ANDROID_KEY_PASSWORD` | 署名鍵のキーパスワード | 設定済み |
| `PLAY_STORE_SERVICE_ACCOUNT_JSON` | Play Developer APIでのアップロード認証 | **未設定（下記の手順が必要）** |

**リリース署名鍵について（重要）**: `android/app/release.keystore` と `android/key.properties` をこのマシンのローカルに生成済み（`.gitignore`済みでリポジトリには含まれない）。**この鍵を紛失すると、Play Storeに公開したアプリを二度と更新できなくなる**（Googleは同じ鍵での署名を要求するため）。`android/app/release.keystore` を必ず安全な場所（パスワードマネージャーの添付ファイル機能など）にバックアップしておくこと。

### Play Store側の準備（ユーザー側でのみ実施可能）

`release-prd` ブランチのワークフローを動かすには、以下がまだ必要（Google Cloud/Firebaseの権限では代行できず、Play Consoleのデベロッパーアカウント名義でしか行えない作業のため）:

1. [Google Play Console](https://play.google.com/console) でデベロッパーアカウントを作成（登録料 $25、初回のみ）
2. アプリを新規作成し、**手動で一度だけ**AAB（`flutter build appbundle --release`で作れる）をアップロードする（Play Developer APIは「一度も手動アップロードされていないアプリ」には使えないため）
3. `applicationId`（現在 `com.example.aimaru`。Play Storeでは`com.example`のような予約語は避けた方がよい）を正式なものに決める場合は、`android/app/build.gradle.kts` の変更に加えて、Firebase Consoleで新しいAndroidアプリとして登録し直す必要がある（`google-services.json`の再取得、SHA-1再登録も必要）
4. Google Cloud Console → 上記と同じGCPプロジェクトで、Play Developer API用のサービスアカウントを作成し、Play Console →「ユーザーと権限」でそのサービスアカウントに「アプリの管理」権限を付与
5. サービスアカウントのJSONキーを発行し、`PLAY_STORE_SERVICE_ACCOUNT_JSON` シークレットに登録
6. `.github/workflows/release.yml` の `packageName: com.example.aimaru` を実際のapplicationIdに合わせて修正

**リリース署名でのGoogleログインについて**: 現在Firebase ConsoleにはデバッグキーのSHA-1しか登録されていない。`release-prd`ブランチのビルド（今回生成した署名鍵）でGoogleログインを機能させるには、そのSHA-1もFirebase Console→プロジェクトの設定→Androidアプリ→フィンガープリントを追加、で登録すること。

### iOS（TestFlight）

```bash
# Apple Developer登録（¥12,900/年）が必要

# ipaビルド
flutter build ipa --release

# App Store Connect → TestFlight → 彼女を内部テスターに追加
```

---

## ファイル構成

```
lib/
├── main.dart                     # エントリポイント + ルーティング + ボトムナビ
├── models/
│   └── models.dart               # CoupleModel, AimaruEvent, ChatMessage, GeminiParsedEvent
├── services/
│   ├── auth_service.dart         # Google認証（+ Calendar同期スコープ）
│   ├── couple_service.dart       # ペアリング（招待コード）
│   ├── event_service.dart        # 予定 CRUD + リアルタイム同期
│   ├── gemini_service.dart       # AI 自然言語→予定変換・デートプラン提案
│   ├── chat_service.dart         # カップルチャット CRUD + リアルタイム同期
│   ├── storage_service.dart      # Firebase Storage 画像アップロード
│   ├── google_calendar_service.dart # Googleカレンダーへの予定push/削除
│   ├── notification_service.dart # FCMトークン保存・フォアグラウンド通知・タップ遷移
│   └── notification_settings_service.dart # 通知ON/OFF・リマインダー時間の設定（users/{uid}）
├── functions/                    # Cloud Functions（予定登録通知・リマインダー送信）
├── screens/
│   ├── login_screen.dart         # ログイン画面
│   ├── pairing_screen.dart       # ペアリング画面
│   ├── ai_chat_screen.dart       # AIチャット画面（自然言語で予定追加）
│   ├── calendar_screen.dart      # カレンダー画面（月表示・予定一覧）
│   ├── event_form_screen.dart    # 予定の新規作成・編集フォーム
│   ├── event_detail_screen.dart  # 予定詳細（写真・メモ・Google同期）
│   ├── chat_screen.dart          # カップルチャット（AIとは別）
│   ├── memories_screen.dart      # 思い出アルバム（画像グリッド）
│   └── settings_screen.dart      # 設定（プロフィール・ログアウト・Googleカレンダー表示設定）
└── utils/
    └── app_theme.dart            # カラー・テーマ定義
```

## 次のステップ

- [x] `CalendarScreen` — table_calendar でカレンダーUI実装
- [x] `EventDetailScreen` — 写真・メモ詳細画面
- [x] AIデートプラン提案（専用画面は廃止し、AIチャットの自然言語対話に統合）
- [x] Google Calendar API 同期（push + アプリ内表示、パートラー分もFirestore経由で共有）
- [x] カップルチャット・思い出アルバム（画像の端末保存対応）
- [x] Firebase Cloud Messaging — 予定登録通知・リマインダー通知（上記「9.」を参照、Cloud Functionsのデプロイが必要）
- [x] `CalendarScreen` — 全体表示（月グリッドに予定プレビュー）⇔ 選択表示（ドット+下部リスト）のトグル
- [x] 設定画面（プロフィール・ログアウト・Googleカレンダー表示/同期設定）
- [ ] `flutter create` でのプラットフォーム補完（上記「0.」を参照、ユーザー側で実施）
- [ ] `flutterfire configure` / Gemini APIキー / Google Cloud設定（上記手順を参照、ユーザー側で実施）
