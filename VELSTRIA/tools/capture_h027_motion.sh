#!/bin/bash
# H027 ジャルドの実機のプレイヤー（RealityKit）をシミュレータで撮る: ギャラリーの待機・歩行・走行・通常攻撃・スキル（正面と横）と、
# 練習場の実戦（ゲームの見下ろしのカメラ、sim の時刻）。docs/H027_QUALITY.md の比較に使う。シミュレータの FPS は実機の証拠にしない。
# build/H027Derived に Debug のシミュレータ用ビルドがある前提（.github/workflows/h027-motion-preview.yml）。
set -euo pipefail
cd "$(dirname "$0")/.."

out="$(pwd)/build/h027-preview"
app="$(pwd)/build/H027Derived/Build/Products/Debug-iphonesimulator/VELSTRIA.app"
bundle="com.bitcoinpay.velstria"
mkdir -p "$out"
[[ -d "$app" ]] || { echo "Missing simulator app: $app" >&2; exit 1; }
udid="$(xcrun simctl create vel-h027-motion 'iPhone 17')"
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
    local label="$1" seconds="$2"
    xcrun simctl io "$udid" recordVideo --codec=h264 --force "$out/$label.mp4" \
        >"$out/$label-record.log" 2>&1 &
    recorder=$!
    sleep "$seconds"
    kill -INT "$recorder" 2>/dev/null || true
    # recordVideo が終わらないことがある（11-05 の h027prev-pass2 は 55 分止まってジョブの上限で切られた）。10 秒待って止める
    for _ in $(seq 1 20); do kill -0 "$recorder" 2>/dev/null || break; sleep 0.5; done
    kill -9 "$recorder" 2>/dev/null || true
    wait "$recorder" 2>/dev/null || true
    recorder=""
    xcrun simctl io "$udid" screenshot "$out/$label.png" || true
    echo "captured $label ($(stat -f%z "$out/$label.mp4" 2>/dev/null || echo 0) bytes)"
}

xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
    -uiTesting -skipOnboarding -language en -heroGallery -galleryDetail H027 -galleryState idle
sleep 30

# ギャラリー: 走りは子龍の 265 + 靴（MLBB の訓練場の歩き 毎秒 2.7〜2.9）、歩きは減速された時の 130
for state in idle walk run attack skill1 skill2 ult; do
    animation="$state"
    speed=285
    seconds=8
    if [[ "$state" == attack ]]; then seconds=16; fi
    if [[ "$state" == walk ]]; then animation=run; speed=130; fi
    for yaw in 0 90; do
        xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
            -uiTesting -skipOnboarding -language en -heroGallery \
            -galleryDetail H027 -galleryState "$animation" -gallerySpeed "$speed" -galleryYaw "$yaw"
        sleep 8
        record "H027-$state-$yaw" "$seconds"
    done
done

# 練習場: 通常の入力で人形へ近づいて撃つ（sim の時刻。2 秒ごと）。quality は通常攻撃・全スキル・移動を巡回する
for what in atk s1 s2 ult quality; do
    seconds=15
    if [[ "$what" == atk || "$what" == quality ]]; then seconds=25; fi
    xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
        -uiTesting -skipOnboarding -grant -language en -graphics medium \
        -hero H027 -battle practice -efkAuto "$what"
    sleep 40
    record "H027-practice-$what" "$seconds"
done

git rev-parse HEAD > "$out/commit.txt"
xcodebuild -version > "$out/environment.txt"
xcrun simctl list devices | sed -n "/$udid/p" >> "$out/environment.txt"
printf '%s\n' 'Debug / iPhone 17 simulator / real RealityKit player.' \
    'Simulator footage is not evidence of physical-device FPS.' >> "$out/environment.txt"
