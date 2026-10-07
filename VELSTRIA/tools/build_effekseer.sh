#!/bin/bash
# Effekseer ランタイム（C++ / Metal）を iOS 向けにビルドして ThirdParty/Effekseer へ同梱する。
# 使い方: tools/build_effekseer.sh [runtime-cpp のパス]
#   既定のパス: ~/Library/Application Support/Effekseer/current/runtime-cpp（Effekseer の「EffekseerForCpp」を展開したもの）
# 出力: ThirdParty/Effekseer/{include, ios-arm64/libEffekseerAll.a, ios-arm64-simulator/libEffekseerAll.a}
# CI はこのスクリプトを実行しない（生成物をリポジトリへコミットしている。cmake 不要）。ランタイムを更新する時だけ手元で実行する。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$HOME/Library/Application Support/Effekseer/current/runtime-cpp}"
OUT="$ROOT/ThirdParty/Effekseer"
WORK="$(mktemp -d /tmp/efk-build.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

[[ -f "$SRC/CMakeLists.txt" ]] || { echo "error: $SRC に Effekseer の C++ ランタイムが見つかりません" >&2; exit 1; }
command -v cmake >/dev/null && command -v ninja >/dev/null || { echo "error: cmake と ninja が必要です（brew install cmake ninja）" >&2; exit 1; }

cp -R "$SRC" "$WORK/rt"

build() { # <名前> <SDK> <出力スライス>
    local name="$1" sdk="$2" slice="$3"
    cmake -S "$WORK/rt" -B "$WORK/b-$name" -G Ninja \
        -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_EXAMPLES=OFF -DBUILD_GL=OFF -DBUILD_METAL=ON -DUSE_OPENAL=OFF >/dev/null
    cmake --build "$WORK/b-$name" >/dev/null
    mkdir -p "$OUT/$slice"
    # 5 つの静的ライブラリを 1 つにまとめる（リンク設定を簡単にする）
    libtool -static -o "$OUT/$slice/libEffekseerAll.a" $(find "$WORK/b-$name" -name '*.a')
}

rm -rf "$OUT"
build device iphoneos ios-arm64
build sim iphonesimulator ios-arm64-simulator

# ヘッダ（ビルドに使うモジュールの公開ヘッダだけ。構造は元のまま）
mkdir -p "$OUT/include"
for d in Effekseer EffekseerRendererCommon EffekseerRendererMetal EffekseerRendererLLGI EffekseerMaterialCompiler 3rdParty/LLGI/src; do
    rsync -a --include='*/' --include='*.h' --include='*.hpp' --include='*.inl' --exclude='*' --prune-empty-dirs \
        "$SRC/src/$d" "$OUT/include/$(dirname "$d")/"
done
cp "$SRC/LICENSE.txt" "$OUT/LICENSE.txt"
echo "ok: $OUT"
du -sh "$OUT"/*
