#!/bin/bash
# スキル演出の比較撮影（CI の .github/workflows/fx-capture.yml から。手元の Mac でもビルド済みなら動く）。
# シミュレータを起動してアプリを入れ、カメラの組（PRESETS）× ヒーロー（HEROES）ごとに練習場を -fxCapture で起動し、
# 書き出した画像と目録（manifest.json）を build/fxcapture/<組>/<ヒーロー>/ へ集める。
#   環境変数: HEROES（空白区切り）・PRESETS（legacy / mlbb）・LEVEL（練習場の開始レベル、既定 4）・APP（.app の場所）
set -euo pipefail
cd "$(dirname "$0")/../.."
BID=com.bitcoinpay.velstria
APP="${APP:-build/dd/Build/Products/Debug-iphonesimulator/VELSTRIA.app}"
HEROES="${HEROES:-H025 H026 H027 H028 H029 H030 H031 H032 H033 H034}"
PRESETS="${PRESETS:-legacy mlbb}"
LEVEL="${LEVEL:-4}"
OUT=build/fxcapture
mkdir -p "$OUT"
HS=/tmp/velstria-fxcap
ROTATE="${ROTATE:-270}"
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
best = None
for rt, devs in d.items():
    if "iOS" not in rt:
        continue
    for x in devs:
        if x["name"] == "iPhone 17":
            best = x["udid"]
print(best or "")')
[[ -n "$UDID" ]] || { echo "error: iPhone 17 のシミュレータが無い" >&2; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
for preset in $PRESETS; do
  first=1
  for hero in $HEROES; do
    xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
    DATA="$(xcrun simctl get_app_container "$UDID" "$BID" data)"
    rm -rf "$DATA/Documents/fxcapture" "$HS"
    mkdir -p "$HS"
    extra=()
    if [[ $first == 1 ]]; then extra=(-fxCaptureRings); fi
    first=0
    echo "==> $preset $hero"
    xcrun simctl launch "$UDID" "$BID" -uiTesting -skipOnboarding -grant -graphics high -battle practice -hero "$hero" \
      -practiceNoCD -practiceLevel "$LEVEL" -cameraPreset "$preset" -fxCapture all ${extra[@]+"${extra[@]}"} -fxCaptureExit >/dev/null
    # アプリは撮る時刻に止めて $HS/request（<ヒーロー>/<名前>）を書く → 画面を撮って $HS/done を置く（FXCapture.handshake）
    dest="$OUT/$preset/$hero"
    mkdir -p "$dest"
    ok=0
    deadline=$((SECONDS + 480))
    while (( SECONDS < deadline )); do
      if [[ -f "$HS/request" ]]; then
        name="$(cat "$HS/request")"
        rm -f "$HS/request"
        raw="$HS/raw.png"
        rm -f "$raw"
        xcrun simctl io "$UDID" screenshot --type=png "$raw" >/dev/null 2>&1 || true
        if [[ -f "$raw" ]]; then
          w="$(sips -g pixelWidth "$raw" | awk '/pixelWidth/ {print $2}')"
          h="$(sips -g pixelHeight "$raw" | awk '/pixelHeight/ {print $2}')"
          # 横向きのアプリでも画面の撮影が縦長なら回す（tools/screenshots.sh と同じ ROTATE）
          if (( h > w )); then sips -r "$ROTATE" "$raw" --out "$HS/rot.png" >/dev/null 2>&1; else cp "$raw" "$HS/rot.png"; fi
          sips -s format jpeg -s formatOptions 88 -Z 1108 "$HS/rot.png" --out "$dest/$(basename "$name").jpg" >/dev/null 2>&1 || true
        fi
        touch "$HS/done"
      fi
      if [[ -f "$DATA/Documents/fxcapture/$hero/manifest.json" ]]; then ok=1; break; fi
      sleep 0.1
    done
    if [[ $ok == 1 ]]; then
      cp -R "$DATA/Documents/fxcapture/$hero/." "$dest/"
      echo "    $(ls "$dest" | wc -l | tr -d ' ') files"
    else
      echo "    error: $hero の撮影が終わらない（480 秒）" >&2
      [[ -d "$DATA/Documents/fxcapture/$hero" ]] && cp -R "$DATA/Documents/fxcapture/$hero/." "$dest/" || true
      xcrun simctl io "$UDID" screenshot "$OUT/$preset/${hero}_timeout.png" >/dev/null 2>&1 || true
    fi
    xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  done
done
