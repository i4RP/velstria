# Reference field art — 2026-10-19

制作経路: built-in ImageGen → Tripo v2 image-to-model → Blenderで減面・UV再ベイク → VSP1。
生成画像はこのフォルダのPNG。入力写真そのものは含まない。
Tripoのリクエスト、モデル版、seed、完了task IDは `../../reference_tripo_state.json`。
認証はローカル設定または環境変数から読み、キーをファイルへ保存しない。

画像生成指示の要旨:

| 画像 | デザイン |
| --- | --- |
| root_wall.png | 淡い灰緑の花崗岩、黄褐色の太い根、低い青緑の葉。横長5m×2m、高さ1.7mの障害物 |
| camp_crescent.png | 中央が空いたU字の岩と根の巣、背面に小さな青緑の結晶。7m×5m、高さ2.1m、前面開放 |
| camp_gate.png | 浅い半月形の岩壁。背面中央の尖ったアーチと青銅格子、左右の柱。7m×2.5m、高さ2.8m |
| river_wall.png | 低いS字の白灰色石壁、細い金の縁飾り。5m×0.9m、高さ0.95m |
| grass.png | 継ぎ目のない落ち着いたセージ・オリーブ色の短い草、細部を抑えた手描き風 |
| rock.png | 継ぎ目のない淡い灰緑の石。大きな面、控えめな亀裂、手描き風 |

全オブジェクトはゲーム用の独立した単体、背景から分離、文字・HUDなし。
ゲート初稿は閉じすぎていたため前面開放へ作り直し、最終稿だけをTripoへ渡した。
モデルの実寸・配置時の高さは画面比較で調整している。

```sh
node tools/stage/reference_tripo.mjs status
node tools/stage/reference_tripo.mjs download
uv run --with numpy --with pillow python tools/stage/reference_bake.py
```

完成モデルの三角形: root_wall 4,000 / camp_crescent 5,999 / camp_gate 6,000 / river_wall 2,500。
アトラス2048×1024。草・岩の地面タイル1024×1024。
Tripo出力の地面での長軸をPCAで揃えてから寸法を合わせる。岩壁は輪郭の断面、巣は開口部を除く弧に沿って配置する。
