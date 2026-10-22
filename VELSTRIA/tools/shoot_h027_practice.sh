#!/bin/bash
# 練習場（実際の sim のスキル・通常攻撃）で H027 を連続スクリーンショット（動画は撮らない）。
# 使い方: tools/shoot_h027_practice.sh <UDID> <atk|s1|s2|ult> [枚数]
set -euo pipefail
cd "$(dirname "$0")/.."
udid="$1"; what="$2"; count="${3:-48}"
out="$(pwd)/build/h027-preview/practice"
mkdir -p "$out"
rm -f "$out/raw_${what}_"*.png
xcrun simctl launch --terminate-running-process "$udid" com.bitcoinpay.velstria -uiTesting -skipOnboarding -grant -language en \
    -graphics medium -hero H027 -battle practice -efkAuto "$what" >/dev/null
sleep "${WAIT:-38}"
for i in $(seq -w 0 $((count - 1))); do
    xcrun simctl io "$udid" screenshot "$out/raw_${what}_$i.png" >/dev/null 2>&1
done
