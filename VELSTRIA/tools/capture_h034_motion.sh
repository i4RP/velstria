#!/bin/bash
# H034 ゴルムの待機・歩行・走行・通常攻撃・スキルを実際の RealityKit 再生で録る（ギャラリー + 練習場の実攻撃）。
# 使い方（VELSTRIA/ で、Debug のシミュレータビルドの後）:
#   tools/capture_h034_motion.sh <VELSTRIA.app> <出力ディレクトリ> [ラベル]
# 例: tools/capture_h034_motion.sh build/H034Derived/Build/Products/Debug-iphonesimulator/VELSTRIA.app build/h034-preview after
set -euo pipefail
cd "$(dirname "$0")/.."

app="$1"
out="$2"
label="${3:-h034}"
bundle="com.bitcoinpay.velstria"
mkdir -p "$out"
[[ -d "$app" ]] || { echo "Missing simulator app: $app" >&2; exit 1; }
udid="$(xcrun simctl create "vel-h034-$label" 'iPhone 17')"
recorder=""
cleanup() {
    if [[ -n "$recorder" ]]; then
        kill -INT "$recorder" 2>/dev/null || true
        wait "$recorder" 2>/dev/null || true
    fi
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl ui "$udid" appearance dark
xcrun simctl status_bar "$udid" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$udid" "$app"

record() {
    local name="$1" seconds="$2"
    xcrun simctl io "$udid" recordVideo --codec=h264 --force "$out/$label-$name.mp4" >"$out/$label-$name.log" 2>&1 &
    recorder=$!
    sleep "$seconds"
    kill -INT "$recorder"
    wait "$recorder"
    recorder=""
    [[ -s "$out/$label-$name.mp4" ]] || { echo "Empty capture: $name" >&2; exit 1; }
}

gallery() {
    xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
        -uiTesting -skipOnboarding -language en -heroGallery -galleryDetail H034 "$@"
}

gallery -galleryState idle
sleep 25
# state animation speed(sim units/s) yaw seconds
while read -r name state speed yaw seconds; do
    gallery -galleryState "$state" -gallerySpeed "$speed" -galleryYaw "$yaw"
    sleep 6
    record "$name" "$seconds"
done <<'EOF'
idle idle 0 25 8
walk run 120 90 8
run run 260 90 8
run-fast run 340 60 6
attack attack 0 60 10
skill1 skill1 0 60 5
skill2 skill2 0 60 5
ult ult 0 60 6
EOF

# 練習場: シムの実際の通常攻撃（命中の時刻はシム）とスキルで、移動 → 攻撃の切り替えも含めて録る。
xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
    -uiTesting -skipOnboarding -grant -language en -graphics medium -hero H034 -battle practice -efkAuto atk
sleep 40
record practice 25
