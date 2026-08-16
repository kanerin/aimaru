#!/usr/bin/env bash
# 結合テスト（E2E）をローカルで実行するスクリプト。
#
# 実機/エミュレータ上でアプリを本当に起動して操作する。Firebaseの接続先は
# ローカルのエミュレータに切り替わるので、本番データには一切触らない。
#
# 事前準備:
#   1. Androidエミュレータ（または実機）を1台つないでおく
#   2. firebase-tools を入れておく: npm install -g firebase-tools
#
# 使い方:
#   ./scripts/run_e2e.sh                                         # 全部
#   ./scripts/run_e2e.sh integration_test/event_crud_test.dart   # 1ファイルだけ
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT_ID="aimaru-7eb2e"
TARGET="${1:-integration_test}"

# ── Firebaseエミュレータを起動（既に動いていればそれを使う）──
if nc -z 127.0.0.1 8080 2>/dev/null; then
  echo "▶ Firebaseエミュレータは既に起動しています"
else
  echo "▶ Firebaseエミュレータを起動します"
  firebase emulators:start --only auth,firestore,storage --project "$PROJECT_ID" \
    > /tmp/firebase-emulator.log 2>&1 &
  emulator_pid=$!

  # スクリプト終了時に確実に落とす
  trap 'kill "$emulator_pid" 2>/dev/null || true' EXIT

  echo -n "  起動待ち"
  for _ in $(seq 1 60); do
    if nc -z 127.0.0.1 8080 2>/dev/null && nc -z 127.0.0.1 9099 2>/dev/null; then
      break
    fi
    echo -n "."
    sleep 2
  done
  echo ""

  if ! nc -z 127.0.0.1 8080 2>/dev/null; then
    echo "✗ Firebaseエミュレータが起動しませんでした。ログ: /tmp/firebase-emulator.log"
    exit 1
  fi
fi

# ── 結合テストを実行 ──
# USE_FIREBASE_EMULATOR=true を渡さないとテスト側が起動を拒否する（本番保護）。
echo "▶ 結合テストを実行: $TARGET"
flutter test "$TARGET" \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  --reporter expanded
