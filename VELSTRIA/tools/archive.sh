#!/bin/bash
# App Store 提出用のアーカイブと .ipa を作成する。アップロードは行わない（人が確認してから手動で行う）。
#
# usage（どこから実行してもよい）:
#   TEAM_ID=ABCDE12345 tools/archive.sh
#   TEAM_ID=ABCDE12345 BUILD_NUMBER=7 tools/archive.sh      # ビルド番号を上書き（App Store Connect では毎回増やす）
#   TEAM_ID=ABCDE12345 STRICT=1 tools/archive.sh            # 提出直前: メタデータのプレースホルダ残りもエラーにする
#
# 出力:
#   build/VELSTRIA.xcarchive   アーカイブ（dSYM 含む）
#   build/export/VELSTRIA.ipa  App Store Connect 用 .ipa
#
# 前提: Xcode にチームのアカウントでサインイン済み（自動署名で配布証明書・プロファイルを取得する）。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

if [[ -z "${TEAM_ID:-}" ]]; then
    cat >&2 <<'EOF'
error: TEAM_ID が設定されていません。
  Apple Developer の Membership 画面に表示される 10 桁の Team ID を指定してください。
  例: TEAM_ID=ABCDE12345 tools/archive.sh
  （Team ID はリポジトリに書き込まない。project.yml の DEVELOPMENT_TEAM は空のまま運用する）
EOF
    exit 1
fi
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "error: TEAM_ID の形式が不正です（英大文字・数字 10 桁）: $TEAM_ID" >&2
    exit 1
fi
if [[ -n "${BUILD_NUMBER:-}" && ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "error: BUILD_NUMBER は数字（例 7 / 1.0.7）で指定してください: $BUILD_NUMBER" >&2
    exit 1
fi

for tool in xcodegen xcodebuild python3 plutil sips; do
    command -v "$tool" >/dev/null || { echo "error: $tool が見つかりません" >&2; exit 1; }
done

ARCHIVE="$ROOT/build/VELSTRIA.xcarchive"
EXPORT_DIR="$ROOT/build/export"
EXPORT_OPTIONS="$ROOT/build/ExportOptions.plist"
DERIVED="$ROOT/.build/DerivedData"

step() { printf '\n==> %s\n' "$*"; }

# 1) 提出前チェック（失敗したらアーカイブしない）
step "提出前チェック"
python3 tools/gen_master_en.py --check
python3 tools/gen_master_ja.py --check
python3 tools/privacy_audit.py
if [[ "${STRICT:-0}" == "1" ]]; then
    python3 tools/validate_appstore_metadata.py --release
else
    python3 tools/validate_appstore_metadata.py
fi
ICON="App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
if [[ "$(sips -g hasAlpha "$ICON" | awk '/hasAlpha/ {print $2}')" != "no" ]]; then
    echo "error: $ICON にアルファチャンネルがあります（App Store のアイコンは不透明であること）。swift tools/make_icon.swift で再生成" >&2
    exit 1
fi

# 2) プロジェクト生成
step "xcodegen generate"
xcodegen generate --quiet

# 3) アーカイブ
step "xcodebuild archive (Release)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$ROOT/build"
ARCHIVE_ARGS=(
    -project VELSTRIA.xcodeproj
    -scheme VELSTRIA
    -configuration Release
    -destination "generic/platform=iOS"
    -archivePath "$ARCHIVE"
    -derivedDataPath "$DERIVED"
    -allowProvisioningUpdates
    DEVELOPMENT_TEAM="$TEAM_ID"
)
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    ARCHIVE_ARGS+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
fi
xcodebuild archive "${ARCHIVE_ARGS[@]}"

# 4) 書き出し（Team ID を入れた一時コピーを使う。元の plist は編集しない）
step "xcodebuild -exportArchive (app-store-connect / export only)"
cp ExportOptions-AppStore.plist "$EXPORT_OPTIONS"
plutil -replace teamID -string "$TEAM_ID" "$EXPORT_OPTIONS"
if [[ "$(plutil -extract destination raw "$EXPORT_OPTIONS")" != "export" ]]; then
    echo "error: ExportOptions の destination が export ではありません（自動アップロードは禁止）" >&2
    exit 1
fi
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates

# 5) 成果物の確認
step "成果物の確認"
IPA="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -n 1)"
[[ -n "$IPA" ]] || { echo "error: .ipa が書き出されていません" >&2; exit 1; }
APP_PLIST="$ARCHIVE/Products/Applications/VELSTRIA.app/Info.plist"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP_PLIST")"
DSYM_COUNT="$(find "$ARCHIVE/dSYMs" -maxdepth 1 -name '*.dSYM' | wc -l | tr -d ' ')"
[[ "$DSYM_COUNT" -gt 0 ]] || { echo "error: dSYM がアーカイブに含まれていません" >&2; exit 1; }
[[ -f "$ARCHIVE/Products/Applications/VELSTRIA.app/PrivacyInfo.xcprivacy" ]] \
    || { echo "error: PrivacyInfo.xcprivacy がアプリに含まれていません" >&2; exit 1; }

cat <<EOF

アーカイブ完了（アップロードはしていません）
  バージョン : $VERSION ($BUILD)
  アーカイブ : $ARCHIVE
  .ipa       : $IPA
  dSYM       : $DSYM_COUNT 個

次の手順（docs/APPSTORE.md「提出手順」）:
  1. Xcode > Window > Organizer でアーカイブを選び「Validate App」で検証する。
  2. 問題がなければ Organizer の「Distribute App」> App Store Connect > Upload、
     または Transporter.app に $IPA をドラッグしてアップロードする。
  3. App Store Connect で処理完了後、TestFlight の内部テストで起動・課金（Sandbox）を確認する。
  4. docs/appstore/release_checklist.md をすべて満たしてから審査へ提出する。
  5. 次回のアップロードでは BUILD_NUMBER を増やす（同じバージョン・ビルド番号は再アップロードできない）。
EOF
