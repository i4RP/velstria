#!/bin/bash
# Effekseer の効果をシミュレータの戦闘画面で再生し、コマ送りで撮ってタイルにまとめる。
# usage: tools/effekseer/preview.sh <効果名[,効果名…]> [コマ数=8] [切り出し 列数=4]
#   環境変数: FRAMES_STEP=進めるフレーム数(既定 4) / FRAMES_TOTAL=1 つの効果の総フレーム(既定 コマ数×step) / YAW=度 / AHEAD=m / HERO=H003
#   事前に: Debug ビルドをシミュレータへ simctl install 済みであること。効果は Effects/Effekseer を毎回バンドルへコピーして読む（再ビルド不要）。
#   出力: /tmp/efk-preview/sheet_<名前>.png（効果ごと 1 枚）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NAMES="$1"; SHOTS="${2:-8}"; COLS="${3:-4}"
STEP="${FRAMES_STEP:-4}"; TOTAL="${FRAMES_TOTAL:-$((SHOTS * STEP))}"
HERO="${HERO:-H003}"; YAW="${YAW:-0}"; AHEAD="${AHEAD:-0}"
SIM="${SIM:-booted}"; BID=com.bitcoinpay.velstria
OUTDIR="${OUTDIR:-/tmp/efk-preview}"; mkdir -p "$OUTDIR"
CROP="${CROP:-700 800 850 250}"   # 高さ 幅 y x（スクリーンショット上のヒーロー付近）
APP="$(xcrun simctl get_app_container "$SIM" "$BID" app)"
rsync -a --delete "$ROOT/Effects/Effekseer/" "$APP/Effekseer/"
xcrun simctl terminate "$SIM" "$BID" 2>/dev/null || true
rm -f /tmp/efk-advance
xcrun simctl launch "$SIM" "$BID" -uiTesting -skipOnboarding -grant -battle practice -hero "$HERO" \
    -efkDemo "$NAMES" -efkFrames "$TOTAL" -efkStep "$STEP" -efkYaw "$YAW" -efkAhead "$AHEAD" >/dev/null
sleep "${WARM:-14}"
IFS=',' read -ra LIST <<< "$NAMES"
PER=$(( TOTAL / STEP + 2 ))   # 開始の 1 コマ + 進めた分 + 次へ切り替える 1 回
for name in "${LIST[@]}"; do
    rm -f "$OUTDIR/${name}_"*.png "$OUTDIR/c_${name}_"*.png
    for i in $(seq 0 $(( TOTAL / STEP ))); do
        touch /tmp/efk-advance
        for _ in $(seq 1 100); do [[ -e /tmp/efk-advance ]] || break; sleep 0.05; done
        sleep "${SETTLE:-0.3}"
        xcrun simctl io "$SIM" screenshot "$OUTDIR/${name}_$(printf %02d "$i").png" >/dev/null 2>&1
    done
    # 次の効果へ切り替える合図（frames を過ぎさせる）
    touch /tmp/efk-advance; for _ in $(seq 1 100); do [[ -e /tmp/efk-advance ]] || break; sleep 0.05; done
    set -- $CROP
    for f in "$OUTDIR/${name}_"[0-9][0-9].png; do
        sips -c "$1" "$2" --cropOffset "$3" "$4" "$f" --out "$OUTDIR/c_$(basename "$f")" >/dev/null 2>&1
    done
    n=$(ls "$OUTDIR/c_${name}_"*.png | wc -l | tr -d ' '); rows=$(( (n + COLS - 1) / COLS ))
    ffmpeg -y -loglevel error -pattern_type glob -i "$OUTDIR/c_${name}_*.png" -vf "scale=iw*0.5:ih*0.5,tile=${COLS}x${rows}" -frames:v 1 "$OUTDIR/sheet_${name}.png"
    echo "$OUTDIR/sheet_${name}.png"
done
