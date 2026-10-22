#!/bin/bash
# H028 ザイルの実際の RealityKit の再生をスクリーンショットで撮る（ギャラリーの単体表示 + 練習モードで sim の通常攻撃・スキル）。
# 使い方（VELSTRIA/ で）: bash tools/capture_h028_motion.sh [<VELSTRIA.app>] [<出力の接頭辞>] [<シミュレータの UDID>]
#   既定の app は build/H028Derived の Debug シミュレータ版。変更前（main）の app を渡せば比較用に同じ条件で撮れる。
#   UDID を省くと使い捨てのシミュレータを作って消す（並行作業のシミュレータと取り合わない）。
# シミュレータの画像は実機の FPS の根拠にならない。
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:-$(pwd)/build/H028Derived/Build/Products/Debug-iphonesimulator/VELSTRIA.app}"
label="${2:-after}"
udid="${3:-}"
out="$(pwd)/build/h028-preview/$label"
bundle="com.bitcoinpay.velstria"
mkdir -p "$out"
[[ -d "$app" ]] || { echo "シミュレータ版の app が無い: $app" >&2; exit 1; }
own=0
if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl create "vel-h028-$label" 'iPhone 17 Pro')"
    own=1
    xcrun simctl boot "$udid"
fi
cleanup() {
    if [[ "$own" == 1 ]]; then
        xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
        xcrun simctl delete "$udid" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl ui "$udid" appearance dark
xcrun simctl status_bar "$udid" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$udid" "$app"

launch() { xcrun simctl launch --terminate-running-process "$udid" "$bundle" -uiTesting -skipOnboarding -language ja "$@" >/dev/null; }
shots() {
    local name="$1" count="$2" gap="$3"
    for i in $(seq 1 "$count"); do
        xcrun simctl io "$udid" screenshot "$out/$name-$i.png" >/dev/null 2>&1
        sleep "$gap"
    done
}

# 初回起動の案内を消す
launch -heroGallery -galleryDetail H028 -galleryState idle
sleep 25

# ギャラリー: 待機・歩行（100 = 1 m/s）・走行（260 = H028 の移動速度）・通常攻撃・S1・S2・ULT（正面と側面）
for spec in "idle idle 330" "walk run 100" "run run 260" "attack attack 330" "s1 skill1 330" "s2 skill2 330" "ult ult 330"; do
    read -r name state speed <<<"$spec"
    for yaw in 0 90; do
        launch -heroGallery -galleryDetail H028 -galleryState "$state" -gallerySpeed "$speed" -galleryYaw "$yaw"
        sleep 8
        shots "gallery-$name-$yaw" 4 0.23
    done
done

# 練習モード: sim が人形へ近づいて撃つ（通常攻撃の命中・S1・S2・ULT の時刻は sim のまま）
for what in atk s1 s2 ult; do
    launch -grant -graphics medium -hero H028 -battle practice -practiceNoCD -practiceLevel 15 -efkAuto "$what"
    sleep 30
    shots "practice-$what" 8 0.4
done

git rev-parse HEAD > "$out/commit.txt"
{ xcodebuild -version; xcrun simctl list devices | sed -n "/$udid/p"
  echo "Debug / iPhone 17 Pro シミュレータ / 実際の RealityKit の再生。シミュレータの画像は実機の FPS の根拠にならない。"; } > "$out/environment.txt"
