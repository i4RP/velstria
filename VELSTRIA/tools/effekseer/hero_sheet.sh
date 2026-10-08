#!/bin/bash
# ヒーローの効果をいくつか撮って、1 枚の縦長シートにまとめる。
# usage: tools/effekseer/hero_sheet.sh <heroID> <段,段,…> [コマ数=8] [step=4]   例: hero_sheet.sh H020 s1_impact,ult_impact 10 4
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERO="$1"; STAGES="$2"; SHOTS="${3:-8}"; STEP="${4:-4}"
NAMES=$(echo "$STAGES" | tr ',' '\n' | sed "s/^/${HERO}_/" | paste -sd, -)
HERO="$HERO" FRAMES_STEP="$STEP" CROP="${CROP:-900 1000 750 150}" "$ROOT/tools/effekseer/preview.sh" "$NAMES" "$SHOTS" 5 >/dev/null
files=(); IFS=',' read -ra L <<< "$NAMES"
for n in "${L[@]}"; do files+=("-i" "/tmp/efk-preview/sheet_${n}.png"); done
cnt=${#L[@]}
ffmpeg -y -loglevel error "${files[@]}" -filter_complex "$(for i in $(seq 0 $((cnt-1))); do printf "[%d]scale=1400:-1[s%d];" $i $i; done)$(for i in $(seq 0 $((cnt-1))); do printf "[s%d]" $i; done)vstack=inputs=$cnt" "/tmp/efk-preview/hero_${HERO}.png"
echo "/tmp/efk-preview/hero_${HERO}.png"
