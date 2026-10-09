#!/bin/bash
# 戦闘の性能計測（シミュレータ）。観戦モードの決定論的な試合（seed 20261001）を指定秒プレイし、
# フレーム時間の分布・ヒッチ・プレイ中のアセット生成（AssetLedger）・読み込み時間を JSON で受け取る。
#
# usage（VELSTRIA/ で実行）:
#   tools/perf_run.sh                         # Release（SCREENSHOTS 付き）をビルドして 150 秒計測
#   tools/perf_run.sh --skip-build --seconds 90 --quality high --out build/perf/after.json
#   tools/perf_run.sh --speed 4 --seconds 150 # 4 倍速で試合後半（巨像 8:00 など）まで回す
#
# 注意: シミュレータの GPU は実機と別物なので、描画負荷の絶対値ではなく
#   「メインスレッドの詰まり（work・ヒッチ）」と「プレイ中のアセット生成 0 件」を比べる用途に使う。
#   実機の確認は同じ起動引数（-battle spectate -perfRun 150）で Xcode から起動し、Instruments の
#   Animation Hitches / Points of Interest（category Battle）と合わせて見る。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

SECONDS_TO_RUN=150
SPEED=1
QUALITY=""
DEVICE="iPhone 17 Pro"
OUT=""
SKIP_BUILD=0
CONFIG=Release
while [[ $# -gt 0 ]]; do
    case "$1" in
        --seconds) SECONDS_TO_RUN="$2"; shift 2 ;;
        --speed) SPEED="$2"; shift 2 ;;
        --quality) QUALITY="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --debug) CONFIG=Debug; shift ;;
        *) echo "error: 不明な引数 $1" >&2; exit 1 ;;
    esac
done

DERIVED="$ROOT/.build/PerfDerivedData"
APP="$DERIVED/Build/Products/$CONFIG-iphonesimulator/VELSTRIA.app"
BUNDLE_ID="com.bitcoinpay.velstria"

if [[ "$SKIP_BUILD" == "0" ]]; then
    echo "==> $CONFIG シミュレータビルド（SCREENSHOTS で起動引数を有効化）"
    xcodegen generate --quiet
    xcodebuild -project VELSTRIA.xcodeproj -scheme VELSTRIA -configuration "$CONFIG" \
        -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$DERIVED" \
        build ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SCREENSHOTS' -quiet
fi
[[ -d "$APP" ]] || { echo "error: $APP がありません（--skip-build を外す）" >&2; exit 1; }

UDID="$(xcrun simctl create "velstria-perf-$$" "$DEVICE")"
cleanup() {
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"

ARGS=(-uiTesting -skipOnboarding -battle spectate -perfRun "$SECONDS_TO_RUN" -perfSpeed "$SPEED" -perfExit)
if [[ -n "$QUALITY" ]]; then
    ARGS+=(-perfQuality "$QUALITY")
fi
echo "==> 計測: $DEVICE / $CONFIG / ${SECONDS_TO_RUN}s × ${SPEED} 倍速 ${QUALITY:+/ 画質 $QUALITY}"
# 起動直後の通知バナー・初回のシステム処理が落ち着くまで待ってから起動する
sleep 20
LOG="${PERF_LOG:-$(mktemp)}"
xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$BUNDLE_ID" "${ARGS[@]}" > "$LOG" 2>&1 &
LAUNCH_PID=$!
DEADLINE=$(( $(date +%s) + SECONDS_TO_RUN + 240 ))
while kill -0 "$LAUNCH_PID" 2>/dev/null; do
    if (( $(date +%s) > DEADLINE )); then
        kill "$LAUNCH_PID" 2>/dev/null || true
        echo "error: 時間内に計測が終わりませんでした" >&2
        tail -20 "$LOG" >&2
        exit 1
    fi
    sleep 2
done

DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
REPORT="$DATA/Documents/perf/perf-report.json"
[[ -f "$REPORT" ]] || { echo "error: 計測結果がありません" >&2; tail -20 "$LOG" >&2; exit 1; }
if [[ -n "$OUT" ]]; then
    mkdir -p "$(dirname "$OUT")"
    cp "$REPORT" "$OUT"
    echo "==> 保存: $OUT"
fi
python3 - "$REPORT" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
f, l = r["frame"], r["ledger"]
print(f"device {r['device']} iOS {r['os']} {r['build']} quality={r['quality']} {r['frameRate']}fps speed×{r['speed']}")
print(f"load {r['loadMs']:.0f} ms (warmup {r['warmupMs']:.0f} ms, {r['warmupFrames']} frames)  peak {r['peakFootprintMB']:.0f} MB, entities {r['peakEntities']}")
print(f"frame p50 {f['p50Ms']:.1f} p95 {f['p95Ms']:.1f} p99 {f['p99Ms']:.1f} max {f['maxMs']:.1f} ms  hitches {f['hitches']} ({f['hitchRatio']:.1f} ms/s)")
print(f"work  p50 {f['workP50Ms']:.2f} p95 {f['workP95Ms']:.2f} p99 {f['workP99Ms']:.2f} max {f['workMaxMs']:.1f} ms  (sim {f['simAvgMs']:.2f} sync {f['syncAvgMs']:.2f} overlay {f['overlayAvgMs']:.2f})")
for name, sample in sorted((r.get('syncWork') or {}).items()):
    print(f"  {name}: avg {sample['totalMs'] / max(1, sample['calls']):.3f} ms, max {sample['maxMs']:.2f} ms")
print(f"assets created while live: {sum(l['live'].values())} {l['live']}  (loading: {l['loading']})")
for s in l["liveSamples"][:20]:
    print("   ", s)
PY
