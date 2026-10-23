#!/bin/bash
# Same sequence/camera/lights for each stage; owns no user simulator.
# Usage: capture_h025_quality.sh <booted simulator UUID> <app> <output dir> [close]
set -euo pipefail
udid="$1"
app="$2"
out="$3"
mode="${4:-battle}"
handshake=/tmp/velstria-h025-review
bundle=com.bitcoinpay.velstria
mkdir -p "$out" "$handshake"
rm -f "$handshake/ready.json" "$handshake/done.json" "$handshake/go"
xcrun simctl install "$udid" "$app"
args=(-uiTesting -skipOnboarding -language en -heroGallery -heroQualityReview)
if [[ "$mode" == close ]]; then args+=(-heroReviewClose); fi
xcrun simctl launch --terminate-running-process "$udid" "$bundle" "${args[@]}" > "$out/launch.log"
for ((i=0;i<180;i++)); do
    [[ -f "$handshake/ready.json" ]] && break
    sleep 1
done
[[ -f "$handshake/ready.json" ]] || { echo 'Review did not become ready' >&2; exit 1; }
cp "$handshake/ready.json" "$out/manifest.json"
xcrun simctl io "$udid" screenshot "$out/idle.png" > "$out/screenshot.log" 2>&1
xcrun simctl io "$udid" recordVideo --codec=h264 --force "$out/raw.mp4" > "$out/record.log" 2>&1 &
recorder=$!
cleanup() { kill -INT "$recorder" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1
touch "$handshake/go"
for ((i=0;i<100;i++)); do
    [[ -f "$handshake/done.json" ]] && break
    sleep 1
done
[[ -f "$handshake/done.json" ]] || { echo 'Review did not complete' >&2; exit 1; }
kill -INT "$recorder"
wait "$recorder" || true
trap - EXIT
cp "$handshake/done.json" "$out/completed.json"
git rev-parse HEAD > "$out/commit.txt"
xcodebuild -version > "$out/environment.txt"
shasum -a 256 "$app/Hero_H025.usdz" "$app/H025MotionClips.json" > "$out/assets.sha256"
# Simulator's video is portrait storage; normalize orientation, preserving scale.
ffmpeg -y -hide_banner -loglevel error -i "$out/raw.mp4" -vf 'transpose=2,scale=1600:-2' \
    -c:v libx264 -crf 18 -pix_fmt yuv420p -an "$out/review.mp4"
echo "$out/review.mp4"
