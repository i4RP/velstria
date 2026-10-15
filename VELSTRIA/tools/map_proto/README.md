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
草むらの細かい格子（2026-10-16）: `node terrain_grid.mjs --write` が `minimap_sanctum.png`（MLBB Wiki の File:Minimap.png。取得方法は
`minimap_fit.mjs` の先頭）を 20 ユニット四方の格子 600×600 に分類し（外・壁・床・レーン・草むら・川・Blue 拠点・Red 拠点）、草むらだけを
`MapSanctumBushGrid.swift`（`BushMask.sanctum`）へ書き出す。確認画像 `terrain_grid.png`（1 セル 4 px の格子表示、種類ごとに色分け。
画像はどちらもコミットしない）: 外 = 黒、壁 = 茶、床 = 濃紺、レーン = 灰、草むら = 緑（縁は暗め）、川 = 水色、拠点 = 青 / 赤。

キャンプの種類と位置は `layout.json`（`blueCamps` / `redCamps` / `crabs` / `riverCamp`）。前回の小キャンプのうち片側 2 つはサイクロンアイだったので外した。

遊ぶ地図（relayout）の地形を MLBB のミニマップ原本から起こす（2026-10-16、`docs/DESIGN.md` §2.1・`docs/STAGE.md` 1.1）:
1. MLBB Wiki の File:Minimap.png（アイコンなしの 512×512。著作物なのでコミットしない・`.gitignore` 済み）を `minimap_sanctum.png` として置く
   （取得方法は `minimap_fit.mjs` の先頭のコメント。画素 → 地図座標は x = −30 + 23.55·px、y = 12010 − 23.55·py）。
2. `node trace_terrain.mjs`: 地形色の確からしさを 25 ユニット格子へ読み、点対称に平均・σ = 1 格子でぼかし、マーチングスクエアで
   壁（岩）の塊の輪郭を引いて弧長 160 ごとの制御点にする（草むらは上の `terrain_grid.mjs` の細かい格子）。結果は `trace_stats.json`（コミットする。画像が無くても次の手順を回せる）と確認用の `trace_debug.png`。
3. `node terrain_swift.mjs --write`: 制御点を閉じた centripetal Catmull-Rom で 1 mm の精度の多角形にし（Swift の
   `Spline.closedCatmullRom(_:tolerance:maxSegment:)` と同じ）、relayout の縮尺（0.81）で `validationIssues` と同じ規則を調べ、
   キャンプを壁に掛からない最寄りへ寄せて `Sim/MapSanctumTerrain.swift` を書く。通路の幅（隣り合う壁の最短距離）も表示する。

