#!/bin/bash
# Capture the actual RealityKit player, using existing debug gallery/practice routes.
# Run after a Debug simulator build into build/H033Derived.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$(pwd)/build/h033-preview"
app="$(pwd)/build/H033Derived/Build/Products/Debug-iphonesimulator/VELSTRIA.app"
bundle="com.bitcoinpay.velstria"
mkdir -p "$out"
[[ -d "$app" ]] || { echo "Missing simulator app: $app" >&2; exit 1; }
udid="$(xcrun simctl create vel-h033-motion 'iPhone 17')"
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
    -uiTesting -skipOnboarding -language en -heroGallery -galleryDetail H033 -galleryState idle
sleep 30

for state in idle walk run attack skill1 skill2 ult; do
    animation="$state"
    speed=330
    seconds=10
    if [[ "$state" == attack ]]; then seconds=20; fi
    if [[ "$state" == walk ]]; then animation=run; speed=100; fi
    for yaw in 0 90; do
        xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
            -uiTesting -skipOnboarding -language en -heroGallery \
            -galleryDetail H033 -galleryState "$animation" -gallerySpeed "$speed" -galleryYaw "$yaw"
        sleep 8
        record "H033-$state-$yaw" "$seconds"
    done
done

# Practice: real simulated attacks / skills against the dummy (gameplay timing, auto-cast every 2 s).
for what in atk s1 s2 ult; do
    seconds=15
    if [[ "$what" == atk ]]; then seconds=25; fi
    xcrun simctl launch --terminate-running-process "$udid" "$bundle"         -uiTesting -skipOnboarding -grant -language en -graphics medium         -hero H033 -battle practice -efkAuto "$what"
    sleep 40
    record "H033-practice-$what" "$seconds"
done

git rev-parse HEAD > "$out/commit.txt"
xcodebuild -version > "$out/environment.txt"
xcrun simctl list devices | sed -n "/$udid/p" >> "$out/environment.txt"
printf '%s\n' 'Debug / iPhone 17 simulator / real RealityKit player.' \
    'Simulator footage is not evidence of physical-device FPS.' >> "$out/environment.txt"
