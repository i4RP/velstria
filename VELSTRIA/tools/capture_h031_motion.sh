#!/bin/bash
# Capture the actual RealityKit player, using existing debug gallery/practice routes.
# Run after a Debug simulator build into build/H031Derived.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$(pwd)/build/h031-preview"
app="$(pwd)/build/H031Derived/Build/Products/Debug-iphonesimulator/VELSTRIA.app"
bundle="com.bitcoinpay.velstria"
mkdir -p "$out"
[[ -d "$app" ]] || { echo "Missing simulator app: $app" >&2; exit 1; }
udid="$(xcrun simctl create vel-h031-motion 'iPhone 17')"
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
    kill -INT "$recorder"
    wait "$recorder"
    recorder=""
    xcrun simctl io "$udid" screenshot "$out/$label.png"
    [[ -s "$out/$label.mp4" ]] || { echo "Empty capture: $label" >&2; exit 1; }
}

# Warm up the new simulator so system setup banners are gone before capturing.
xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
    -uiTesting -skipOnboarding -language en -heroGallery -galleryDetail H031 -galleryState idle
sleep 30

for state in idle walk run attack skill1 skill2 ult; do
    animation="$state"
    speed=250
    seconds=10
    if [[ "$state" == attack ]]; then seconds=15; fi
    if [[ "$state" == walk ]]; then animation=run; speed=100; fi
    yaws="0 90"
    if [[ "$state" == skill* || "$state" == ult ]]; then yaws="35"; fi
    for yaw in $yaws; do
        xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
            -uiTesting -skipOnboarding -language en -heroGallery \
            -galleryDetail H031 -galleryState "$animation" -gallerySpeed "$speed" -galleryYaw "$yaw"
        sleep 8
        record "H031-$state-$yaw" "$seconds"
    done
done

# The practice controller fires real simulated attacks, allowing visual release
# to be compared with actual projectile creation rather than a gallery-only loop.
xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
    -uiTesting -skipOnboarding -grant -language en -graphics medium \
    -hero H031 -battle practice -efkAuto atk
sleep 40
record H031-practice-release 70

git rev-parse HEAD > "$out/commit.txt"
xcodebuild -version > "$out/environment.txt"
xcrun simctl list devices | sed -n "/$udid/p" >> "$out/environment.txt"
printf '%s\n' 'Debug / iPhone 17 simulator / real RealityKit player.' \
    'Simulator footage is not evidence of physical-device FPS.' >> "$out/environment.txt"
