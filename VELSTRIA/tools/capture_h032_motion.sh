#!/bin/bash
# H032 の待機・歩行・走行・通常攻撃・練習試合を実際の RealityKit 再生で録画する（シミュレータ。実機 FPS の根拠にはしない）。
# usage: tools/capture_h032_motion.sh <VELSTRIA.app> <出力ディレクトリ> [ラベル]
set -euo pipefail
cd "$(dirname "$0")/.."
app="$1"; out="$2"; tag="${3:-H032}"
bundle="com.bitcoinpay.velstria"
mkdir -p "$out"
udid="$(xcrun simctl create "vel-$tag-motion" 'iPhone 17')"
recorder=""
cleanup() {
    [[ -n "$recorder" ]] && { kill -INT "$recorder" 2>/dev/null || true; wait "$recorder" 2>/dev/null || true; }
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl ui "$udid" appearance dark
xcrun simctl install "$udid" "$app"
record() {
    xcrun simctl io "$udid" recordVideo --codec=h264 --force "$out/$1.mp4" >/dev/null 2>&1 &
    recorder=$!; sleep "$2"; kill -INT "$recorder"
    # 高負荷時は INT で止まらないことがある: 15 秒待って強制終了
    for _ in $(seq 30); do kill -0 "$recorder" 2>/dev/null || break; sleep 0.5; done
    kill -9 "$recorder" 2>/dev/null || true; wait "$recorder" 2>/dev/null || true; recorder=""
}
launch() { xcrun simctl launch --terminate-running-process "$udid" "$bundle" -uiTesting -skipOnboarding -language ja "$@" >/dev/null; }
launch -heroGallery -galleryDetail H032 -galleryState idle
sleep 25
for spec in "idle idle 0 8" "walk run 120 8" "run run 400 8" "attack attack 0 12" "s1 skill1 0 7" "s2 skill2 0 7" "ult ult 0 8"; do
    set -- $spec
    launch -heroGallery -galleryDetail H032 -galleryState "$2" -gallerySpeed "$3" -galleryYaw 60
    sleep 7
    record "$tag-$1" "$4"
done
launch -grant -graphics medium -hero H032 -battle practice
sleep 35
record "$tag-practice" "${PRACTICE_SECONDS:-30}"
