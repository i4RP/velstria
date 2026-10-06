#!/bin/bash
# スキル演出の目視確認（DEBUG の -skillDemo）。シミュレータで 1 スロットだけ実演し、録画から効果の山の前後を 16 コマのシートにする。
#
# usage: tools/skillfx/capture.sh <heroID> <slot 0-4> [pre秒=0.4] [post秒=1.4]
#   slot: 0 = パッシブ / 1 = S1 / 2 = S2 / 3 = S3 / 4 = 奥義
# 環境変数:
#   SKILLFX_UDID   使うシミュレータ（必須。xcrun simctl create で自分専用を作る）
#   SKILLFX_DD     DerivedData（既定 build/skillfx-dd）。先に build.sh でビルドしておく
#   SKILLFX_OUT    出力先（既定 build/skillfx-shots）
# 出力: $SKILLFX_OUT/sheet_<hero>_<slot>.png（Read で見る）
# 注意: シミュレータでは後処理のブルームが出ない（実機ではもっと光る）。
set -euo pipefail
cd "$(dirname "$0")/../.."
H=$1; S=$2; PRE=${3:-0.4}; POST=${4:-1.4}
: "${SKILLFX_UDID:?SKILLFX_UDID を設定}"
DD=${SKILLFX_DD:-build/skillfx-dd}; OUT=${SKILLFX_OUT:-build/skillfx-shots}
mkdir -p "$OUT"
APP=$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "*.app" | head -1)
BID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun simctl install "$SKILLFX_UDID" "$APP"
xcrun simctl launch --terminate-running-process "$SKILLFX_UDID" "$BID" -uiTesting -skipOnboarding -battle practice \
    -hero "$H" -graphics high -skillDemo -skillDemoSlot "$S" >/dev/null
sleep 11
MP4="$OUT/${H}_$S.mp4"
rm -f "$MP4"
xcrun simctl io "$SKILLFX_UDID" recordVideo --codec=h264 --force "$MP4" >/dev/null 2>&1 &
REC=$!
sleep 7
kill -INT $REC; wait $REC 2>/dev/null || true
PY=${SKILLFX_PYTHON:-python3}
"$PY" tools/skillfx/peak_sheet.py "$MP4" "$OUT/sheet_${H}_$S.png" "$PRE" "$POST"
