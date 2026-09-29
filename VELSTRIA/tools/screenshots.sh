#!/bin/bash
# App Store 用スクリーンショット（横画面）をシミュレータで撮影する。
#
# usage（どこから実行してもよい）:
#   tools/screenshots.sh                        # ビルド → 6.9" / 6.1" × 日英 × 全画面を撮影
#   tools/screenshots.sh --skip-build           # 既存の Release シミュレータビルドを使う
#   tools/screenshots.sh --lang en --only 04_battle_lanes
#   DEVICES="iPhone 17 Pro Max" tools/screenshots.sh
#
# 出力: build/screenshots/<デバイス>/<言語>/NN_name.png        製品ページ用（最大 10 枚）
#       build/screenshots/<デバイス>/<言語>/review/iap_*.png   App 内課金の審査用スクリーンショット
#   iPhone 17 Pro Max（6.9"）→ 2868×1320、iPhone 16e（6.1"）→ 2532×1170（App Store Connect の受付サイズ）
#
# 仕組み: 専用シミュレータ（vel-shots-*）を作成 → Release ビルドをインストール →
#   App/Core/DebugLaunch.swift の起動引数（-uiTesting 等）で各画面へ直行 → 撮影 →
#   縦向きのフレームバッファを横向きに回転 → 終了時にシミュレータを削除。
#   -uiTesting は一時ディレクトリのプロフィールを使うので、実データや他のシミュレータには触れない。
#   新規シミュレータは起動直後にシステムの通知バナー（「Apple Intelligence の準備ができました」等）を出すため、
#   撮影前に WAIT_WARMUP 秒アプリを起動したまま待ってバナーを流してから撮影する。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

DEVICE_LIST="${DEVICES:-iPhone 17 Pro Max,iPhone 16e}"
LANGS=(ja en)
SKIP_BUILD=0
ONLY=""
# シミュレータのフレームバッファは縦向き。横画面アプリを正立させる回転角（sips は時計回り）
ROTATE="${ROTATE:-270}"
# 画面表示・戦闘進行の待ち時間（秒）
WAIT_SCREEN="${WAIT_SCREEN:-5}"
WAIT_BATTLE_EARLY="${WAIT_BATTLE_EARLY:-35}"
WAIT_BATTLE_LATE="${WAIT_BATTLE_LATE:-120}"
# 新規シミュレータの初回通知バナーが消えるまでの待ち時間（秒）
WAIT_WARMUP="${WAIT_WARMUP:-45}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=1 ;;
        --lang) shift; LANGS=("$1") ;;
        --only) shift; ONLY="$1" ;;
        -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
        *) echo "error: 不明な引数 $1" >&2; exit 1 ;;
    esac
    shift
done

# 撮影する画面: 名前|起動引数|待ち時間
# App Store の並び順（最初の 3 枚が検索結果に出る）: 戦闘 → ホーム → ヒーロー → …
SHOTS=(
    "01_battle_teamfight|-grant -battle standard|$WAIT_BATTLE_LATE"
    "02_home||$WAIT_SCREEN"
    "03_heroes|-grant -route heroes|$WAIT_SCREEN"
    "04_battle_lanes|-grant -battle standard|$WAIT_BATTLE_EARLY"
    "05_hero_detail|-grant -route heroDetail:H003|$WAIT_SCREEN"
    "06_build_editor|-grant -route buildEditor:H003|$WAIT_SCREEN"
    "07_ranked|-route rankOverview|$WAIT_SCREEN"
    "08_skin_store|-route skinStore|$WAIT_SCREEN"
    "09_star_pass|-route starPass|$WAIT_SCREEN"
    "10_spectate|-battle spectate|$WAIT_BATTLE_LATE"
)
# App 内課金の審査用（製品ページには載せない。review/ に保存）
REVIEW_SHOTS=(
    "iap_currency_store|-route currencyStore|$WAIT_SCREEN"
    "iap_star_pass|-route starPass|$WAIT_SCREEN"
)

APP="$ROOT/.build/DerivedData/Build/Products/Release-iphonesimulator/VELSTRIA.app"
if [[ -n "$ONLY" ]] && ! printf '%s\n' "${SHOTS[@]}" "${REVIEW_SHOTS[@]}" | grep -q "^$ONLY|"; then
    echo "error: --only に指定した名前 \"$ONLY\" の撮影定義がありません" >&2
    exit 1
fi
BUNDLE_ID="com.velstria.game"
OUT="$ROOT/build/screenshots"
CREATED=()

cleanup() {
    for udid in "${CREATED[@]:-}"; do
        [[ -n "$udid" ]] || continue
        xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
        xcrun simctl delete "$udid" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

if [[ "$SKIP_BUILD" == "0" ]]; then
    echo "==> Release シミュレータビルド"
    xcodegen generate --quiet
    xcodebuild -project VELSTRIA.xcodeproj -scheme VELSTRIA -configuration Release \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$ROOT/.build/DerivedData" \
        build CODE_SIGNING_ALLOWED=NO -quiet
fi
[[ -d "$APP" ]] || { echo "error: $APP がありません（--skip-build を外して実行）" >&2; exit 1; }

# 1 枚撮影: <出力先ディレクトリ> <名前> <起動引数> <待ち秒> <言語> <ロケール>
capture() {
    local dir="$1" name="$2" args="$3" wait="$4" lang="$5" locale="$6"
    mkdir -p "$dir"
    # shellcheck disable=SC2086
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" \
        -uiTesting -skipOnboarding -language "$lang" \
        -AppleLanguages "($lang)" -AppleLocale "$locale" $args >/dev/null
    sleep "$wait"
    local raw="$dir/.$name.raw.png"
    xcrun simctl io "$udid" screenshot --type=png "$raw" >/dev/null 2>&1
    sips -r "$ROTATE" "$raw" --out "$dir/$name.png" >/dev/null
    rm -f "$raw"
    local w h
    w="$(sips -g pixelWidth "$dir/$name.png" | awk '/pixelWidth/ {print $2}')"
    h="$(sips -g pixelHeight "$dir/$name.png" | awk '/pixelHeight/ {print $2}')"
    if (( w <= h )); then
        echo "warning: $dir/$name.png が縦長です（${w}×${h}）。ROTATE を調整してください" >&2
    fi
    echo "  ${dir#"$OUT/"}/$name.png  ${w}×${h}"
}

IFS=',' read -r -a DEVICES_ARR <<< "$DEVICE_LIST"
for device in "${DEVICES_ARR[@]}"; do
    device="$(echo "$device" | sed 's/^ *//; s/ *$//')"
    slug="$(echo "$device" | tr ' ' '-')"
    if ! xcrun simctl list devicetypes | grep -q "^$device ("; then
        echo "error: デバイス種別 \"$device\" がありません（Xcode > Settings > Components でランタイムを追加）" >&2
        exit 1
    fi
    echo "==> $device"
    udid="$(xcrun simctl create "vel-shots-$slug" "$device" 2>/dev/null)"
    CREATED+=("$udid")
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl ui "$udid" appearance dark
    xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
        --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$APP"
    # 初回起動時のシステム通知バナーを撮影前に流す
    echo "  （初回通知バナー待ち ${WAIT_WARMUP} 秒）"
    xcrun simctl launch "$udid" "$BUNDLE_ID" -uiTesting -skipOnboarding >/dev/null
    sleep "$WAIT_WARMUP"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true

    for lang in "${LANGS[@]}"; do
        dir="$OUT/$slug/$lang"
        locale="ja_JP"; [[ "$lang" == "en" ]] && locale="en_US"
        for shot in "${SHOTS[@]}"; do
            IFS='|' read -r name args wait <<< "$shot"
            [[ -z "$ONLY" || "$ONLY" == "$name" ]] || continue
            capture "$dir" "$name" "$args" "$wait" "$lang" "$locale"
        done
        for shot in "${REVIEW_SHOTS[@]}"; do
            IFS='|' read -r name args wait <<< "$shot"
            [[ -z "$ONLY" || "$ONLY" == "$name" ]] || continue
            capture "$dir/review" "$name" "$args" "$wait" "$lang" "$locale"
        done
        xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    done
done

cat <<EOF

撮影完了: $OUT
次の手順:
  - すべての画像を目視確認（UI の欠け・デバッグ表示・ダミー文言・システムの通知バナーが無いこと）。
    バナーが写った場合は WAIT_WARMUP を増やすか、--only <名前> で撮り直す。
  - 戦闘画面は進行タイミングで構図が変わるので、良い構図が撮れなければ WAIT_BATTLE_EARLY / WAIT_BATTLE_LATE を調整して再撮影。
  - App Store Connect の「6.9 インチディスプレイ」に iPhone-17-Pro-Max、「6.1 インチ」に iPhone-16e をアップロード（docs/appstore/screenshots.md）。
  - review/iap_*.png は各 App 内課金の「審査用のスクリーンショット」に使う（docs/appstore/in_app_purchases.md）。
EOF
