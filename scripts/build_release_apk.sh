#!/usr/bin/env bash
# リリースAPKビルド用スクリプト。.env.local からAPIキーを読み込み、
# --dart-defineでFlutterに渡す（ソースにキーを書かないため）。
# CI環境ではGEMINI_API_KEYが環境変数として既に設定されている想定で、
# .env.local が無くても環境変数があればそのまま使う。
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env.local ]; then
  set -a
  source .env.local
  set +a
fi

if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "GEMINI_API_KEY が設定されていません（.env.local または環境変数）。" >&2
  exit 1
fi

flutter build apk --release --dart-define=GEMINI_API_KEY="$GEMINI_API_KEY" "$@"
