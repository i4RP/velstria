#!/bin/bash
# tools/archive.sh で作ったアーカイブ（build/VELSTRIA.xcarchive）を App Store Connect へアップロードする（TestFlight 配信用）。
# 前提: App Store Connect に Bundle ID のアプリレコードがあること、Xcode にチームのアカウントでサインイン済みであること。
#
# usage:
#   TEAM_ID=BPZ8375UX5 BUILD_NUMBER=3 ALLOW_APP_PLACEHOLDERS=1 tools/archive.sh   # 先にアーカイブ
#   tools/upload_testflight.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ARCHIVE="build/VELSTRIA.xcarchive"
OPTIONS="build/ExportOptions-upload.plist"

[[ -d "$ARCHIVE" ]] || { echo "error: $ARCHIVE がありません。先に tools/archive.sh を実行してください" >&2; exit 1; }
[[ -f build/ExportOptions.plist ]] || { echo "error: build/ExportOptions.plist がありません（tools/archive.sh が作成）" >&2; exit 1; }

cp build/ExportOptions.plist "$OPTIONS"
plutil -replace destination -string upload "$OPTIONS"

PLIST="$ARCHIVE/Products/Applications/VELSTRIA.app/Info.plist"
echo "==> アップロード: $(plutil -extract CFBundleIdentifier raw "$PLIST") $(plutil -extract CFBundleShortVersionString raw "$PLIST") ($(plutil -extract CFBundleVersion raw "$PLIST"))"
# App Store Connect API キーがあればそれで認証（無ければ Xcode にサインイン済みのアカウント）
AUTH=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
    KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
    AUTH=(-authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
    echo "==> 認証: App Store Connect API キー $ASC_KEY_ID"
fi
rm -rf build/upload
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath build/upload \
        -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}; then
    cat >&2 <<'EOF'

error: アップロードに失敗しました。
  "Error Downloading App Information" の場合: App Store Connect にこの Bundle ID のアプリレコードがありません。
  App Store Connect →「アプリ」→「＋」→「新規アプリ」で作成してから再実行してください。
  "already been uploaded" の場合: BUILD_NUMBER を増やして tools/archive.sh からやり直してください。
EOF
    exit 1
fi
echo "==> 完了。App Store Connect の処理（10〜30 分）後に TestFlight の内部テストで配信できます。"
