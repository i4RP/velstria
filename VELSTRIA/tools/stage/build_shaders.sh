#!/bin/bash
# ステージのシェーダー（tools/stage/shaders/StageShaders.metal）を metallib にコンパイルする。
#
# usage（どこから実行してもよい）: tools/stage/build_shaders.sh
#
# 出力:
#   App/Resources/Stage/StageShaders-ios.metallib   実機（iOS 18+）
#   App/Resources/Stage/StageShaders-sim.metallib   シミュレータ
#   App/Resources/Stage/StageShaders.sha256         ソースのハッシュ（テストが古い metallib を検出する）
#   build/stage/StageShaders-mac.metallib           macOS（見た目確認のハーネス用。アプリには入れない）
#
# アプリのターゲットで .metal をコンパイルしないのは、CI の Xcode に Metal Toolchain が無くてもビルドを通すため。
# Metal Toolchain が無いときは `xcodebuild -downloadComponent MetalToolchain` で入れる。
set -euo pipefail
cd "$(dirname "$0")/../.."
SRC=tools/stage/shaders/StageShaders.metal
OUT=App/Resources/Stage
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT" build/stage

build() { # sdk triple-flag out
    local sdk=$1 flag=$2 out=$3
    xcrun -sdk "$sdk" metal -c "$SRC" -o "$TMP/$sdk.air" $flag -ffast-math -Wall
    xcrun -sdk "$sdk" metallib "$TMP/$sdk.air" -o "$out"
    echo "$out ($(wc -c < "$out" | tr -d ' ') bytes)"
}
build iphoneos -mios-version-min=18.0 "$OUT/StageShaders-ios.metallib" & p1=$!
build iphonesimulator -mios-simulator-version-min=18.0 "$OUT/StageShaders-sim.metallib" & p2=$!
build macosx -mmacosx-version-min=15.0 build/stage/StageShaders-mac.metallib & p3=$!
fail=0
for p in $p1 $p2 $p3; do wait "$p" || fail=1; done
[ "$fail" = 0 ] || { echo "error: シェーダーのコンパイルに失敗" >&2; exit 1; }
shasum -a 256 "$SRC" | awk '{print $1}' > "$OUT/StageShaders.sha256"
echo "sha256 $(cat "$OUT/StageShaders.sha256")"
