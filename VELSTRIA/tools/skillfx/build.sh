#!/bin/bash
# スキル演出の確認用の Debug ビルド（シミュレータ）。usage: SKILLFX_UDID=... tools/skillfx/build.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${SKILLFX_UDID:?SKILLFX_UDID を設定}"
DD=${SKILLFX_DD:-build/skillfx-dd}
[ -d VELSTRIA.xcodeproj ] || xcodegen generate --quiet
xcodebuild -project VELSTRIA.xcodeproj -scheme VELSTRIA -configuration Debug -destination "id=$SKILLFX_UDID" \
    -derivedDataPath "$DD" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -40
