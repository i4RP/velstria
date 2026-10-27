#!/bin/bash
# Repeatable full-detail first-person capture. Pass an explicitly owned simulator.
# Usage: tools/vision_review.sh SIMULATOR_UUID APP_PATH OUTPUT_DIRECTORY
set -euo pipefail
udid="${1:?simulator UUID required}"
app="${2:?app path required}"
out="${3:?output directory required}"
mkdir -p "$out"
git rev-parse HEAD > "$out/base-commit.txt"
git diff --binary > "$out/working.patch"
xcrun simctl list devices booted > "$out/device.txt"
xcrun simctl install "$udid" "$app"
xcrun simctl launch --terminate-running-process "$udid" com.bitcoinpay.velstria \
  -uiTesting -skipOnboarding -battle practice -hero H003 -graphics high -stageFull \
  -perfRun 65 -perfQuality high -visualReview > "$out/launch.txt"
# Allow full stage preparation, then record the real drawable (never a mockup).
# The perf report is written after 65 seconds of battle, excluding loading.
data="$(xcrun simctl get_app_container "$udid" com.bitcoinpay.velstria data)"
report="$data/Documents/perf/perf-report.json"
# A previous run's report must not count as this capture.
rm -f "$report"
for ((attempt=0; attempt<180; attempt++)); do
  if [[ -f "$report" ]]; then break; fi
  sleep 2
done
[[ -f "$report" ]] || { echo 'Battle did not finish 65 seconds of measurement' >&2; exit 1; }
xcrun simctl io "$udid" screenshot "$out/raw.png"
sips -r 270 "$out/raw.png" --out "$out/battle.png" >/dev/null
cp "$report" "$out/perf-report.json"
python3 - "$out/perf-report.json" <<'PYREPORT'
import json, sys
report = json.load(open(sys.argv[1]))
print("Capture quality:", report["quality"])
for note in report["notes"]:
    if note.startswith(("quality at", "visual review:")):
        print(note)
if not any(note.startswith("visual review:") for note in report["notes"]):
    raise SystemExit("Rebuild with the visualReview capture hook before comparing")
print("Live asset allocations:", report["ledger"]["live"])
PYREPORT
echo "Saved $out/battle.png (review image and perf-report.json before accepting)."
