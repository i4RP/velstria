#!/bin/bash
# preview.sh が撮ったコマを、ヒーロー付近で切り出してタイル 1 枚にまとめる。
# usage: tools/effekseer/sheet.sh <効果名> [列数=4] [切り出し 高さ 幅 y x = 700 800 850 250]
set -euo pipefail
NAME="$1"; COLS="${2:-4}"; H="${3:-700}"; W="${4:-800}"; Y="${5:-850}"; X="${6:-250}"
D="${OUTDIR:-/tmp/efk-preview}"; cd "$D"
rm -f "c_${NAME}_"*.png
n=0
for f in "${NAME}"_[0-9][0-9].png; do
    sips -c "$H" "$W" --cropOffset "$Y" "$X" "$f" --out "c_${f}" >/dev/null 2>&1
    n=$((n+1))
done
ROWS=$(( (n + COLS - 1) / COLS ))
ffmpeg -y -loglevel error -pattern_type glob -i "c_${NAME}_*.png" -vf "scale=iw*0.5:ih*0.5,tile=${COLS}x${ROWS}" -frames:v 1 "sheet_${NAME}.png"
echo "$D/sheet_${NAME}.png"
