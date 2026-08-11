#!/usr/bin/env bash
# ローカル開発用の起動スクリプト。.env.local からAPIキーを読み込み、
# --dart-defineでFlutterに渡す（ソースにキーを書かないため）。
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env.local ]; then
  echo ".env.local が見つかりません。.env.local.example をコピーして値を入れてください。" >&2
  exit 1
fi

set -a
source .env.local
set +a

if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "GEMINI_API_KEY が .env.local に設定されていません。" >&2
  exit 1
fi

flutter run --dart-define=GEMINI_API_KEY="$GEMINI_API_KEY" "$@"
