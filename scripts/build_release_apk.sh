#!/usr/bin/env bash
# リリースAPKビルド用スクリプト。
#
# Gemini APIキーはCloud Functions（functions/src/index.ts の askGemini）へ
# 移設済みで、Dart側は GEMINI_API_KEY を読まない（README.md「3. Gemini
# APIキー取得」参照）。
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build apk --release "$@"
