# ステージ（戦場の地形・小物）の作り方

担当: battle-renderer（ステージ）。2026-10-05 に全面的に作り直した。目標の画作りは Arena of Valor / Honor of Kings 系:
手描き風の草地と土のレーン、苔の乗った灰色の岩の崖、茂み・木、青緑の川、彫刻のある円形の石の台座、遺跡、暖かく彩度の高い光。

## 1. 守ること（ゲームの判定と食い違わせない）

- 地形の判定は `MapDefinition.standard`（VelstriaCore）だけが正。壁 106（軸平行の矩形と円）、草むら 32 か所（軸平行の矩形 44。斜めの草むらは矩形の連なり）、
  川は x + y = 12000 を中心とする幅 900 の帯（見た目だけ。移動に影響なし）、レーンは中心線の折れ線。
  - 硬く見えるもの（岩・崖・木の幹）は壁の足跡の内側か、地図の外にだけ置く。足跡の外は歩ける見た目（平らな地面・低い草花）。
  - 矩形の壁は角まで埋める（衝突は角の立った膨張なので、丸めると何もない所で止まって見える）。円の壁は丸く見せる。
  - レーン中心線から 3.5 m・泉/Core から 18 m 以内に背の高いものを置かない。
  - 草むらの見た目の縁は矩形に合わせる（判定は中心点が矩形の内側か）。
- 平面の高さは `GroundLayer`（`App/Battle/Render/GroundLayer.swift`）の段を使う。重なる不透明な平面は 4 mm 以上離す。
- `MapScene` の契約: `init(map:materials:quality:groundImage:)`・`root`・`mapMeters`・`update(dt:)`・草むらの API
  （`brushEntities` の添字 = `MapDefinition.brushes` の添字、半透明フェード）・`fountainSpires`（2 本）。
- カメラは 56° 見下ろし・縦画角 48°・距離 12.5 m × ズーム（0.7〜1.4）・回転しない（南から北を見る）。画面に見える地面は幅 20〜45 m。
  高さ h の物は奥（北）の地面を約 0.67·h 隠す。壁の北の辺の岩は低く（壁の向こうの歩ける所を隠さない）、
  高い岩・柱状の岩・木は南（手前）に寄せる（隠すのは壁の上だけになる）。地図の外は南の縁だけ低くする。
- 壁の小物の地面近く（高さ 1 m 未満）は足跡から 0.4 m までしかはみ出さない（壁で止まるユニットの半径 0.55 m より小さく。
  `StageTests.testSolidPropsStayInsideWallsOrOutsideTheMap` が頂点で確かめる）。

## 2. 全体の流れ

```
[オフライン]
 tools/stage/stage_art.py      Codex で 2D 素材（地面タイル・祭壇の模様・Meshy 用コンセプト画像） → build/stage/art/
 tools/stage/stage_meshy.mjs   Meshy Image to 3D（コンセプト画像 → GLB + テクスチャ） → build/stage/meshy/<id>/
 tools/stage/stage_bake.py     タイルのシームレス化・縮小、GLB の正規化・減面・アトラス化 → App/Resources/Stage/
 tools/stage/build_shaders.sh  StageShaders.metal → metallib（実機 / シミュレータ / macOS） → App/Resources/Stage/

[実行時]
 StagePrep（背景スレッド）     地図データ → 地面の配合マップ・小物の配置・チャンク毎の結合頂点
 MapScene（main actor）        TextureResource・MeshResource・マテリアルを作ってエンティティにする
```

Metal のシェーダーはアプリのターゲットでコンパイルしない（CI の Xcode に Metal Toolchain が無くても通るように）。
`tools/stage/build_shaders.sh` が事前にコンパイルした metallib を `App/Resources/Stage/` に置き、実行時に
`MTLDevice.makeLibrary(URL:)` で読む。`.metal` のソースは `tools/stage/shaders/` に置く（App/ の外）。
シェーダーを変えたら必ず build_shaders.sh を実行して metallib を更新する（テストがソースのハッシュを照合する）。

## 3. 素材の形式

### 3.1 地面タイル `App/Resources/Stage/StageTile_<id>.jpg`
- id: `grass` `grass_dark` `dirt` `paving` `rock` `moss` `riverbed`。1024×1024、JPEG 品質 90、sRGB。
- 4 辺ともシームレス（オフセット合成）。色の調整はしない（シェーダー側の定数で合わせる）。
- 実寸の周期（シェーダーの定数）: grass 6 m、grass_dark 6 m、dirt 7 m、paving 5 m、rock 4 m、moss 4 m、riverbed 6 m。

### 3.2 祭壇の模様 `App/Resources/Stage/StageDecal_rune.jpg`
- 円形の石の台座を上から見た絵。円がちょうど内接する正方形に切り出し 1024×1024。円の外は使わない（円盤メッシュに貼る）。

### 3.3 小物メッシュ `App/Resources/Stage/StageProps.bin` + `StagePropsAtlas.jpg`
- アトラス: 2048×1024 の JPEG（品質 90）。512×512 のセルを 4 列 × 2 行。各セルの中身は 496×496 + 周囲 8 px の端の引き伸ばし。
  既定（`STAGE_PROPS_UV=rebake`）は、減面後のメッシュに新しい UV を作り、Meshy の base_color を元のメッシュから焼き付けた絵。
  Meshy の UV は数千の小島に分かれていて、大きく減面すると三角形が島をまたいで色が崩れるため
  （`STAGE_PROPS_UV=meshy` で Meshy の UV と base_color の縮小をそのまま使う）。セルの並び（左上から行優先）:
  `cliff_rock_a, cliff_rock_b, boulder, tree_round / tree_tall, bush, ruin_pillar, ruin_arch`。
- バイナリ（リトルエンディアン）:
  ```
  "VSP1"(4) | u32 version=1 | u32 jsonLength | JSON(UTF-8) | 0 埋めで 16 バイト境界 | データ
  JSON = {"atlas":{"width":2048,"height":1024},
          "props":[{"id":"cliff_rock_a","vertexCount":N,"indexCount":M,
                    "vertexOffset":<データ先頭からのバイト>,"indexOffset":<同>,
                    "boundsMin":[x,y,z],"boundsMax":[x,y,z]}, ...]}
  頂点 = float32 × 8 [px,py,pz, nx,ny,nz, u,v]（32 バイト）、添字 = uint32（三角形リスト、反時計回りが表）
  ```
- 座標: RealityKit と同じ（+Y が上、メートル）。足跡（x/z の外接矩形）の中心が原点、最も低い点が y = 0。
  水平で最も長い向きを +X に合わせる（門は開口部の向きが X）。
- UV は RealityKit の向き（アトラス画像の**下端**が v = 0）。
- 法線は滑らか（角度で分割済み）・単位長。減面後の三角形数の目安と正規化後の実寸
  （崖の岩は地図全体で約 450 個置くので、1 個あたりの面数が全体の負荷を決める。2026-10-05 の計測で
  2400 面のままだと地図全体 300 万面になったため下げた）:

  | id | 三角形 | 実寸 |
  |---|---|---|
  | cliff_rock_a | 1000 | 幅（X）4.0 m |
  | cliff_rock_b | 900 | 高さ 3.0 m |
  | boulder | 500 | 足跡の長辺 2.0 m |
  | tree_round | 1100 | 高さ 4.2 m |
  | tree_tall | 1050 | 高さ 5.0 m |
  | bush | 450 | 足跡の長辺 1.6 m |
  | ruin_pillar | 900 | 高さ 2.6 m |
  | ruin_arch | 1400 | 幅（X）4.0 m |

### 3.4 シェーダー `App/Resources/Stage/StageShaders-ios.metallib`・`StageShaders-sim.metallib`
- ソース `tools/stage/shaders/StageShaders.metal`。関数（`[[visible]]`）:
  - `stageGroundSurface`（地面: 配合マップでタイルを混ぜる・水面のアニメーション）
  - `stageRockSurface`（崖の芯: 側面は rock、上向きの面は moss を三平面投影）
  - `stageFoliageGeometry`（草・葉の揺れ: 頂点の高さに応じて時間で揺らす）
  - `stagePropSurface`（小物アトラス: 色調の統一）
- テクスチャの割り当て（CustomMaterial のスロット → 中身）:

  | 材質 | base_color | emissive | roughness | metallic | specular | ambient_occlusion | custom |
  |---|---|---|---|---|---|---|---|
  | 地面 | grass | dirt | paving | riverbed | grass_dark | 補助マップ | 配合マップ |
  | 崖の芯 | rock | — | moss | — | — | — | — |

  clearcoat 系のスロットは `.lit` の照明モデルでは束縛されない（黒くなる）ので使わない。

- 配合マップ（custom、RGBA8、地図の外 20 m まで含む 160 m 四方 = world x −20…140、z 20…−140）:
  R = 土（レーン・キャンプ）、G = 石畳（拠点・祭壇まわり）、B = 川（川底 + 水面）、A = 森の下草（壁際・木陰）。
  草地（grass）は 1 − (R+G+B+A) の残り。
- 補助マップ（ambient_occlusion、RGBA8、同じ範囲）: R = 遮蔽（崖の根元・木陰・草むらの下を暗く）、
  G = 大きな色むら（0.5 が中立）、B = 川の深さ（0 = 岸、1 = 中央）、A = 予備。

## 4. 実行時の構成（`App/Battle/Render/Stage/`）

- `StageAssets` — バンドルの素材（タイル・アトラス・小物メッシュ・metallib）を読む。背景スレッドで画像を展開し、結果をキャッシュ。
- `StageSplat` — 配合マップ・補助マップを地図データから作る（純粋関数、背景スレッド可）。
- `StageLayout` — 崖・木・茂み・遺跡・草花の配置（純粋関数、乱数は種固定）。
- `StagePrep` — 上の 3 つをまとめて背景で作り、`MapScene` が拾う。
- `StageMaterials` — CustomMaterial を作る。作れないとき（シェーダーが読めない・未対応の環境）は PBR に落とす
  （地面は配合マップとタイルを CPU で合成した 2048 px の画像）。

チャンク: 小物は 12 m 格子のチャンク × 材質（小物・崖の芯・草花）ごとに 1 メッシュへ結合する（視錐台カリング用）。
計画（StagePlan）は 1 つだけ取っておき、MapScene が取り出したら手放す（読み込みを中断したら BattleRenderer.teardown が捨てる）。
展開した画像は試合ごとに読み直し、小物のメッシュだけを覚えておく。
DEBUG の `-uiTesting`（UI テスト）と単体テストのホストでは小物を減らし地図の外を省く（CI の UI テストが HUD を待つ時間・
単体テストの所要時間に収めるため。`-stageFull` で無効）。配置の規則と面数は StageTests が本来の密度で直接確かめる。

## 5. 画質ごとの違い

| | low | medium | high |
|---|---|---|---|
| 地面 | CustomMaterial（異方性 1） | 同（異方性 2） | 同（異方性 4） |
| 小物の密度 | 0.6 | 0.85 | 1.0 |
| 草・葉の揺れ | なし | あり | あり |

## 6. 見た目の確認

- シミュレータ: `-uiTesting -skipOnboarding -battle spectate`（霧なし）または `-battle standard` で起動し
  `xcrun simctl io <UDID> screenshot`。ブルーム・色調補正はシミュレータでは出ない（実機のみ）。
- `-stageTour` 起動引数（DEBUG）: カメラを地図の名所（青の拠点・中央の川・ボスの巣・ジャングル）へ順に動かす。
