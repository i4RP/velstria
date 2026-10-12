# ステージと塔の再デザイン（アートディレクション・実装計画）

担当: battle-renderer（アートディレクション）。2026-10-12 作成。塔の新モデル（部品分割）・塔の一生の演出・Star Core の終幕カメラ・
ステージ環境の作り直しを並行で進めるための**計画と規則**。結果の記録ではない（結果は各担当がこの文書の該当節へ追記する）。

前提として読むもの: `docs/BATTLE_PERFORMANCE.md`（性能契約）、`docs/STAGE.md`（地形の判定の守り方・素材の形式）、
`App/Battle/Render/TowerTimeline.swift`（塔・Core の時刻表と部品名の契約）。

**ゲームの規則は変えない**: 射程・攻撃の時刻・HP・勝敗・位置・衝突・視界・草むらの判定は `VelstriaCore` のまま。
ここで扱うのは見た目と、見た目を出す時刻だけ。

## 0. 事実（2026-10-12、d6aaf94 時点）

| 項目 | 内容 |
|---|---|
| 描画 | RealityKit（`ARView`）。地形は CustomMaterial（事前コンパイルの metallib: `App/Resources/Stage/StageShaders-*.metallib`、ソースは `tools/stage/shaders/`）。後処理（ブルーム・色調）は実機のみ |
| 光 | 太陽（左上の奥）+ 補助の平行光。太陽の影は high だけ（`RenderQuality.shadows`、影マップは半径 20 m）。low/medium の接地の陰は配合マップの補助マップ R に焼く |
| 形式 | 構造物: `App/Resources/Structures/Struct_<id>.usdz`（材質 1 つ、赤は `_red.jpg` / `_red_emit.jpg` に差し替え）。小物: `StageProps.bin` + `StagePropsAtlas.jpg`（2048×1024、512 px × 8 セル）。地面: `StageTile_<id>.jpg` 1024 px × 7 種 |
| 端末 | iOS 18.0 以上・iPhone のみ・横画面（project.yml）。iOS 18 の対応機種の下限は A12 世代 |
| カメラ | 俯角 56°・縦画角 48°・距離 12.5 m × ズーム 0.7〜1.4、回転なし（南から北を見る）。画面の地面は幅 20〜45 m。高さ h の物は奥の地面を約 0.67·h 隠す |
| 地図 | 120 m 四方（sim 12000、100 単位 = 1 m）。座標は Blue 基準で点対称。下表 |
| 予算 | 構造物: 塔・Core 台座 6k 三角形、結晶 2.5k、テクスチャ 1024 px（`StructureAssetsTests`）。地形: 小物 60万/70万/80万（低/中/高）、チャンク計 90万（high 100万）未満、草むら 9万未満（`StageTests`） |

| 地図の要素（Blue 側、m） | 位置・寸法 |
|---|---|
| 泉 / Core | (6, 6) 半径 8 / (12.5, 12.5) 当たり半径 2.5。間は 9.2 m |
| 塔（外・内・基地） | top (4.8, 87.9) (5.6, 63.4) (6.4, 31.7)、mid (46.6, 49.9) (33.9, 37.1) (24.0, 24.0)、bot (88.5, 5.7) (54.2, 4.7) (31.8, 6.3)。当たり半径 1.1、射程 7.5（Core 8.0） |
| レーン | 中心線: 縁から 7 m の帯 2 本（角は 45°）+ 対角の mid。土の幅は中心線から 2.3〜3.6 m |
| 川 | x + y = 120 を中心とする幅 9 m の帯（移動に影響なし、橋なし） |
| 壁 | 106 個（矩形と円）。草むら 32 か所（矩形 44） |
| キャンプ | 各陣地 5（紫バフ・赤バフ・棘角トカゲ・熔岩の岩人・熾甲虫）+ ボス 2（星喰竜 (82.6, 35.9)、古環の巨像 (37.4, 84.1)）+ 川の中立 3 |

## A. 現状と目標の差分

スクリーンショット（d6aaf94、iPhone Air シミュレータ、medium、`stage_shots.sh` の 10,10 / 46.6,50 / 56,30 / 60,60 / 83,37）で確認。

### A1. 観察できる差

| 場所 | 現状 | 目標（MLBB のジャングルの水準） |
|---|---|---|
| 基地の広場 | 同じ大きさ・明るさの敷石が広場一面に均等に繰り返し、縁まで同じ | 中心ほど整い、外側ほど欠け・土・草が入る。縁石・段・階段で面を区切る |
| 泉 | 明るい灰白の平らな面の多角形（台・箱の柱・単色の結晶）。周囲と質感が合わない | 石材キットで作る低い湧水の祭壇。苔・水・接地の陰 |
| 塔・Core | 金と紺の機械仕掛け（ファンタジー × SF）。遺跡の地面と世界観が別 | 灰緑の花崗岩 + 古い青銅 + 結晶（承認済みの 2D 案 `build/tower_redesign/`） |
| 崖・岩 | 上に明るい緑の苔が平らな板のように乗る。根元が地面に刺さったままで境目に土・小石・草がない | 厚く重い岩。苔は上面の形に沿って縁から垂れる。根元に土・小石・草の裾 |
| 土と草 | キャンプの空き地が輪郭のぼけた楕円の染み。レーンの縁も同じぼけ方 | 草が土へ被さる縁、踏み固めの低い段差、縁に小石と草の房 |
| 素材の統一 | 素材集をつないだように見える（クリーム色 + 深紅の遺跡の柱、灰青の岩、金紺の塔、灰白の泉） | 全ての建築が同じ石・同じ青銅・同じ結晶 |
| 接地 | 塔・Core・泉の足元に陰がなく浮いて見える（low/medium） | 全ての立体に接地の陰 |
| 植生 | 草地が一様。木は壁の上だけ、歩ける所の低木が少ない | 地被・中低木・樹冠の 3 層。壁際・森の奥ほど密 |
| 光る物 | 床の光る輪・八芒星（**2ab581f で削除済み**）。ボスの巣の紫/金の輪と星、Core の傾いた回転リングは残る | 光るのは結晶とルーンの溝だけ。床の装飾の光は戻さない |

残すもの: 敵の塔の射程円（視点ヒーローが敵の塔の近くにいる時だけ出る**機能の表示**。`StructureVisual.rangeRing`）、ボスの巣の紋章（巣の識別）。

### A2. 実プロジェクトで確認が必要な原因（推定。直す前に各担当が確かめる）

| 差 | 推定の原因 | 確かめる所 |
|---|---|---|
| 石畳の均等な反復 | 配合マップ G が Core 半径 13.8 m・泉 9.4 m・参道 5.6 m の範囲でほぼ 1 になり、石畳タイル 1 枚（5 m 周期。タイル自体が同じ大きさの敷石で埋まっている）だけが出る。タイルのずらし（variation）と色むら（補助 G、±17%）では大きさの単調さは消えない | `StageSplat.make` の G、`stageGroundSurface` の variation |
| 白い泉 | `MapScene.buildDecorations` の手続きメッシュ（`.stone` = 灰 0.72）。ステージの素材経路の外 | `MapScene` の泉・参道のランタン・門柱 |
| 平らな苔の板 | 崖の芯は `stageRockSurface` が法線の上向き成分（smoothstep 0.45〜0.8）で岩 → 苔を切り替え、縁から垂れる表現がない。Meshy の岩は苔の帽子がテクスチャに焼かれている | シェーダーの `top`、`StagePropsAtlas.jpg` |
| 根元が浮く | 補助 R の遮蔽は壁・樹冠・草むらだけで、塔・Core・泉が入っていない。補助マップは 512 px / 160 m（31 cm/px）で細い接地陰が出ない | `StageSplat` の補助マップ |
| 土の境のぼけ | 高さ付き混合はあるが、スタンプの幅（inner→outer 1〜1.5 m）が広く、縁に小物を置かない（`isFloraSpot` がレーン・石畳を避ける） | `StageSplat` のスタンプ、`StageLayout.groundFlora` |
| 素材集の継ぎはぎ | 出所が 4 系統（Codex のタイル、Meshy の小物、Tripo の構造物、手続きメッシュ）。色の統一は `stagePropSurface` の定数だけ | `tools/stage/stage_art.json`・`tools/structures/structures.json` の画風指定 |
| 植生の層の薄さ | 草花・低い茂みは共通の三角形予算で後から削られる（10/09 の修正。外周の森の密度も変わった） | `StageLayout.admitProp`、配置の順番 |

## B. 統一アートディレクション

主題: **自然と共存する古代の石の遺跡、まだ魔力を残す建築**。半写実のスタイライズ（筆致はあるが材質は物理的に正しい。写実でもローポリでもない）。
優先順位: シルエット > 大きな明暗の塊 > 材質の分離 > 中くらいの形 > 細部。

| 項目 | 規則 |
|---|---|
| 配色 | 深い森の緑・青緑・灰色の石・くすんだ土の茶。彩度は地面 < 植生 < 結晶。白に近い面・純色の面を作らない |
| チーム色 | 青 = シアン〜青緑の光 `#3fd0e0`・琺瑯と布 `#1f5f7a`。赤 = 深紅〜橙の熾火の光 `#ff5a3c`・`#7a1f2a`。**結晶・ルーンの溝・旗・小さな琺瑯の飾りだけ**。石の本体は灰のまま（建物全体を青・赤に塗らない） |
| 石 | 重い風化した灰緑の花崗岩。厚い面取り（1 m の塊で 8〜12 cm）・欠けた角・すり減った段。苔と地衣類は割れ目と上面に薄く。艶なし |
| 金属 | 暗い古青銅・黒ずんだ鉄（留め具・帯・腕金・鋲）。控えめな低い艶、少しの緑青。金・真鍮の明るい金属は使わない |
| 結晶・ルーン | 唯一の発光。光は形の内側に収め、輪郭を光で消さない。床に光の線・輪を描かない |
| 形 | 太く短い塊、上が少しすぼまる。45° の見下ろしで上面のシルエットが読めること（塔は「上から見た形」で種類が分かる） |
| 光 | 暖かい中立の主光（左上の奥）+ 柔らかい空の補助光。割れ目の遮蔽で厚みと重さを見せる。リムライト・強い逆光は使わない |
| 植生 | 3 層: 地被（苔・短い草・落ち葉、地面のタイル）/ 中低木（膝〜腰、低木・シダ）/ 樹冠（壁の上・地図の外）。レーン → 壁へ向かって密度を上げる |
| 接地 | 立体は全て地面に「埋まって」見えること: 根元に土・小石・草の裾 + 接地の陰。地面から生えたように見えない物（台座の真下の平らな影だけ）は不可 |
| 建築 | 塔・Core・泉・門柱・遺跡は同じ石材キット・青銅金具・結晶で作り、一つの文明に見せる。クリーム色の石・深紅の塗装（旧 ruin_*）は使わない |
| 遊びの読みやすさ | レーンの土・草むら・壁の輪郭が一目で分かること。歩ける所の植物は膝下（草むらと見間違えない）。草むらの見た目の縁は矩形どおり。ユニットより明るい地面を作らない |
| 色覚配慮 | 色覚配慮モードでは赤チームが橙になる（`TeamColors`）。構造物の赤テクスチャは現状固定で未対応 → チーム色の部位は差し替え可能な材質に分ける（F 参照） |

## C. 全環境アセットの再制作一覧

プロジェクトに**存在する物だけ**。橋はない（川は全面を歩ける）ので作らない。階段は Core・泉のモデルの一部としてだけ作る。

優先度: P0 = 塔・Core（進行中）/ P1 = 地面・崖・岩・泉（画面の大部分）/ P2 = 植生・川岸・キャンプ / P3 = 門柱・ランタン・遺跡・小物。

### C1. 用途・配置・寸法

| アセット | 現状 | 用途・配置 | 基準寸法（目標） | バリエーション | 優先 |
|---|---|---|---|---|---|
| 外塔 | Struct_tower（3 種共用） | 各レーンの 1 本目、6 基 | 高さ 4.4 m・基壇 2.4 m 角 | 青/赤（色替え） | P0 |
| 内塔 | 同上 | 2 本目、6 基 | 高さ 4.6 m・基壇 3.0 m（八角） | 同上 | P0 |
| 基地塔 | 同上 | 3 本目（拠点の入口）、6 基 | 高さ 4.8 m・基壇 3.4 m 角 | 同上 | P0 |
| Star Core | core_base + core_crystal | 拠点の中心、2 基 | 台座の直径 6.8 m、全高 約 5.4 m | 同上 | P0 |
| 泉 | 手続きメッシュ + 浮遊結晶 2 本（`fountainSpires`） | 復活地点（半径 8 m の中は歩ける） | 台の直径 6.8 m・高さ 0.45 m 以下、縁の石柱 1.6 m 以下 | 同上 | P1 |
| 拠点の石畳 | 石畳タイル 1 枚 | Core・泉・参道・塔の足元 | タイル周期 5 m | 整った敷石 / 欠けた敷石 / 土の混じり（配合で） | P1 |
| 道（レーンの土） | dirt タイル | 3 レーン・キャンプの空き地 | 周期 7 m | 踏み固め / 縁の草の被さり | P1 |
| 地面（草地・下草・苔） | grass / grass_dark / moss | 歩ける地面の大部分・壁際・岩の上 | 周期 4〜6 m | — | P1 |
| 崖の壁 | 芯（押し出し）+ cliff_rock_a/b + boulder | 壁 106 個の足跡の内側、地図の外 | 板岩 幅 4 m、柱岩 高さ 3 m | 板岩 2・柱岩 1・単体 1 | P1 |
| 岩（単体） | boulder | 壁の角・円の壁の周り | 長辺 2 m | 2（丸い / 角ばる） | P1 |
| 樹木 | tree_round / tree_tall | 壁の上（南寄り）・外周の森 | 4.2 m / 5.0 m | 2 | P2 |
| 低木 | bush（+ 膝下へ潰した地被） | 壁の上・歩ける所（膝下） | 長辺 1.6 m | 1 + 潰し | P2 |
| 草むら | 手続きの葉（`brushClump`）、半透明化あり | 草むらの矩形 44 | 葉の高さ 0.85〜1.3 m | — | P2 |
| 草花・小石 | 手続き（頂点色） | 歩ける所の縁・境目 | 0.1〜0.4 m | — | P2 |
| 川・川岸 | 水面シェーダー + riverbed | 対角の帯 9 m | — | 岸の石・葦（新規の小物） | P2 |
| キャンプ・祭壇 | 土の空き地 + ルーンの円盤（番人 半径 2.5 m） | キャンプ 10 | 空き地 半径 2.3〜3.3 m | — | P2 |
| ボスの巣 | ルーンの円盤 半径 5.6 m + 紋章の輪 + 遺跡の柱 ≤3 | 2 か所 | — | 星喰竜（紫）/ 巨像（金） | P2 |
| レーンの門柱 | 手続きの柱（ルーン付き） | Core から 15.6 m、レーンごとに左右 | 高さ 2.0 m | 青/赤（ルーン色） | P3 |
| 参道のランタン | 手続きの支柱 + 灯 | 泉 → Core の参道 4 本 | 高さ 2.1 m | — | P3 |
| 遺跡の装飾 | ruin_pillar（巣の周り）、ruin_arch（アトラスにあるが未配置） | 壁の足跡の内側だけ | 柱 2.6 m、門 幅 4 m | 柱 2・門 1 | P3 |
| 旗 | 塔の手続きメッシュにだけある | 塔・Core のモデルの一部 | 塔 0.3×1.0 m | チーム色 | P0（塔に含む） |

共通モジュール（先に作り、全アセットで使い回す）:

| モジュール | 中身 | 使う所 |
|---|---|---|
| M1 石材キット | 灰緑の花崗岩の塊・面取り・欠け・段・苔の乗り方 | 塔・Core・泉・門柱・遺跡・石畳タイル・崖の色 |
| M2 青銅金具 | 帯・留め具・鋲・腕金（暗い青銅 + 緑青） | 塔・Core・ランタン・門柱 |
| M3 結晶とルーン | チーム色の発光（発光テクスチャ側だけに置く） | 塔・Core・泉・門柱 |
| M4 接地の裾 | 根元の土・小石・草の房 + 補助 R の陰 | 全ての立体 |
| M5 植生セット | 3 層の配色（深緑・青緑・黄緑の頂点）と密度の勾配 | 地被・低木・草むら・樹木 |

### C2. 材質・生成・分割・形式

| アセット | 材質 | 生成入力 | 分割・可動部・破壊 | 最終形式 | 最適化 |
|---|---|---|---|---|---|
| 塔 3 種 | M1 + M2 + M3 + 布 | 承認済み画像 `outer_blue` `inner_blue` `base_blue` → Tripo（結晶は別生成も可） | 部品 5（E1）。立ち上がり・倒壊・瓦礫 | `Struct_<id>.usdz`（子メッシュ `part_*`）+ 赤テクスチャ | 部品合計 6k（結晶 2.5k）、1024 px。瓦礫の塊も 6k に含める |
| Star Core | 同上 | `core_blue` → Tripo | 部品 3（台座・石柱と弧・大結晶）。終幕 | 同上 | 台座 + 石柱 6k、結晶 2.5k |
| 泉 | M1 + M3 + 水 | 新しい概念画像 → Tripo | 浮遊結晶 2 本は別エンティティ（回転、既存の契約） | USDZ（構造物と同じ読み込み） | 新設の予算 4k・1024 px（`StructureAssetsTests` に足す） |
| 石畳・道・地面 | タイル（艶なし） | Codex のタイル（D3）→ `stage_bake.py` | — | `StageTile_<id>.jpg` 1024 px | 地面の CustomMaterial のスロットは 7 つ全部使用中（clearcoat は使えない）。層を増やすなら既存の層の置き換えか配合の意味の変更 |
| 崖・岩 | M1 の色の岩 + 苔 | 概念画像（D2）→ Meshy（`stage_meshy.mjs`）か Tripo | — | `StageProps.bin` のセル | 板岩 1000・柱岩 900・単体 500 三角形（約 450 個置くため） |
| 樹木・低木 | 葉の塊 + 幹 | 概念画像 → Meshy / Tripo | 揺れは `stageFoliageGeometry`（頂点の高さで揺らす） | 同上 | 1100 / 1050 / 450 三角形 |
| 草むら・草花 | 頂点色 | 手続き（D2 の画像は配色の基準） | 揺れ・半透明（判定の表示） | 手続き | 草むら 9 万三角形未満 |
| 川岸 | 石・葦 | 概念画像 → Meshy | — | 小物のセル（セル数は 8 のまま、F2） | 共通の小物予算に入れる |
| 門柱・ランタン・遺跡 | M1 + M2 + M3 | 概念画像 → Meshy / Tripo | — | 小物のセル | 900〜1400 三角形 |
| 祭壇・ボスの巣 | M1 の石の円盤の絵 | Codex の decal（既存の形式） | — | `StageDecal_rune.jpg` | 紋章の光は今の値を超えない |

生成は 1 点ずつ「概念画像 → 確認 → 3D」。Tripo / Meshy の残高は複数のセッションで共有しているので、生成の前に残高を確認する
（10/11 の構造物 7 点で Tripo 390 credits）。API キーはコミットしない。

## D. 代表アセットの画像生成プロンプト

### D1. 塔・Core（`tools/structures/redesign.json` の原文。正は JSON、組み立て済みは `node tools/structures/redesign.mjs prompt <id>`）

プロンプト = 共通部（art + チーム色 + object + break + exclude）+ 個別の Object。赤は `redvar` で青の採用版を添付して作る。

```text
[art]
Art direction: high-end stylized semi-realistic MOBA environment art (painterly but physically grounded PBR materials, like a premium modern mobile MOBA; neither photoreal nor low-poly). World theme: ancient stone ruins coexisting with lush nature; the architecture still holds residual magic. Priority: silhouette > large light/shadow masses > material separation > mid-scale forms > fine details. Materials: (1) STONE = heavy weathered grey-green granite blocks with thick chamfered edges, chipped corners, worn steps, thin moss and lichen in crevices and on top surfaces, matte; (2) METAL = dark aged bronze and blackened iron fittings (clamps, bands, brackets, rivets) with restrained low-gloss reflections and a little green patina; (3) CRYSTAL = the magic core and thin rune channels carved into the stone, the ONLY glowing parts, glow kept contained and soft. Palette: deep forest green, blue-green teal, grey stone, muted earth brown, with the team color used sparingly. The team color appears only in the crystal core, the rune inlays, small cloth banners and a few metal enamel accents; the stone body stays natural grey — never paint the whole building blue or red. Light: one warm-neutral key light from the upper left, soft sky fill, clear form shadows and ambient occlusion in crevices that show thickness and weight.

[blue]
Team color for this image: BLUE team = cool cyan-teal magic glow (#3fd0e0) and deep blue-teal enamel and cloth (#1f5f7a).

[object]
Image type: single-object concept for image-to-3D (Tripo). Show exactly ONE object, whole and uncropped with margin on all sides, centred, viewed three-quarter from above at about 45 degrees (like a MOBA game camera) so the top surfaces and the top-view silhouette are clearly readable. Plain flat light-grey (#d8d8d8) background, soft even studio lighting, no cast shadow on the background, no ground diorama, no display pedestal or turntable, no grass patch around it. The building's own stone foundation plinth IS included and its bottom edge is flat (it will be sunk slightly into the terrain).

[break]
Construction must read as a breakable assembly with visible seams: (a) a fixed stepped stone foundation plinth with a shaft opening at its top (the tower rises out of it at match start), (b) one central monolithic stone pillar, (c) outer cladding made of a few large stone blocks around the pillar, (d) an upper crown structure, (e) the magic core crystal held at the top, (f) dark bronze support brackets, clamps and bands joining the parts, (g) small decorations (cloth banner, hanging chain). Joints between parts are clear, with bronze clamps across them.

[exclude]
Exclude: HUD, UI, text, letters, numbers, logos, watermarks, people, characters, unrelated extra objects, extreme wide-angle distortion, fog, smoke, sparks, particles, glow bloom or light rays hiding the outline, floating debris, uniform plastic shine, noisy micro-detail, over-ornamentation, merging the object into the background.

[outer_blue]
Object: OUTER lane defense tower (tier 1, the lightest and most forward tower of the family). Silhouette: slim, tall, a single vertical pillar — the narrowest of the tower family. A square 2-step granite foundation plinth with a square shaft opening and four short bronze-capped corner posts; rising from it a square-section, slightly tapered stone pillar about 3 times as tall as the plinth width, cladded with four large chamfered granite slabs bound by two dark bronze bands with rivets; one thin vertical rune channel carved up each face, glowing faintly; crown: four inward-curving stone fangs (like a cupped hand) with bronze tips, cradling one floating elongated faceted crystal (team-color glow) that hovers slightly above the crown with a visible gap; one small narrow cloth banner hanging from a bronze bracket on the front face. Top view reads as a square with four fangs and a bright crystal in the centre. Moss on the plinth steps and in the slab seams.

[inner_blue]
Object: INNER lane defense tower (tier 2, sturdier than the outer tower). Silhouette: medium-tall and noticeably thicker, with two flying-buttress stone ribs. An octagonal 3-step granite foundation plinth with an octagonal shaft opening; a thick octagonal stone pillar (about 2.5 times as tall as the plinth width) cladded with large chamfered stone blocks in two courses and three dark bronze bands; two opposite curved stone buttress ribs lean against the pillar from the plinth corners up to two-thirds of its height, joined to the pillar by heavy bronze brackets; crown: a thick stone ring (like a broken halo) on four short bronze arms, holding a larger faceted crystal cluster (one main crystal plus two small shards) floating in the ring's centre; two cloth banners hang from the tops of the buttresses. Top view reads as an octagon with a ring and two buttress arms.

[base_blue]
Object: BASE high-ground defense tower (tier 3, the strongest lane tower, guarding the base entrance). Silhouette: broad, heavy and fortress-like — the widest and strongest silhouette of the family, only slightly taller than the inner tower. A wide square 3-step granite foundation with chamfered corners and a square shaft opening; a massive square keep-like pillar with four corner buttress columns, battered (sloped) lower walls of large stone blocks, three dark bronze bands with big rivets and an armored bronze ring near the top; crown: a crenellated stone parapet with four bronze-capped corner spires, inside it a large floating faceted crystal core (team-color glow) surrounded by three small orbiting crystal shards; carved rune channels on the four faces; two larger cloth banners on the front corners. Top view reads as a square fortress with four spires and a bright core.

[core_blue]
Object: the STAR CORE — the team's final crystal nexus (destroying it ends the match). Monumental and the visual focal point of the base, larger than every tower but wide rather than tall. A wide circular ancient sanctuary platform of grey-green granite: three low concentric steps with four short stairways (front, back, left, right), worn and mossy, rune circles carved into the top floor glowing faintly; six standing stone monoliths arranged evenly around the rim, each bound with a dark bronze band and holding a small team-color crystal shard on its top; in the centre a low round stone altar with a bronze socket ring; above it a GIANT floating faceted crystal cluster (one huge elongated double-pointed main crystal with a cluster of smaller crystals around its lower half) glowing with team-color inner light, held in place by three broken stone arch fragments curving up around it and a bronze armillary-style ring circling its waist. Here the 'shaft opening' of the family is the altar socket the crystal hovers above. Top view reads as a large circle with six dots and a bright centre. Total height about 0.8 times the platform diameter.
```

### D2. 環境（新規。env_art + env_object + 個別 + common_exclude_env）

塔の `break`（分解できる組み立て）とチーム色の指定は付けない。env_art は塔の art から結晶・チーム色の文を抜いたもの。

```text
[env_art]
Art direction: high-end stylized semi-realistic MOBA environment art (painterly but physically grounded PBR materials, like a premium modern mobile MOBA; neither photoreal nor low-poly). World theme: ancient stone ruins coexisting with lush nature. Priority: silhouette > large light/shadow masses > material separation > mid-scale forms > fine details. Stone is heavy weathered grey-green granite with thick chamfered edges, chipped corners, thin moss and lichen in crevices and on top surfaces, matte. Palette: deep forest green, blue-green, grey stone, muted earth brown; nothing glows. Light: one warm-neutral key light from the upper left, soft sky fill, clear form shadows and ambient occlusion in crevices that show thickness and weight.

[env_object]
Image type: single-object concept for image-to-3D. Show exactly ONE environment object, whole and uncropped with margin on all sides, centred, viewed three-quarter from above at about 45 degrees (like a MOBA game camera) so the top surfaces and the top-view silhouette are clearly readable. Plain flat light-grey (#d8d8d8) background, soft even studio lighting, no cast shadow on the background, no ground diorama, no display pedestal. The object's bottom is flat and includes its own small skirt of soil, pebbles and low grass so it will look embedded in the terrain.

[cliff_rock]
Object: a wide cliff rock wall segment for a jungle wall, about 4 m wide, 2 m tall and 1.5 m deep. Three or four heavy stacked grey-green granite boulders with thick rounded-chamfered edges and broad flat facets, clear horizontal strata, chipped corners and deep cracks with darker cool grey-green occlusion. Moss and short grass grow on the top surfaces following the rock forms and drape irregularly over the upper edge, thinning out on the vertical faces (NOT a flat green cap). Small ferns and roots in the cracks. At the base, fallen pebbles, packed soil and low grass blades so the rock sits IN the ground. Uneven top silhouette; the base outline is a long rectangle with rounded ends so it can line up along a wall edge. No ruins, no crystals, nothing glowing.

[shrub]
Object: a low dense shrub, about 1.6 m wide and 1.0 m tall, wider than tall with a rounded silhouette. Chunky clusters of broad leaves in deep forest green and blue-green, soft yellow-green highlights on the top leaves and darker teal-green undersides, a few woody twigs visible inside, moss and roots where it meets the ground. At most a few tiny muted flowers. It must read clearly as a shrub, not as tall grass.

[tall_grass_clump]
Object: one clump of tall wild grass used as a hiding bush in a MOBA, about 1.2 m tall and 1.2 m wide. Dense long narrow blades in deep green and blue-green with lighter yellow-green tips, blades leaning outward in a fountain shape, a few broad leaves and seed heads, darker and denser at the base with soil showing between the stems. Readable from the 56-degree top-down camera as vertical blades (not round leaf clumps). Matte, no flowers, no glow. (Color and shape reference for the procedural brush blades and for a blade-card texture; not meant for image-to-3D.)

[common_exclude_env]
Exclude: HUD, UI, text, letters, numbers, logos, watermarks, people, characters, unrelated extra objects, extreme wide-angle distortion, fog, smoke, particles, glowing elements, team colors, gold or brass trim, cream-beige stone, crimson paint, plastic shine, strong rim light, noisy micro-detail, over-ornamentation, merging the object into the background.
```

### D3. 地面タイル（Codex、`stage_art.py` の tile として。シームレス化は `stage_bake.py`）

```text
[env_tile]
Seamless tileable top-down ground texture, square, viewed straight from above (orthographic, no perspective, no horizon, no object shadows, no lighting direction). Stylized semi-realistic MOBA terrain: painterly but physically grounded and matte, soft value variation at several scales, no single large feature, uniform density so it tiles on all four edges. Palette: deep green, blue-green, grey-green stone and muted earth brown. Keep it calm and slightly darker than the characters so units on top stay readable. No text, no border, no vignette, no glow, no team colors.

[paving]  (period 5 m)
Weathered grey-green granite flagstone paving of MIXED sizes — large slabs 60 to 120 cm across with smaller filler stones between them — in an irregular layout with no repeating grid. Some slabs cracked, chipped or slightly sunken, worn smooth in the middle; wide joints filled with dark soil, moss and short grass; a few spots where a stone is missing and packed earth shows. Low contrast between slabs.

[dirt]  (period 7 m)
Packed earth lane path: muted brown and grey-brown compacted soil with fine grit and small embedded pebbles, faint foot-worn smoothing, a few shallow cracks and darker damp patches, a little scattered dry grass. Desaturated, not orange, not red, no large polygonal mud plates.

[grass]  (period 6 m)
Short lush meadow grass in deep green and blue-green with soft yellow-green sunlit patches, small clover and moss clumps, very few tiny muted flowers, low-contrast detail at several scales.
```

## E. 塔の構造と演出

時刻と部品名は `App/Battle/Render/TowerTimeline.swift` が正（この節は意図の説明）。部品名の子メッシュは `tools/structures/tower_parts.py` が書く。

### E1. 部品表（塔）

| 部品 | 中身 | 立ち上がり | 稼働 | 破壊 | 破壊後 |
|---|---|---|---|---|---|
| `part_plinth` | 段の基壇・竪穴・角の柱 | **固定**。紋様の点灯・継ぎ目の砂 | 固定 | 固定（粉塵の出所） | **残る**（破損した基壇・地面の亀裂） |
| `part_lower` | 中央支柱の下半 | 竪穴からせり上がる（**可動**、行き過ぎ・跳ねなし） | 固定 | 上端の継ぎ目で**破断** | **残る**（折れた根元） |
| `part_upper` | 支柱の上半・外装板・帯・旗 | 下半と一緒に上がり、外装板が閉じて留め具がかかる | 固定 | 奥へ傾いて**落下**、大きな塊 3 つに分かれる | 瓦礫 → 整理で消える |
| `part_crown` | 頂部（牙・環・胸壁） | 最後に開いて収まり**ロック** | 固定 | **落下**（上半とは別の塊） | 瓦礫 → 消える |
| `part_crystal` | 魔力コア | 暗いまま → 最後に下から点灯 | 浮遊・回転・脈動（**可動**） | 異常発光 → 割れて失活・落下 | 結晶片 → 消える |

Core は `part_plinth`（聖域の台座。残る）・`part_upper`（石柱 6 本と壊れた弧。終幕で倒れる）・`part_crystal`（大結晶と青銅の環）。
新しい Core では手続きの発光の回転リング（`ringA` / `ringB`）と塔の周回する結晶片（`shards`）を使わない（旧の見た目の経路だけに残す）。

形の規則: 基壇の段は合計 0.5 m 以下（ユニットが縁に乗って見えても不自然でない高さ）。足跡は 3.6 m 未満（今の検査）。
破断面は中身の詰まった石（内側は暗い石 + 錆びた鉄の芯。`outer_parts` の右上）。中空にしない。
`part_lower` の上端は最初から破断面で作り、稼働中は `part_upper` の下端の内側に隠す。原点（回転の中心）は部品ごとに
基壇 = 足跡の中心の地面、下半 = 底の中心、上半 = 破断の継ぎ目の奥側の縁、頂部 = 底の中心、結晶 = 中心。
倒れる向きは**奥（北）± 30°**（手前に倒すと戦闘を隠す）。向きは塔の id から決め、毎回同じにする（乱数を時刻で引かない）。

### E2. 状態遷移

| 状態 | 時刻（起点） | 見た目 |
|---|---|---|
| 未出現 | 試合開始前（読み込み画面の裏） | 基壇だけ。竪穴は石の扉で閉じ、紋様は暗い（`outer_states` の 1） |
| 立ち上がり | sim 時刻 0〜0.3 / 〜1.3 / 〜1.9 / 〜2.4 | 紋様の点灯と砂 → 支柱がせり上がる → 頂部が収まりロック → 魔力が下から上へ流れ結晶が点灯 |
| 稼働 | 2.4〜破壊 | 結晶の浮遊と脈動。下の重ねを足す |
| 破壊進行 | deathTime + 0〜0.2 / 〜0.6 / 〜1.5 / 〜2.3 | 稼働光の停止・結晶の異常発光・粉塵 → 亀裂・接合部の破断 → 上部が奥へ傾き大塊で落ちる → 着地・低い粉塵 |
| 瓦礫 | + 2.3〜4.8 | 低い瓦礫のシルエット（根元・大塊 3・暗い結晶片・小破片） |
| 消失処理 | + 4.8〜6.3 | 小破片 → 結晶片（小さなチーム色の粒になって上へ）→ 大きな石（表面から崩れて沈む）の順 |
| 破壊後 | + 6.3〜 | 破損した基壇と根元だけ。接地の陰は基壇の分を保つ |

立ち上がりは塔の稼働（sim では t = 0 から攻撃できる）を待たせない。見た目だけ。試合途中からの観戦・シーク・再接続では
時刻の関数なのでその時刻の姿になる（2.4 秒より後なら最初から稼働の姿）。

| 重ね | きっかけ | 見た目 | 上限・省略 |
|---|---|---|---|
| 攻撃 | 塔が source の `attackReleased` | 結晶の短い閃光（約 0.15 秒）とルーンの溝の脈動。弾は結晶の位置から | 弾（攻撃対象を示す表示）は省略しない |
| 被弾 | 塔が target のダメージ | 結晶の明滅、当たった側に石の粉（既存の hitSpark） | 1 基 0.15 秒に 1 回まで。超えた分は装飾を省く |
| 損傷 1 | HP 割合 < 0.7 | ひび・欠け、結晶の明るさを少し落とす | 段階は毎フレーム HP から `damageStage` で求める（積み上げない） |
| 損傷 2 | HP 割合 < 0.35 | 外装板 1 枚の脱落・帯の曲がり・割れ目からチーム色の漏れ | 漏れの粒子は 1 基 1 放出体まで |
| 凍結 | キットの構造物の凍結（`canAct` が偽） | 結晶の回転・脈動を止める（構造物専用の凍結表示は今は無い。足すかは要判断） | 攻撃しない間は攻撃の重ねも出ない |

損傷の表現に追加の部品名（外装板 1 枚など）が要る場合は、`TowerTimeline` のコメントと `tower_parts.py` を同時に更新する。
契約の 5 部品名は変えない。

### E3. Star Core の終幕（Core の deathTime から。全員の画面で同じ）

| 区間 | 時刻 | カメラ | 出来事 |
|---|---|---|---|
| 寄り | 0〜0.6 | ゲームカメラのまま Core へ寄る。HUD・ミニマップを隠す | 最後の一撃で大結晶が白熱し、光の亀裂が走る |
| 回り込み | 0.6〜4.0 | 低い第三者視点で Core の周りを回る | 6 本の石柱の結晶が順に消灯 → 青銅の環が曲がる → 弧が外へ倒れる → 大結晶が大きな破片に分かれて浮く → 光の柱 → 一点へ収縮 |
| 落ち着き | 4.0〜5.2 | 引きの構図（画面の左にリザルトの余白） | 地面を走る衝撃波の輪、破片が台座へ重く落ちる、粉塵が外へ |
| リザルト | 5.2 | 固定 | 勝敗のバナー |

試合が終わると sim は止まるので、終幕の時刻は `RenderFrame.presentationTime − Core.deathTime`（終了後も実時間で進む）で求める。
終幕は**Core の破壊で終わった試合だけ**。降参・時間切れ・中断は今の流れのまま（すぐリザルト）。

視界の情報を漏らさない理由:
- 構造物は両チームに常に見える（`VisionSystem.isVisible` が構造物は true を返す。破壊後の残骸も）。終幕が映すのは Core と、
  誰の画面でも同じ時刻（オンラインでも決定論的に同じ deathTime）の同じ出来事だけ。
- ユニットの表示は今の視界の判定のまま（`RenderFrame.isVisible`）。終幕の間も霧・見えないユニットの非表示を外さない。
  カメラの構図を変えるだけで、見える物の集合は変えない。
- カメラは Core を注視点に固定し、Core から一定の距離の外を映さない。観戦者の追従対象も切り替えない。
- 試合はすでに終わっていて、映った物から得をする操作がない。

## F. 実装計画

### F1. 塔・Core（RealityKit）

- **素材**: 塔は 3 種（外・内・基地）+ Core。USDZ の中の子メッシュ `part_*` を名前で取り出し、部品ごとに `MeshResource` を 1 つ作って
  同じ種類の全ての塔で共有する。材質はチームごと（今の `StructureAssets` と同じ: メッシュ 1 つ・赤はテクスチャの差し替え）。
  チーム色の部位は差し替えられる材質に分ける（色覚配慮モードの橙のため。また今の `structures_bake.py` は色相 165〜300°・
  彩度 0.07 以上の画素を赤へ回すので、青緑の苔・地衣類も赤くなりうる。赤版の画像で確かめる）。読み込みは準備中に 1 度だけ。失敗・予算超過は従来の見た目へ戻す。
- **姿勢の評価**: 部品の変換・不透明度は `(種類, sim 時刻, presentationTime − deathTime, HP 割合)` の純粋な関数で毎フレーム求める。
  前のフレームの値を積み上げない（シーク・再同期・一時停止・リプレイ・重複イベントで同じ見た目）。単体テストは「同じ入力 → 同じ姿勢」と
  「途中から評価しても最初から進めても同じ」を確かめる。試合中の presentationTime は 30 Hz の刻みなので、ユニットの補間と同じ
  `presentationTime − (1 − alpha) × Balance.dt` で滑らかにする（要確認: 実装担当と 1 か所で決める）。
- **画面外**: 詳細の判定（`RenderFrame.detailBounds`）の外の塔は姿勢を更新しない。時刻の関数なので、画面に入った時にその時刻の姿で出る。
- **演出の再利用**: 粉塵・破片・閃光は `VFXSystem` の既存の種類（`smoke` `debris` `towerExplosion` `flash` `ring`）を important で使う。
  倒壊の大塊・小破片は部品と同じく読み込み時に作ったメッシュを、倒壊の同時数（`maxConcurrentCollapses = 2`）分のプールで使い回す。
  小破片は 1 基 `maxSmallDebris = 12` まで。3 基目以降の同時倒壊は粉塵を減らした短縮版。Core の光の柱・衝撃波は Effekseer
  （`tools/effekseer` の DSL）で作ってもよいが、ARView の上に重ねて描く方式なので石柱の陰に回る表現は確認してから使う。
- **音**: 効果音は全て合成（`SFXSynth`、1 音 0.8 秒まで）。立ち上がりは画面内の塔に 1 つだけの低い地鳴り（18 基分を鳴らさない）。
  倒壊は破断（0）と着地（`toppleEnd`）の 2 音。時刻をまたいだ時だけ鳴らし、シークで飛び越えた分は鳴らさない。終幕の後は既存の勝利/敗北の音。
- **状態遷移**: `unit.isAlive` と `deathTime` から状態を決める。`presentationEpoch` の変化（シーク・再同期）は「演出なしで今の時刻の姿」。
  破壊前へ戻るシークは稼働の姿へ戻す（今の `revive()` と同じ扱い）。
- **影**: high は大きな部品（基壇・上半・頂部）だけ影を落とし、小破片・結晶は落とさない。low/medium は基壇の接地の陰を補助マップ R に焼く
  （基壇は最後まで残るので静的でよい）。試合中に補助マップを作り直さない。
- **衝突**: 見た目の部品・瓦礫に当たり判定を持たせない（RealityKit の物理も使わない。動きは全て時刻表の曲線）。判定は sim の
  当たり半径（塔 1.1 m・Core 2.5 m）のまま。瓦礫は基壇の中心から 2.0 m 以内・高さ 0.8 m 以下に収め、歩けそうに見える所を塞がない。
- **遮蔽**: 追従ヒーローを隠す時の半透明（`occludes`）は全部品に掛ける。HP バー・弾の発射点は `part_crystal` の位置から決める。
- **終幕**: `CameraDirector` に終幕の区間を足す（手動操作・自動カメラより優先）。HUD のリザルト表示は `finaleResult` まで待つ。
  低い視点では見える範囲が増えるので、遠方を映さない構図（注視点からの距離・俯角の下限）にする。

### F2. ステージ環境

- 判定に合わせる規則は `docs/STAGE.md` §1 のまま（硬い物は壁の足跡の中、北の辺は低く、レーン 3.5 m・泉/Core 18 m 以内に背の高い物を置かない、
  草むらの縁は矩形どおり、地面近くのはみ出しは 0.4 m まで）。`StageTests` を通す。
- 石畳: 配合マップで「整った石畳 → 欠けた石畳 → 土」の勾配を作る（Core から外へ）。縁は M1 の縁石・段の小物で区切る。
- 土と草: 境目に草の房・小石を置く（今は避けている）。高さ付き混合の幅を狭め、草が土に被さる縁を作る。
- 接地: 塔・Core・泉・門柱の足元を補助 R に入れる。岩・崖の根元に M4 の裾（小物の一部としてモデルに含める）。
- 植生: 3 層の配色を揃え、壁際ほど密にする。追加は共通の小物予算（60万/70万/80万）の中で。上限に達したら優先度の低い物から省く
  （壁の芯・草むら・祭壇の床は別経路なので省かれない）。
- アトラスは 2048×1024・8 セルのまま。セルの割り当て（新しい岩・低木・遺跡・川岸）は差し替えで行う。上限を広げる時は性能契約を先に改める。
- 泉・門柱・ランタンは手続きメッシュから素材の経路（USDZ か小物のセル）へ移す。`fountainSpires`（2 本、回転）の契約は保つ。

### F3. 予算と上限（引き上げない）

| 対象 | 上限 | 検査 |
|---|---|---|
| 塔 1 種（結晶以外の部品 + 瓦礫） | 6,000 三角形、テクスチャ 1024 px | `StructureAssetsTests` |
| 結晶（塔・Core） | 2,500 三角形 | 同上 |
| Core（台座 + 石柱と弧） | 6,000 三角形 | 同上 |
| 倒壊の同時数・小破片 | 2 基・1 基 12 個 | `TowerTimeline` |
| 小物・地形 | 60万/70万/80万、チャンク 90万（high 100万）、草むら 9万 | `StageTests` |
| 戦闘中の生成 | 0 件（新しい経路は `AssetLedger.record` を通す） | `PerfReport.ledger.live` |

塔の種類が 1 → 3 に増えるのでテクスチャのメモリが増える。ピークメモリを前後で記録する（必要なら発光テクスチャを 512 px に）。

### F4. 計測（実機の結果はまだ無い。FPS の改善・悪化を断定しない）

- 同じ端末・Release・同じ seed・画質・速度・時間で、旧（`-legacyStage -legacyStructures`）と新を比べる。
  `tools/perf_run.sh --seconds 150 --speed 4 --quality medium --out build/perf/<名前>.json`。自動画質調整の履歴も保存する。
- 場面: (1) 試合開始の立ち上がり（拠点の塔が画面内）、(2) 2 基の同時倒壊（`-towerDemo`）、(3) Core の終幕（`-coreFinaleDemo`、低い視点で
  映るチャンクが増える）、(4) 通常の 150 秒。`sync.units`・`sync.map`・`sync.effects`・`sync.effekseer` の合計 ms と最大 ms、ヒッチ、ピークメモリ。
- 実機は Instruments の Time Profiler / Animation Hitches / Metal。最新世代 1 台と、iOS 18 対応の古い世代 1 台（機種は手元の実機で決める）。
  温度・低電力モード・メモリを併記する。シミュレータの値は CPU の詰まりと生成 0 件の確認だけに使う。

## G. 比較素材の作り方

起動引数（DEBUG）: `-legacyStage`（今の 10/05 版ステージ。素材が無い時の手続きの地形ではない）・`-legacyStructures`（旧構造物）・`-towerDemo`（1 基の立ち上がり → 損傷 → 倒壊 → 瓦礫 → 整理を
繰り返す）・`-coreFinaleDemo`（Core の終幕）。**名前はこの文書で固定し、各担当が実装する**（d6aaf94 時点では未実装）。

1. ビルド（自分の DerivedData・`ARCHS=arm64`）と自分専用のシミュレータ（`xcrun simctl create <名前> "iPhone Air"`、終わったら削除）。
2. 静止画: 同じビルドで旧と新を同じ地点で撮る。
   ```
   STAGE_APP=<dd>/Build/Products/Debug-iphonesimulator/VELSTRIA.app WAIT=30 tools/stage/stage_shots.sh <UDID> build/sr/new \
       10,10,1.0 46.6,50,0.9 33.9,37.1,0.9 24,24,0.9 56,30 60,60 83,37
   STAGE_APP=... WAIT=30 tools/stage/stage_shots.sh <UDID> build/sr/old <同じ地点> -- -legacyStage -legacyStructures
   ffmpeg -i build/sr/old/stage_10_10_1.0.png -i build/sr/new/stage_10_10_1.0.png -filter_complex hstack build/sr/cmp_base.png
   ```
   地点: 青の拠点（泉・Core）/ mid の外塔 / 内塔 / 基地塔 / ジャングル / 川の中央 / 星喰竜の巣。`GRAPHICS=low|medium|high` を揃える。
3. 動画: `-towerDemo` / `-coreFinaleDemo` で起動し、`xcrun simctl io <UDID> recordVideo --codec=h264 --force out.mp4` を
   バックグラウンドで回して SIGINT で止める（`tools/skillfx/capture.sh` と同じ手順）。コマ割りは
   `ffmpeg -i out.mp4 -vf "fps=4,scale=480:-1,tile=4x4" sheet.png`。
4. 見る前に `sips -Z 1000` で縮める。キャプションに commit・画質・端末・起動引数を書く。
5. 注意: シミュレータではブルーム・色調補正が出ない（発光の強さは実機で判断）。観戦の試合は時刻でユニットの位置が変わるので、
   地形・構造物だけを比べる。
