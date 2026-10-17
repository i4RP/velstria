# ステージ（戦場の地形・小物）の作り方

## 2026-10-17: 川のタートル／ロードの巣

- 衝突は `BossPitGeometry`（外径 8.2 m、内径 6.84 m、開口 86 度）。描画は専用画像から作った Tripo 2.5 モデル。
  下側は上側の上下反転。紋章の最大高 約 2.4 m、手前は低い縁に補正。旧ルーン円盤・発光リングを廃止。
- `StageSanctuary` の石材・笠石・紋章・水路・低い苔草は背景準備し、材質別チャンクへ結合する。
  1 個 12,000 三角形、共有アトラス 1024²、最大 2 チャンク。既存のステージ予算上限は変更しない。
  元画像 `tools/stage/references/sanctuary_concept.png` → `node tools/stage/sanctuary_tripo.mjs`
  → `uv run --with numpy --with pillow python tools/stage/sanctuary_bake.py` で生成・Blender 減面・色焼き付け。
  API は v2、モデルは `v2.5-20250123`。タスク ID を保存して再開し、有料リクエストを自動再送しない。
  キーは環境変数かリポジトリ外の設定からのみ取得。配布には生成済み bin/JPEG を使い、API 接続は不要。
  壁上の苔草には隠蔽判定を付けない。ブッシュは引き続き BushMask の草カードだけ。
- 比較撮影: `-battle practice -stageFull -stageCam 28.45,70.044,1.34 -stagePitch 40
  -stageSilent -stageClean -stagePitReference`。最後の引数は描画用コピーだけにタートルとヒーローを配置する。
  通常カメラは 56 度のまま。`tools/stage/compare_pit.py` は参照画像と撮影の等倍率リサイズ・中央切り抜き、
  50% 重ね合わせ、差分を出力する。形状を変形させる画像位置合わせは行わない。
- 巣は下側のタートル（初回 2:00）から開始。討伐後は反対側へ移る。タートル再出現 120 秒、8:00 にロードへ交代、
  ロード再出現 180 秒、12:00 強化、18:00 進化。討伐側の残存タワー HP が最も少ないレーンへ味方ロードが進む。
  強化以降は突進と味方ミニオンの加速、進化後は自身の被ダメージ軽減と近くの味方ヒーローの通常攻撃への魔法追撃。
  強化の具体的な係数は暫定のゲーム内調整値。シミュレーション版は統合後 43。

担当: battle-renderer（ステージ）。2026-10-05 に全面的に作り直し、2026-10-12 に素材を「遺跡と森」のセットへ替えた。

- 壁と地図の外（2026-10-16、MLBB 風のスタイライズ）: 壁は足跡いっぱいの一枚岩（`StageLayout.slabCore`。裾を 0.28 m 広げ、
  上の縁を丸め、上面は苔）に茂みと木を載せる。辺に崖の岩・角に柱状の岩を並べるのはやめた（境界がガタガタで隙間が暗く見えた）。
  地図の外は一枚岩の崖の帯（地図の縁 = 移動の限界から外へ約 6 m、南は低い）・その後ろの森・暗がりの板（`StageLayout.edgeSkirt`、
  縁から 3 m より外を暗い森の地面からほぼ黒へ）。補助マップの遮蔽は地図の外 7 m で 1 になる。シェーダーは変えていない。

- 既定のセット（`StageArtSet.ruins`、2026-10-12）: 古代の石の遺跡と豊かな自然が共存し、建築に魔力が残る世界。スタイライズドな
  セミリアル。石 = 重く風化した灰緑の花崗岩（艶なし・欠け・苔）、金属 = 暗い古びた青銅、光るのは結晶とルーンだけ。色は深緑・青緑・
  灰色の石・くすんだ土。チーム色は結晶・ルーン・小さな飾りだけ。拠点の石畳は中央をきれいに保ち、縁ほど崩れて土と苔が入り込む。
  泉は遺跡の台座（柱の受け皿にチーム色の小さな結晶）。
- 旧セット（`StageArtSet.legacy`、2026-10-05）: Arena of Valor / Honor of Kings 系の手描き風（暖かく彩度の高い草地と土のレーン、
  灰色の岩の崖）。素材ファイルはそのまま残してあり、起動引数 `-legacyStage`（DEBUG / SCREENSHOTS ビルド）で読む（見比べ用）。

配置・衝突・草むら・川の規則（1 章）と配置のコード（`StageLayout`）は両セットで同じ。違うのは素材ファイル・拠点の石畳の配合・
シェーダーの色合わせ（custom_parameter の「新セット」の値）・泉の見た目だけ。

## 1. 守ること（ゲームの判定と食い違わせない）

- 地形の判定は遊ぶ地図 `MapDefinition.relayout`（VelstriaCore）だけが正。壁 44（滑らかな多角形。1.1）、草むら 32 か所（細かい格子 `BushMask`。`brushes[k]` は外接矩形）、
  川は x + y = 12000 を中心とする幅 900 の帯（見た目だけ。移動に影響なし）、レーンは中心線の折れ線。
  - 硬く見えるもの（岩・崖・木の幹）は壁の足跡の内側か、地図の外にだけ置く。足跡の外は歩ける見た目（平らな地面・低い草花）。
  - 矩形の壁は角まで埋める（衝突は 2026-10-16 から角をユニットの半径で丸めた膨張。見た目の角の丸めはそれより小さく）。円の壁は丸く見せる。
  - レーン中心線から 3.5 m・泉/Core から 18 m 以内に背の高いものを置かない。
  - 草むらの見た目の縁は矩形に合わせる（判定は中心点が矩形の内側か）。稼働版 `relayout` の草むらは細かい格子（`MapDefinition.bushMask`）で、
    房はセルの中だけに置き、地面の下草・HUD のミニマップも格子の形どおりに塗る（`MapDefinition.brush(_:contains:)`・`brushRects`）。
- 平面の高さは `GroundLayer`（`App/Battle/Render/GroundLayer.swift`）の段を使う。重なる不透明な平面は 4 mm 以上離す。
- `MapScene` の契約: `init(map:materials:quality:groundImage:)`・`root`・`mapMeters`・`update(dt:)`・草むらの API
  （`brushEntities` の添字 = `MapDefinition.brushes` の添字、半透明フェード）・`fountainSpires`（2 本）。
- カメラは 56° 見下ろし・縦画角 48°・距離 12.5 m × ズーム（0.7〜1.4）・回転しない（南から北を見る）。画面に見える地面は幅 20〜45 m。
  高さ h の物は奥（北）の地面を約 0.67·h 隠す。壁の北の辺の岩は低く（壁の向こうの歩ける所を隠さない）、
  高い岩・柱状の岩・木は南（手前）に寄せる（隠すのは壁の上だけになる）。地図の外は南の縁だけ低くする。
- 壁の小物の地面近く（高さ 1 m 未満）は足跡から 0.4 m までしかはみ出さない（壁で止まるユニットの半径 0.55 m より小さく。
  `StageTests.testSolidPropsStayInsideWallsOrOutsideTheMap` が頂点で確かめる）。

### 1.1 壁の形と高さ（2026-10-16、MLBB のミニマップ原本から）

遊ぶ地図（`MapDefinition.relayout`）の壁は、MLBB のミニマップ原本の暗い塊の輪郭を閉じたスプラインにした多角形
（`Obstacle.polygon`、DESIGN §2.1）。描画は `StageLayout.polygonWall` → `slopedSlab`（足跡いっぱいの一枚岩）。

- カメラ（56° 見下ろし・縦画角 48°）の視線は、画面の上端で 32°、中央で 56°、下端で 80°。面の傾斜が視線より寝ていれば、
  面の向こうの地面は隠れない。高さ H・傾斜 α の面が向こう側を隠す幅は H·(1/tan e − 1/tan α)（e = 視線の角度、負なら隠さない）。
- 基準値（`StageLayout.WallProfile`）:

  | 項目 | 値 | 理由 |
  |---|---|---|
  | 高さの上限 | 2.0 m | ヒーロー（約 1.8 m）の頭が壁の向こうに見える |
  | 細い壁の高さ | ≤ 0.55 + 1.1 × 半分の厚み（m） | 細い三日月の岩は低く（上面が残る傾斜にする） |
  | 北向き（奥）の面 | 38° | 中央の視線 56° より寝ている → 隠さない。上端（32°）でも隠すのは 0.32·H（H = 2 m で 0.64 m） |
  | 横向きの面 | 58° | |
  | 南向き（手前）の面 | 74° | 崖に見せる。隠すのは壁の上だけ |
  | 裾の張り出し | 0.28 m | 足跡（衝突）から 0.4 m 以内（上の規則） |
  | 上の縁の丸め | ≤ 0.35 m | 苔の上面へ滑らかにつなぐ（法線を共有） |

- 傾斜の幅は半分の厚みの 75% まで（細い壁は傾斜が立つ代わりに低くなる）。上面は耳刈りで三角形に分ける（凹んだ形でも覆う）。
- 根元は裾のすぐ外（足跡から 0.3〜0.5 m）に低い草の房と小石を並べてなじませる（`groundFlora`）。補助マップの遮蔽が根元を暗くする。

## 2. 全体の流れ

```
[オフライン]（セットは環境変数 STAGE_SET=ruins（既定）| legacy）
 tools/stage/stage_art.py      Codex で 2D 素材（地面タイル・祭壇の模様・3D 生成用コンセプト画像）
                               仕様 ruins: stage_art_ruins.json → build/stage/ruins/art/、legacy: stage_art.json → build/stage/art/
 tools/stage/stage_tripo.mjs   ruins: Tripo image-to-model（P1・PBR・光の除去。コンセプト画像 → GLB、base_color.png を取り出す）
                               → build/stage/ruins/tripo/<id>/（状態 tools/stage/tripo_state.json）
 tools/stage/stage_meshy.mjs   legacy: Meshy Image to 3D → build/stage/meshy/<id>/（2026-10-11 から無料プランの API では作れない）
 tools/stage/stage_bake.py     タイルのシームレス化・縮小、GLB の正規化・減面・色と遮蔽の焼き付け・アトラス化 → App/Resources/Stage/
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

ファイル名はセットごとに分ける（App/Resources/Stage/ はバンドルの直下に平らに入る）:

| | ruins（既定） | legacy（-legacyStage） |
|---|---|---|
| 地面タイル | `StageRuinsTile_<id>.jpg` | `StageTile_<id>.jpg` |
| 小物メッシュ | `StageRuinsProps.bin` | `StageProps.bin` |
| 小物アトラス | `StageRuinsPropsAtlas.jpg` | `StagePropsAtlas.jpg` |
| 祭壇の模様・シェーダー | 共用（`StageDecal_rune.jpg`・`StageShaders-*.metallib`） | 同 |

### 3.1 地面タイル `App/Resources/Stage/StageTile_<id>.jpg`（新セットは `StageRuinsTile_<id>.jpg`）
- id: `grass` `grass_dark` `dirt` `paving` `rock` `moss` `riverbed`。1024×1024、JPEG 品質 90、sRGB。
- 4 辺ともシームレス（オフセット合成）。色の調整はしない（シェーダー側の定数で合わせる）。
- 実寸の周期（シェーダーの定数）: grass 6 m、grass_dark 6 m、dirt 7 m、paving 5 m、rock 4 m、moss 4 m、riverbed 6 m。

### 3.2 祭壇の模様 `App/Resources/Stage/StageDecal_rune.jpg`
- 円形の石の台座を上から見た絵。円がちょうど内接する正方形に切り出し 1024×1024。円の外は使わない（円盤メッシュに貼る）。

### 3.3 小物メッシュ `App/Resources/Stage/StageProps.bin` + `StagePropsAtlas.jpg`（新セットは `StageRuinsProps.bin` + `StageRuinsPropsAtlas.jpg`）
- アトラス: 2048×1024 の JPEG（品質 90）。512×512 のセルを 4 列 × 2 行。各セルの中身は 496×496 + 周囲 8 px の端の引き伸ばし。
  既定（`STAGE_PROPS_UV=rebake`）は、減面後のメッシュに新しい UV を作り、Meshy の base_color を元のメッシュから焼き付けた絵。
  Meshy の UV は数千の小島に分かれていて、大きく減面すると三角形が島をまたいで色が崩れるため
  （`STAGE_PROPS_UV=meshy` で Meshy の UV と base_color の縮小をそのまま使う）。セルの並び（左上から行優先）:
  `cliff_rock_a, cliff_rock_b, boulder, tree_round / tree_tall, bush, ruin_pillar, ruin_arch`。
  新セットは最後のセルが `spawn_dais`（泉の遺跡の台座。旧セットの `ruin_arch` は配置に使っていなかった）。
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
  | ruin_arch（旧セット） | 1400 | 幅（X）4.0 m |
  | spawn_dais（新セット） | 2000 | 足跡の長辺 6.8 m（旧い泉の台座の直径） |

- 新セット（Tripo）の焼き方（stage_bake.py の表。理由はコメント）: 岩・遺跡は面積が全体の 1% 未満の部分（シダ・蔦の葉の板）を
  減面の前に消す（`MIN_PART`）。木・茂みはボクセルで塊にし、内側の空洞の面を消してならしてから減らす（`REMESH`・`DROP_CAVITIES`・
  `SMOOTH`）。円の壁・矩形の壁の角に置く岩は平面形の角を超楕円で落とす（`ROUND_PLAN`。足跡からのはみ出し 0.4 m の規則のため）。
  色は元のメッシュから焼き付け、減面後の形の遮蔽（Cycles の AO、足元に地面の板）を 0.55 の強さで掛ける（`STAGE_BAKE_AO`）。
  葉は光を除いた色が暗いのでガンマで持ち上げる（`COLOR_GAMMA`）。

### 3.4 シェーダー `App/Resources/Stage/StageShaders-ios.metallib`・`StageShaders-sim.metallib`
- ソース `tools/stage/shaders/StageShaders.metal`。関数（`[[visible]]`）:
  - `stageGroundSurface`（地面: 配合マップでタイルを混ぜる・水面のアニメーション）
  - `stageRockSurface`（崖の芯: 側面は rock、上向きの面は moss を三平面投影）
  - `stageFoliageGeometry`（草・葉の揺れ: 頂点の高さに応じて時間で揺らす）
  - `stagePropSurface`（小物アトラス: 色調の統一）
- custom_parameter（CustomMaterial の custom.value）: 地面 = (繰り返し対策の強さ, 水面の動き, 異方性, **新セット**)、
  崖の芯 = (**新セット**, 0, 0, 0)、小物・草花 = (揺れの強さ, **新セット**, 0, 0)。新セットが 0 のときは 2026-10-05 の式のまま
  （旧セットの見た目を変えない）。新セットでは: タイルごとの色合わせ、石畳の風化（補助マップの A）で石を苔寄りに暗くし暗い目地を
  森の下草で埋める、拠点の中央のきれいな床は石目のコントラストを抑える、小物の根元を湿った青緑に暗くする、葉の上面を日の当たる
  黄緑にする、揺れは個体ごとの位相（頂点色の rgb = 個体の色味のハッシュ）・ゆっくり流れる突風・葉先の細かな震え（数 cm）。
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
  G = 大きな色むら（0.5 が中立）、B = 川の深さ（0 = 岸、1 = 中央）、A = 石畳の風化（新セットだけ。拠点の中央 0 → 縁 1、
  塔の台座・祭壇のまわりは 0.55〜0.8。旧セットは 0）。
- 新セットの拠点の石畳（`StageSplat.BasePlaza`）: 泉から 5.0 m・Core から 6.8 m・参道の中心線から 2.2 m は必ず石畳（風化 0）。
  その外は旧セットの広場の縁（泉 8.9 m・Core 13.2 m・参道 5.1 m）を大小のノイズで揺らして 3 m ほどかけて崩し、縁寄りには石の
  抜けた穴が点々と空く。崩れた所はノイズで踏み固めた土（R）と苔（A）に分ける。レーンの土は縁を広く揺らす（2.1〜4.0 m）。

## 4. 実行時の構成（`App/Battle/Render/Stage/`）

- `StageAssets` — バンドルの素材（タイル・アトラス・小物メッシュ・metallib）を読む。背景スレッドで画像を展開し、結果をキャッシュ。
- `StageSplat` — 配合マップ・補助マップを地図データから作る（純粋関数、背景スレッド可）。
- `StageLayout` — 崖・木・茂み・遺跡・草花の配置（純粋関数、乱数は種固定）。
- `StagePrep` — 上の 3 つをまとめて背景で作り、`MapScene` が拾う。
- `StageMaterials` — CustomMaterial を作る。作れないとき（シェーダーが読めない・未対応の環境）は PBR に落とす
  （地面は配合マップとタイルを CPU で合成した 2048 px の画像）。
- 泉（新セット）: `StageLayout.fountains` が台座（spawn_dais）を最初に置く（装飾の三角形の予算で省かれない。歩ける所の飾りなので
  placements には入れない）。床の高さ・縁の柱の頂部はメッシュから求め（`daisFeatures`）、床が 0.12 m になるまで沈め、柱の無い
  向きを Core へ向ける。柱の頂部（`StageLayoutResult.fountainSockets`）に MapScene がチーム色の小さな結晶を置き、浮遊結晶
  （`fountainSpires`）は細長い両錐 + 腰の小結晶 3 本にして台座の受け口の上（底 0.95 m）に浮かべる。拠点の門柱は遺跡の標柱
  （`MapProps.ruinPost`: 花崗岩 + 青銅の帯 + チーム色の結晶）、旧来の吊りランタンは置かない。旧セットは旧来の泉のまま。

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
| 壁の一枚岩（1.1） | 縦 9 段・平らな上面 | 縦 13 段・上面の盛り上がり・起伏 | 中 + 輪郭の頂点 2 倍 |

## 6. 見た目の確認

- シミュレータ: `-uiTesting -skipOnboarding -battle spectate`（霧なし）または `-battle standard` で起動し
  `xcrun simctl io <UDID> screenshot`。ブルーム・色調補正はシミュレータでは出ない（実機のみ）。
  `tools/stage/stage_shots.sh <UDID> <出力> 16,18 12,12,1.3 42,42 60,60 56,30 6,3,0.9`（最後は泉）で撮り、
  `-- -legacyStage` を付けて同じ位置の旧セットと見比べる。
- `-stageTour` 起動引数（DEBUG）: カメラを地図の名所（青の拠点・中央の川・ボスの巣・ジャングル）へ順に動かす。
