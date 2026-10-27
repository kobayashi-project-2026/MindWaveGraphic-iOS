#!/usr/bin/env bash
# iOS アプリのロジック（Contracts / 分析 / ナビゲーション / 履歴 / InsightProvider）の自動テストを実行する。
#
# Xcode プロジェクト（project.pbxproj）を変更せずに済むよう、アプリのソース（@main を除く）と
# Tests/MindWaveCoreTests/*.swift を swiftc で iOS シミュレーター向け実行ファイルとしてビルドし、
# `xcrun simctl spawn` で起動中のシミュレーター上で実行する。
#
# 使い方:
#   scripts/run_ios_core_tests.sh            # 起動中のシミュレーターを自動選択
#   SIM_UDID=<UDID> scripts/run_ios_core_tests.sh
#
# 終了コード: 0 = 全テスト成功 / 1 = 失敗あり / 2 = ビルド・環境エラー
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$ROOT/MindWaveGraphic/MindWaveGraphic"
TEST_SRC="$ROOT/Tests/MindWaveCoreTests"
OUT_DIR="${TMPDIR:-/tmp}/mindwave-core-tests"
mkdir -p "$OUT_DIR"

# プロジェクト設定（IPHONEOS_DEPLOYMENT_TARGET / SWIFT_* ）と揃える
IOS_TARGET="${IOS_TARGET:-26.4}"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"

SIM_UDID="${SIM_UDID:-$(xcrun simctl list devices booted | grep -Eo '\(([0-9A-F-]{36})\) \(Booted\)' | head -1 | grep -Eo '[0-9A-F-]{36}' || true)}"
if [[ -z "$SIM_UDID" ]]; then
  echo "[core-tests] 起動中のシミュレーターがありません。Simulator.app で iPhone を起動してください。" >&2
  exit 2
fi

# @main を持つ App 構造体はテスト用 main と衝突するため除外する
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(
  find "$APP_SRC" -name '*.swift' ! -name 'MindWaveGraphicApp.swift' -print0
)
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find "$TEST_SRC" -name '*.swift' -print0)

echo "[core-tests] compiling ${#SOURCES[@]} files for ${ARCH}-apple-ios${IOS_TARGET}-simulator"
if ! xcrun swiftc \
  -sdk "$SDK_PATH" \
  -target "${ARCH}-apple-ios${IOS_TARGET}-simulator" \
  -swift-version 5 \
  -default-isolation MainActor \
  -enable-upcoming-feature MemberImportVisibility \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -D DEBUG -Onone \
  -module-name MindWaveGraphic \
  -o "$OUT_DIR/MindWaveCoreTests" \
  "${SOURCES[@]}" 2> "$OUT_DIR/build.log"; then
  grep -E "error:" "$OUT_DIR/build.log" | head -40 >&2
  echo "[core-tests] ビルド失敗（全ログ: $OUT_DIR/build.log）" >&2
  exit 2
fi

echo "[core-tests] running on simulator $SIM_UDID"
xcrun simctl spawn "$SIM_UDID" "$OUT_DIR/MindWaveCoreTests"
