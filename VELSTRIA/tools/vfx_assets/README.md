# vfx_assets（Blender で作るスキル演出の素材）

スキル演出の UV 付きメッシュ・コマ送り・1 枚の模様・継ぎ目の無い流れる模様を、Blender をヘッドレスで回して作る。
どれもこのフォルダのスクリプトの手続き（形・ノイズ・Cycles の体積の描画）で作ったもので、他のゲームの素材は使っていない
（MLBB の画面収録は大きさ・色・時刻を比べるためだけに手元で見る。リポジトリには入れない）。

| スクリプト | 動かすもの | 出力 |
|---|---|---|
| `blender/fx_meshes.py` | Blender（bmesh で組んで評価後の頂点を書き出す） | `App/Resources/FX/Meshes/fxm_<名前>.bin`（.fxm 形式） |
| `blender/fx_render.py` | Blender（Cycles・CPU・ノイズ除去） | 作業用のコマ（16 bit PNG。リポジトリの外） |
| `pack.py` | Python（numpy・OpenCV・Pillow） | `App/Resources/FX/Sheets/fx_<名前>.png`・`App/Resources/FX/Textures/fx_<名前>.png`・`manifest.json` |

`App/Resources` 以下はアプリのバンドル直下へ平らに入るので、名前に `fx_` / `fxm_` を付けてほかの画像とぶつけない。

## 作り直す

```sh
B="$LOCALAPPDATA/Programs/BlenderLTS/blender-4.5.10-windows-x64/blender.exe"   # 確認した版: Blender 4.5.10 LTS（Windows 11、zip 版）
W="$TEMP/vfxwork"
"$B" -b --factory-startup --python-exit-code 1 -P blender/fx_meshes.py -- --out ../../App/Resources/FX/Meshes
"$B" -b --factory-startup --python-exit-code 1 -P blender/fx_render.py -- --out "$W/frames" --samples 32
python pack.py --frames "$W/frames" --preview "$W/preview"      # 確認用の合成画像（草地色・暗色の上）はリポジトリの外へ
```

`--only <名前>`（何度でも）で一部だけ、`fx_render.py --scale 0.25 --samples 12` で確認用に小さく速く描ける。
全部で約 10 分（Cycles・CPU 32 サンプル）。乱数・ノイズの種は固定で、同じ版の Blender・ライブラリなら同じ画になる。

## 形式

- **.fxm**（`fx_common.write_fxm`）: `"FXM1"`・頂点数・添字数・予約・境界（min/max）・頂点（位置・法線・UV の float32 × 8）・添字（uint32）。
  実行時は `FXModelFile`（`App/Battle/Render/SkillFX/FXMeshes.swift`）が読み、`FXShape` の模型の形としてプールする
  （試合のレシピが使う形だけ）。どれも単位の大きさ、前 = 実行時の -Z。UV の約束は `fx_meshes.py` の冒頭と `FXShape`。
- **シート**: `cols × rows` の格子（左上から行優先）。各コマの外周 2 px は完全に透明（隣のコマへにじまない）。
  `white` = RGB 白 + アルファ（色は実行時の tint）、`colored` = 色をアルファで割った直線のアルファ（爆炎の白 → 黄 → 橙、煙・岩の陰影）。
  実行時の `FXSheet`（`FXPrograms.swift`）に列・行・1 コマの画素・色付きかを書く。粒子（`FXEmit.sheet`）とメッシュ（`FXMesh.sheet`）の両方で使う。
- **1 枚の模様**（地割れ・焦げ跡・四芒星・斬撃の帯・渦の刃）: 白 + アルファ。`FXTex` の Blender の画像（`bundled`）。
- **流れる模様**（溶岩の網・炎の筋）: UV のトーラスで 4D ノイズを引いた継ぎ目なしの白黒。`FXFlowTex` の `lava` / `flame`。

## 一覧

| 名前 | 種類 | 大きさ | 中身 |
|---|---|---|---|
| `fireball` | シート 5 × 5（色付き・加算） | 1280² | 白い芯の爆炎が膨らみ、黄 → 橙 → 暗い朱へ冷えて上へ千切れる（体積の発光） |
| `smoke_hd` | シート 5 × 5（色付き・アルファ） | 1280² | こぶ状の煙が膨らんで昇り、縁から薄れる（体積・日の光の陰影） |
| `spikes` | シート 4 × 4（白・加算） | 1024² | 中心から放射状のぎざぎざの炎の舌が一瞬で伸び、細りながら消える + 白い芯 |
| `rock_tumble` | シート 4 × 4（色付き・アルファ・繰り返し） | 512² | 角張った白っぽい岩が 1 回転する |
| `dust_ring` | シート 4 × 4（色付き・アルファ・地面） | 1024² | 地面を走る土煙の輪が外へ広がり薄れる（上から見た形） |
| `crack_s` | 1 枚（白） | 1024² | 横に寝た S 字の太い地割れ + 枝 + 細いひび |
| `crack_radial` | 1 枚（白） | 1024² | 放射状の 11 本の枝分かれするひび + 途切れた輪のひび |
| `scorch` / `star4` / `swoosh` / `blade` | 1 枚（白） | 512² / 256² | 焦げ跡・四芒星・斬撃の帯（u = 尾 → 頭）・渦の刃 |
| `lava` / `flame_noise` | 継ぎ目なし（白黒） | 512² | 溶岩の網・炎の筋 |
| `crescent` `ringLip` `twister` `pillar2` `bladeRing` `burstDome` `starCross` `shardRing` | .fxm | 130〜1344 三角形 | 三日月の帯・衝撃の輪・竜巻・2 重の光の柱・渦の刃の輪・炎の半球・四芒星の盤・岩板の輪 |

大きさ・バイト数・sha256 は `manifest.json`。
