#!/bin/bash
# ステージの見た目確認: シミュレータで観戦モードを起動し、地図の名所でスクリーンショットを撮る。
#
# usage: tools/stage/stage_shots.sh <UDID> <出力ディレクトリ> [x,y[,zoom] ...] [-- 追加の起動引数]
#   位置を省略すると docs/STAGE.md の名所（青の拠点・上レーン・中央・川・ボスの巣・ジャングル）。
#   アプリは DerivedData（STAGE_APP、既定 /tmp/vel-stage-dd の Debug ビルド）から入れる。
#   環境変数 WAIT（起動後の待ち、既定 22 秒）、GRAPHICS（low/medium/high、既定 medium）。
set -euo pipefail
UDID=$1; OUT=$2; shift 2
SPOTS=(); EXTRA=()
while [[ $# -gt 0 ]]; do
    if [[ $1 == "--" ]]; then shift; EXTRA=("$@"); break; fi
    SPOTS+=("$1"); shift
done
[[ ${#SPOTS[@]} -eq 0 ]] && SPOTS=("16,18" "14,60" "42,42" "60,60" "83,37" "56,30")
APP=${STAGE_APP:-/tmp/vel-stage-dd/Build/Products/Debug-iphonesimulator/VELSTRIA.app}
WAIT=${WAIT:-22}
mkdir -p "$OUT"
xcrun simctl install "$UDID" "$APP"
for s in "${SPOTS[@]}"; do
    xcrun simctl terminate "$UDID" com.bitcoinpay.velstria >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" com.bitcoinpay.velstria -uiTesting -skipOnboarding -graphics "${GRAPHICS:-medium}" \
        -battle spectate -stageFull -stageCam "$s" ${EXTRA[@]+"${EXTRA[@]}"} >/dev/null
    sleep "$WAIT"
    f="$OUT/stage_${s//,/_}.png"
    xcrun simctl io "$UDID" screenshot "$f" >/dev/null 2>&1
    # シミュレータのフレームバッファは縦向き → 横画面へ回転して縮小
    sips -r 270 "$f" --out "$f" >/dev/null && sips -Z 1600 "$f" >/dev/null
    echo "$f"
done
xcrun simctl terminate "$UDID" com.bitcoinpay.velstria >/dev/null 2>&1 || true
