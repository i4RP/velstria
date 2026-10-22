#!/bin/bash
# H029 の実際の RealityKit 再生を撮る（ギャラリーの単体プレビュー + 練習場の実戦）。シミュレータの映像は実機 FPS の根拠にならない。
#   bash tools/capture_h029_motion.sh <VELSTRIA.app> <出力ディレクトリ> [ラベル]
# Debug のシミュレータビルドを渡す。専用のシミュレータを作って撮り、終わったら消す。
set -euo pipefail
cd "$(dirname "$0")/.."
app="$1"; out="$2"; tag="${3:-H029}"
bundle="com.bitcoinpay.velstria"
mkdir -p "$out"
[[ -d "$app" ]] || { echo "Missing simulator app: $app" >&2; exit 1; }
udid="$(xcrun simctl create "vel-h029-$tag-$$" "iPhone 17")"
recorder=""
cleanup() {
    if [[ -n "$recorder" ]]; then kill -INT "$recorder" 2>/dev/null || true; wait "$recorder" 2>/dev/null || true; fi
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl ui "$udid" appearance dark
xcrun simctl status_bar "$udid" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$udid" "$app"
record() {
    local label="$1" seconds="$2"
    xcrun simctl io "$udid" recordVideo --codec=h264 --force "$out/$label.mp4" >"$out/$label-record.log" 2>&1 &
    recorder=$!
    sleep "$seconds"
    kill -INT "$recorder"
    for _ in $(seq 1 40); do kill -0 "$recorder" 2>/dev/null || break; sleep 0.5; done
    kill -9 "$recorder" 2>/dev/null || true; wait "$recorder" 2>/dev/null || true; recorder=""
    [[ -s "$out/$label.mp4" ]] || { echo "Empty capture: $label" >&2; exit 1; }
}
# 撮り済み（中断前）の動画は撮り直さない。高負荷でコマが落ちた（15 fps 未満・4 秒未満・壊れた）動画は撮り直す
have() {
    local f="$out/$tag-$1.mp4" v
    [[ -s "$f" ]] || return 1
    v=$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames,duration -of csv=p=0 "$f" 2>/dev/null) || v=""
    python3 -c "import sys; d,n=sys.argv[1].split(',')[:2]; sys.exit(0 if float(d)>=4 and float(n)/float(d)>=15 else 1)" "$v" 2>/dev/null
}
gallery() { xcrun simctl launch --terminate-running-process "$udid" "$bundle" -uiTesting -skipOnboarding -language en \
    -heroGallery -galleryDetail H029 "$@" >/dev/null; }
gallery -galleryState idle
sleep 25
# ギャラリー: 待機・歩行（1.0 m/s）・走行（基本 2.6 m/s）・通常攻撃・スキル（-galleryState を繰り返す）
for spec in "idle idle 330 10" "walk run 100 8" "run run 260 8" "attack attack 330 12" "skill1 skill1 330 8" "skill2 skill2 330 8" "ult ult 330 8"; do
    set -- $spec
    for yaw in 0 90; do
        have "gallery-$1-$yaw" && continue
        gallery -galleryState "$2" -gallerySpeed "$3" -galleryYaw "$yaw"
        sleep 7
        record "$tag-gallery-$1-$yaw" "$4"
    done
done
# 練習場: 人形へ近づいて 2 秒ごとに通常攻撃・スキル（実際の sim の命中・突進・詠唱）
for what in atk s1 s2 ult; do
    have "practice-$what" && continue
    xcrun simctl launch --terminate-running-process "$udid" "$bundle" -uiTesting -skipOnboarding -grant -language en \
        -graphics medium -hero H029 -battle practice -efkAuto "$what" >/dev/null
    sleep 30
    record "$tag-practice-$what" 16
done
xcodebuild -version > "$out/environment.txt"
printf '%s\n' "Debug / iPhone 17 simulator ($(xcrun simctl list runtimes | grep -m1 iOS)) / real RealityKit player." \
    'Simulator footage is not evidence of physical-device FPS.' >> "$out/environment.txt"
