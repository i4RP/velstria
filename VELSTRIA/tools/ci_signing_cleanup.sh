#!/bin/bash
# tools/ci_signing_setup.sh の後片付け（キーチェーン検索リストを戻し、一時キーチェーンとプロファイルを削除）。
set -uo pipefail

WORK="${RUNNER_TEMP:?RUNNER_TEMP（setup と同じ作業ディレクトリ）を指定してください}"
if [[ -f "$WORK/keychains.before" ]]; then
    security list-keychains -d user -s $(cat "$WORK/keychains.before")
fi
if [[ -f "$WORK/keychain.path" ]]; then
    security delete-keychain "$(cat "$WORK/keychain.path")" 2>/dev/null || true
fi
if [[ -f "$WORK/profile.uuid" ]]; then
    UUID="$(cat "$WORK/profile.uuid")"
    rm -f "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$UUID.mobileprovision" \
          "$HOME/Library/MobileDevice/Provisioning Profiles/$UUID.mobileprovision"
fi
rm -f "$WORK/profile.mobileprovision" "$WORK/dist.p12" "$WORK/keychains.before" "$WORK/keychain.path" "$WORK/profile.uuid"
echo "署名の後片付け完了"
