#!/bin/bash
# Records real practice inputs and PerfReport. Use Release + SCREENSHOTS + TESTER_TOOLS for performance comparisons.
# Args: simulator app output [seconds >= 65] [H025|H028]
set -euo pipefail
udid=${1:?simulator UUID}
app=${2:?path to VELSTRIA.app}
out=${3:?output directory}
seconds=${4:-65}
hero=${5:-H025}
case "$hero" in H025|H028) ;; *) echo "Hero must be H025 or H028" >&2; exit 1 ;; esac
[[ "$seconds" =~ ^[0-9]+$ ]] && (( seconds >= 65 ))
mkdir -p "$out"
out=$(cd "$out" && pwd)
xcrun simctl install "$udid" "$app"
data=$(xcrun simctl get_app_container "$udid" com.bitcoinpay.velstria data)
report="$data/Documents/perf/perf-report.json"
rm -f "$report"
xcrun simctl launch --terminate-running-process \
    --stdout="$out/runtime.log" --stderr="$out/runtime.log" \
    "$udid" com.bitcoinpay.velstria \
    -uiTesting -skipOnboarding -grant -language en -battle practice -hero "$hero" \
    -practiceNoCD -practiceLevel 4 -efkAuto quality -perfRun "$seconds" -perfQuality medium \
    > "$out/launch.log"
xcrun simctl io "$udid" recordVideo --codec=h264 --force "$out/raw.mp4" > "$out/record.log" 2>&1 &
recorder=$!
trap 'kill -INT "$recorder" 2>/dev/null || true' EXIT
for ((i=0; i<seconds+120; i++)); do
    [[ -f "$report" ]] && break
    sleep 1
done
[[ -f "$report" ]]
kill -INT "$recorder"
wait "$recorder" || true
trap - EXIT
cp "$report" "$out/perf-report.json"
xcrun simctl io "$udid" screenshot "$out/final.png" > /dev/null 2>&1
dimensions=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$out/raw.mp4")
width=${dimensions%x*}
height=${dimensions#*x}
filter='scale=1600:-2'
if (( width < height )); then filter="transpose=${H025_CAPTURE_TRANSPOSE:-2},scale=1600:-2"; fi
ffmpeg -y -hide_banner -loglevel error -i "$out/raw.mp4" -vf "$filter" \
    -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -an "$out/review.mp4"
echo "$out/review.mp4"
