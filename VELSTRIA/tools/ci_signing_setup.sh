#!/bin/bash
# CI 用: 配布証明書（p12）を一時キーチェーンへ取り込み、App Store プロファイルを配置する。
# 環境変数（GitHub Secrets から）:
#   CI_DIST_P12_BASE64     配布証明書 + 秘密鍵の p12（base64）
#   CI_DIST_P12_PASSWORD   p12 のパスワード
#   CI_PROFILE_BASE64      App Store プロビジョニングプロファイル（base64）
#   RUNNER_TEMP            作業ディレクトリ（GitHub Actions が設定。ローカル検証時は任意のディレクトリ）
# 後片付けは tools/ci_signing_cleanup.sh。
set -euo pipefail

: "${CI_DIST_P12_BASE64:?}" "${CI_DIST_P12_PASSWORD:?}" "${CI_PROFILE_BASE64:?}"
WORK="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="$WORK/velstria-ci.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"

umask 077
printf '%s' "$CI_DIST_P12_BASE64" | base64 --decode > "$WORK/dist.p12"
printf '%s' "$CI_PROFILE_BASE64" | base64 --decode > "$WORK/profile.mobileprovision"

# 一時キーチェーン（ロック解除・自動ロック無効）に取り込み、codesign から無確認で使えるようにする
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/dist.p12" -k "$KEYCHAIN" -P "$CI_DIST_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# 既存の検索リストの先頭に追加（元のリストは後片付けで戻す）
security list-keychains -d user | tr -d '"' | sed 's/^ *//' > "$WORK/keychains.before"
security list-keychains -d user -s "$KEYCHAIN" $(cat "$WORK/keychains.before")
rm -f "$WORK/dist.p12"

# プロファイルを UUID 名で配置（Xcode 26 は UserData、旧来の MobileDevice の両方を見る）
UUID="$(security cms -D -i "$WORK/profile.mobileprovision" | plutil -extract UUID raw -o - -)"
NAME="$(security cms -D -i "$WORK/profile.mobileprovision" | plutil -extract Name raw -o - -)"
for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
    mkdir -p "$dir"
    cp "$WORK/profile.mobileprovision" "$dir/$UUID.mobileprovision"
done
echo "$UUID" > "$WORK/profile.uuid"
echo "$KEYCHAIN" > "$WORK/keychain.path"

security find-identity -v -p codesigning "$KEYCHAIN"
echo "プロファイル: $NAME ($UUID)"
