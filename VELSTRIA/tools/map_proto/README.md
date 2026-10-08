# map_proto

`MapDefinition.standard`（Swift）の座標を Node で検証・描画する試作。座標は `layout.json`（レーン・タワー・キャンプ・ボス）と
`shapes.json`（壁・草むら）に持ち、Swift と同じ値にする。`node mapproto.mjs` が違反 0・到達性 OK になることを確かめる。

ミニマップのスクリーンショットから座標を起こす手順（`docs/REFERENCE_GAP.md` §11）:
1. `icons.ps1`（Add-Type の C# を呼ぶ PowerShell。`[Icons]::Run(画像, x0, y0, x1, y1)`）でアイコンを色で切り出し、`icons_raw.csv` に保存。
2. `icons.mjs` でタワーのアイコンを組み立て、`calib.mjs` で点対称のペアから較正して地図座標へ。
3. `camps_measured.mjs` でキャンプを Blue / Red それぞれ測定値のまま地図座標へ。
4. 壁: `walls.mjs` で明るさの分布を確認し、`fitwalls.mjs`（`rgb4.txt` = 4 枚目のミニマップの RGB。`dump_rgb.ps1` で書き出す（7 MB 超なのでコミットしない））で抽出・当てはめ → `fixbrushes.mjs` で草むらを避難 → `gen_swift.mjs` で `MapDefinition.swift` の配列を生成。
