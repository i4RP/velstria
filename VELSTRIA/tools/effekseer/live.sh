#!/bin/bash
# 実際の戦闘（練習）で、ヒーローが人形へ通常攻撃 / スキルを撃ち続ける様子を録画し、コマに切り出す。
# usage: tools/effekseer/live.sh <heroID> <atk|s1|s2|ult> [録画秒=14] [fps=5]
#   出力: /tmp/efk-live/<hero>_<mode>/f_NN.png と sheet.png（全コマのタイル）
set -euo pipefail
HERO="$1"; MODE="$2"; SECS="${3:-14}"; FPS="${4:-5}"
SIM="${SIM:-booted}"; BID=com.bitcoinpay.velstria
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="/tmp/efk-live/${HERO}_${MODE}"; rm -rf "$OUT"; mkdir -p "$OUT"
APP="$(xcrun simctl get_app_container "$SIM" "$BID" app)"
rsync -a --delete "$ROOT/Effects/Effekseer/" "$APP/Effekseer/"
xcrun simctl terminate "$SIM" "$BID" 2>/dev/null || true
xcrun simctl launch "$SIM" "$BID" -uiTesting -skipOnboarding -grant -battle practice -hero "$HERO" -practiceNoCD -practiceLevel 12 -efkAuto "$MODE" >/dev/null
sleep "${WARM:-16}"; sleep "${WAIT:-0}"
xcrun simctl io "$SIM" recordVideo --codec h264 --force "$OUT/v.mp4" >/dev/null 2>&1 &
REC=$!
sleep "$SECS"
kill -INT "$REC" 2>/dev/null || true
for _ in $(seq 1 20); do kill -0 "$REC" 2>/dev/null || break; sleep 0.25; done
kill -TERM "$REC" 2>/dev/null || true
ffmpeg -y -loglevel error -i "$OUT/v.mp4" -vf "fps=$FPS" "$OUT/f_%03d.png"
echo "$OUT ($(ls "$OUT"/f_*.png | wc -l) frames)"
