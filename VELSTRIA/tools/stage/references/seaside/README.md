# Seaside references — 2026-10-28

`moodboard.png` はユーザー提供の FPS 視点の参考画像。手前の味方とミニオンは既存モデルを維持し、
砂浜・海・草を冠した石灰岩・ヤシの色と形をステージの参考にする。
`limestone_arch.png` と `palm_cluster.png` は、この画像を参考に ImageGen で先に作成した 3D 生成専用画像。

| 画像 | 生成指示の要旨 | 3D 生成先 |
| --- | --- | --- |
| limestone_arch.png | 淡いクリーム色の面を持つ石灰岩の自然アーチ。中央は大きく開放、上面は明るい芝と少量の蔦。単体・無地背景、人物・海・HUD・文字なし | Meshy |
| palm_cluster.png | 曲がった黄褐色の幹、幅広い緑の葉とココナッツ。大きなヤシと小さなヤシ、根元に少量の白い石。単体・無地背景、人物・HUD・文字なし | Tripo |

## 現在の生成状態

2026-10-28 の初回リクエストは両社とも残高不足で拒否された（Meshy HTTP 402、Tripo HTTP 403）。
API 残高の追加後、Meshy Smart Topology `meshy-t2.5` でアーチの形状生成が完了。
同じアーチ参考画像による Meshy Retexture と Tripo のヤシ生成も完了し、両方のテクスチャ付きモデルを
VSP1 と共通アトラスへ焼いた。完成した VSP1・アトラスを Blender で読み戻し、前後から形と色を確認した。
アーチは 2,399 三角形、ヤシは 2,400 三角形。アトラスは 1024×1024。

出力のサイズ・SHA-256・モデル別予算は [bake-report.json](bake-report.json)。
[アーチのプレビュー](preview_arch.png) / [ヤシのプレビュー](preview_palm.png) はモデル単体の確認画像。
アプリ画面と参考画像の比較は視界レビューで別途記録する。

画像 SHA-256・指定モデル・パラメーター・応答は [seaside_generation.json](../../seaside_generation.json) と
[seaside_texture.json](../../seaside_texture.json) に記録。最新の進捗はこれらの状態ファイルを参照。
認証情報は環境変数 `MESHY_API_KEY` / `TRIPO_API_KEY` またはローカル設定から読み、リポジトリへ保存しない。

## 再開と取り込み

残高を解消した後、`VELSTRIA/` から実行する。`submit` は新しい有料生成を開始する。
通信結果が不明な提出は `submitting` を残して再提出を止める。提供元でタスクの有無を確認してから再開する。

```sh
node tools/stage/seaside_generate.mjs submit limestone_arch
node tools/stage/seaside_generate.mjs submit palm_cluster
node tools/stage/seaside_generate.mjs status
node tools/stage/seaside_generate.mjs download
node tools/stage/seaside_texture.mjs submit
node tools/stage/seaside_texture.mjs status
node tools/stage/seaside_texture.mjs download
uv run --with numpy --with pillow python tools/stage/seaside_bake.py --preview
```

アーチの再テクスチャは既存 Meshy タスクを使い、形状を再生成しない。参考画像の SHA-256 が元の入力と
一致することと、API 残高が 10 クレジット以上あることを提出前に確認する。
元の形状には UV がなかったため、Retexture で UV を作る。
元 GLB は `geometry-original.glb` に保持し、成功したテクスチャ付き GLB だけを `model.glb` に置く。

取り込み元は `build/stage/seaside/{limestone_arch,palm_cluster}/model.glb`。
Blender で元の材質の色を再ベイクし、各モデル最大 2,500 三角形、共通アトラス 1024×1024 に収める。
出力は `App/Resources/Stage/StageSeaside.bin` と `StageSeasideAtlas.jpg`。
VSP1 の ID は `ruin_arch` / `tree_tall`、座標は +Y 上・底面 0・XZ 中央原点。
中間ファイル、三角形数・元 GLB の SHA-256、プレビューは `build/stage/seaside/` に保存する。
完成後は実描画で向き・葉の形・アーチの開口・色・予算を確認する。

API は [Meshy Image to 3D](https://docs.meshy.ai/en/api/image-to-3d)、
[Meshy Retexture](https://docs.meshy.ai/en/api/retexture) と
[Tripo v3 Image to 3D / P Series](https://developers.tripo3d.ai/en/docs/generation-image-to-model/p) を使用。
指定パラメーターは実装と状態ファイルを正とする。
