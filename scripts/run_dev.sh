#!/usr/bin/env bash
# ローカル開発用の起動スクリプト。
#
# Gemini APIキーはCloud Functions（functions/src/index.ts の askGemini）へ
# 移設済みで、Dart側はもう GEMINI_API_KEY を読まない（README.md「3. Gemini
# APIキー取得」参照）。.env.local が無くても起動できるようにしてあるが、
# 過去との互換のため .env.local に値があれば引き続き --dart-define で渡す
# （渡しても実質無害）。
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env.local ]; then
  set -a
  source .env.local
  set +a
fi

if [ -n "${GEMINI_API_KEY:-}" ]; then
  flutter run --dart-define=GEMINI_API_KEY="$GEMINI_API_KEY" "$@"
else
  flutter run "$@"
fi
