#!/bin/bash
# スキル演出の比較撮影（CI の .github/workflows/fx-capture.yml から。手元の Mac でもビルド済みなら動く）。
# シミュレータを起動してアプリを入れ、カメラの組（PRESETS）× ヒーロー（HEROES）ごとに練習場を -fxCapture で起動し、
# 書き出した画像と目録（manifest.json）を build/fxcapture/<組>/<ヒーロー>/ へ集める。
#   環境変数: HEROES（空白区切り）・PRESETS（legacy / mlbb）・LEVEL（練習場の開始レベル、既定 4）・APP（.app の場所）・
#            PROBE（1 なら -fxCaptureProbe）・ROTATE（縦長の画面の撮影を回す角度、既定 270）・
#            MOTION（1 なら全身のモーションの確認: 細かい時刻・体の横が見える向き・通常攻撃も撮る）
# アプリは撮る時刻に止めて $HS/request（<ヒーロー>/<名前>）を書く → 画面を撮って $HS/done に同じ名前を書く（FXCapture.handshake）。
# 起動直後にアプリが落ちる（CI のシミュレータで音声の初期化が固まる AURemoteIO の RPC timeout）ことがあるので、落ちたら 3 回まで起動し直す。
set -euo pipefail
export LC_ALL=en_US.UTF-8
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
REPORTS="$HOME/Library/Logs/DiagnosticReports"
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

# 1 回分の撮影。0 = 目録ができた、1 = 落ちた（新しい落ちた時の記録がある）、2 = 時間切れ
capture_once() {
  local preset="$1" hero="$2" dest="$3" log="$4"; shift 4
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  DATA="$(xcrun simctl get_app_container "$UDID" "$BID" data)"
  rm -rf "$DATA/Documents/fxcapture" "$HS"
  mkdir -p "$HS"
  touch "$HS/start"
  xcrun simctl launch --stdout="$log" --stderr="$log" "$UDID" "$BID" -uiTesting -skipOnboarding -grant -graphics high \
    -battle practice -hero "$hero" -practiceNoCD -practiceLevel "$LEVEL" -cameraPreset "$preset" -fxCapture all \
    "$@" -fxCaptureExit >/dev/null
  local deadline=$((SECONDS + 480)) tick=0
  while (( SECONDS < deadline )); do
    if [[ -f "$HS/request" ]]; then
      local name raw="$HS/raw.png"
      name="$(cat "$HS/request")"
      rm -f "$HS/request" "$raw"
      xcrun simctl io "$UDID" screenshot --type=png "$raw" >/dev/null 2>&1 || true
      if [[ -f "$raw" ]]; then
        local w h
        w="$(sips -g pixelWidth "$raw" | awk '/pixelWidth/ {print $2}')"
        h="$(sips -g pixelHeight "$raw" | awk '/pixelHeight/ {print $2}')"
        # 横向きのアプリでも画面の撮影が縦長なら回す（tools/screenshots.sh と同じ ROTATE）
        if (( h > w )); then sips -r "$ROTATE" "$raw" --out "$HS/rot.png" >/dev/null 2>&1; else cp "$raw" "$HS/rot.png"; fi
        sips -s format jpeg -s formatOptions 88 -Z 1108 "$HS/rot.png" --out "$dest/$(basename "$name").jpg" >/dev/null 2>&1 || true
      fi
      printf "%s" "$name" > "$HS/done"
    fi
    if [[ -f "$DATA/Documents/fxcapture/$hero/manifest.json" ]]; then return 0; fi
    tick=$((tick + 1))
    if (( tick % 20 == 0 )) && [[ -n "$(find "$REPORTS" -iname 'VELSTRIA*' -newer "$HS/start" 2>/dev/null | head -1)" ]]; then
      find "$REPORTS" -iname 'VELSTRIA*' -newer "$HS/start" -exec cp {} "$dest/" \; 2>/dev/null || true
      return 1
    fi
    sleep 0.1
  done
  return 2
}

for preset in $PRESETS; do
  first=1
  for hero in $HEROES; do
    extra=()
    if [[ $first == 1 ]]; then extra=(-fxCaptureRings); fi
    if [[ -n "${PROBE:-}" ]]; then extra+=(-fxCaptureProbe); fi
    if [[ -n "${MOVING:-}" ]]; then extra+=(-fxCaptureMovingParticles); fi
    if [[ -n "${MOTION:-}" ]]; then
      extra+=(-fxCaptureTimes "0,0.05,0.1,0.15,0.2,0.25,0.3,0.35,0.45,0.55,0.65,0.8,0.95,1.1,1.3,1.6,1.85,2.05,2.3"
              -fxCaptureSide -fxCaptureAttack)
    fi
    # 判定の形の線（HitShapeOverlay。撮影では既定で出す）を出さない
    if [[ -n "${NOHITSHAPES:-}" ]]; then extra+=(-noHitShapes); fi
    first=0
    dest="$OUT/$preset/$hero"
    mkdir -p "$dest"
    status=2
    for attempt in 1 2 3; do
      echo "==> ${preset} ${hero}（${attempt} 回目）"
      log="$PWD/$OUT/$preset/${hero}.log"
      set +e
      capture_once "$preset" "$hero" "$dest" "$log" ${extra[@]+"${extra[@]}"}
      status=$?
      set -e
      [[ $status == 1 ]] && { echo "    アプリが落ちた（記録は ${dest}）。起動し直す"; continue; }
      break
    done
    if [[ $status == 0 ]]; then
      cp -R "$DATA/Documents/fxcapture/$hero/." "$dest/"
      echo "    $(ls "$dest" | wc -l | tr -d ' ') files"
    else
      echo "    error: ${hero} の撮影が終わらない（status ${status}）" >&2
      [[ -d "$DATA/Documents/fxcapture/$hero" ]] && cp -R "$DATA/Documents/fxcapture/$hero/." "$dest/" || true
      xcrun simctl io "$UDID" screenshot "$OUT/$preset/${hero}_timeout.png" >/dev/null 2>&1 || true
    fi
    xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  done
done
