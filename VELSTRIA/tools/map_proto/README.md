# map_proto

`MapDefinition.standard`（Swift）の座標を Node で検証・描画する試作。座標は `layout.json`（レーン・タワー・キャンプ・ボス）と
`shapes.json`（壁・草むら）に持ち、Swift と同じ値にする。`node mapproto.mjs` が違反 0・到達性 OK になることを確かめる。

ミニマップのスクリーンショットから座標を起こす手順（`docs/REFERENCE_GAP.md` §11）:
1. `icons.ps1`（Add-Type の C# を呼ぶ PowerShell。`[Icons]::Run(画像, x0, y0, x1, y1)`）でアイコンを色で切り出し、`icons_raw.csv` に保存。
2. `icons.mjs` でタワーのアイコンを組み立て、`calib.mjs` で点対称のペアから較正して地図座標へ。
3. `camps_measured.mjs` でキャンプを Blue / Red それぞれ測定値のまま地図座標へ。
4. 壁: `walls.mjs` で明るさの分布を確認し、`fitwalls.mjs`（`rgb4.txt` = 4 枚目のミニマップの RGB。`dump_rgb.ps1` で書き出す（7 MB 超なのでコミットしない））で抽出・当てはめ → `fixbrushes.mjs` で草むらを避難 → `gen_swift.mjs` で `MapDefinition.swift` の配列を生成。

草むら・キャンプの種類（2026-10-09、`docs/REFERENCE_GAP.md` §12）:
1. `bushes_mlbb.mjs`: MLBB の現行マップの俯瞰画像（MLBB Wiki の `Sanctum Island Map.jpg`、2400×1080）を、タワー 18 基とコアの台座の画素位置で
   射影変換して真上から見た図にし、背の高い草の範囲を読み取った矩形（Blue 側。1 つの草むらが複数の矩形なら同じ組）。画像はコミットしない。
2. `resolve_bushes.mjs --write`: 譲る前の壁（`walls_fit.json` = fitwalls.mjs の結果を固定したもの）から始めて、草むらと壁の重なりを深さの半分ずつ譲り、角の壁を MLBB の壁の線へ置き直して `shapes.json` を更新。
3. `node mapproto.mjs` で違反 0・到達性 OK を確かめ、`gen_swift.mjs` で `MapDefinition.swift` の壁・角・草むらの配列を作り直す。
キャンプの種類と位置は `layout.json`（`blueCamps` / `redCamps` / `crabs` / `riverCamp`）。前回の小キャンプのうち片側 2 つはサイクロンアイだったので外した。
