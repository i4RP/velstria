#!/bin/bash
# H027 の実際の RealityKit 再生のスクリーンショット（動画は撮らない）。ギャラリーの各状態を等間隔で撮り、横向きに直して並べる。
# 使い方: tools/shoot_h027_motion.sh <UDID> [states...]   先に Debug のシミュレータ版をインストールしておく。
set -euo pipefail
cd "$(dirname "$0")/.."
udid="$1"; shift
states="${*:-idle run attack s1 s2 ult}"
out="$(pwd)/build/h027-preview/shots"
bundle="com.bitcoinpay.velstria"
mkdir -p "$out"
for state in $states; do
    speed=265
    [[ "$state" == walk ]] && { anim=run; speed=110; } || anim="$state"
    xcrun simctl launch --terminate-running-process "$udid" "$bundle" -uiTesting -skipOnboarding -language en -heroGallery \
        -galleryDetail H027 -galleryState "$anim" -gallerySpeed "$speed" -galleryYaw "${YAW:-30}" >/dev/null
    sleep 9
    for i in 0 1 2 3 4 5 6 7; do
        xcrun simctl io "$udid" screenshot "$out/raw_${state}_$i.png" >/dev/null 2>&1
        sleep "${GAP:-0.12}"
    done
    ffmpeg -v error -y -pattern_type glob -i "$out/raw_${state}_*.png" \
        -vf "transpose=2,crop=1100:1000:250:120,scale=330:-1,tile=4x2" -frames:v 1 "$out/H027_${state}.png"
done
