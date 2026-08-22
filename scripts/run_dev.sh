#!/usr/bin/env bash
# ローカル開発用の起動スクリプト。
#
# Gemini APIキーはCloud Functions（functions/src/index.ts の askGemini）へ
# 移設済みで、Dart側は GEMINI_API_KEY を読まない（README.md「3. Gemini
# APIキー取得」参照）。ローカルでのCloud Functionsエミュレータ実行に
# キーが要る場合は functions/.secret.local を使う。
set -euo pipefail
cd "$(dirname "$0")/.."

flutter run "$@"
