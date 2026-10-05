# ヒーローの 3D アセット（Tripo 生成）

このフォルダの `.usdz` はアプリのバンドル直下へ平らにコピーされ、`HeroAssetLibrary`（App/Battle/Heroes/SkinnedHeroModel.swift）が
`Bundle.main.url(forResource:withExtension:)` で探す。無いヒーローは手続き生成モデル（HeroModel）のまま表示される。
この README は project.yml の `**/*.md` 除外によりバンドルへ入らない（フォルダを保つための置き場所）。
ファイルは手で置かず、`node tools/tripo.mjs import ...` の関門（下記）を通して置く。

## 命名規約
| 種類 | ファイル名 | 例 |
|---|---|---|
| ヒーロー本体（既定スキン） | `Hero_<heroID>.usdz` | `Hero_H001.usdz` |
| スキン別の本体 | `Hero_<heroID>_<cosmeticID>.usdz` | `Hero_H007_CO007.usdz` |
| 武器・副手 | `Prop_<kind>.usdz`（`WeaponKind` / `OffhandKind` の case 名） | `Prop_broadsword.usdz`, `Prop_gateShield.usdz` |

- スキン別の本体が無いスキンは、既定の本体にスキンの基調色を薄く掛けて表示する（Epic のオーラは従来どおり）。
- 武器名が両方の enum にある Prop（glassDagger, petalBlade, dreamNeedle）は 1 ファイルを左右で共用する。
- stoneFist（H007）・azureClaw（H022）は体に付ける装着物で、本体のメッシュに含める。スキンモデルでは Prop としても
  手続きメッシュとしても付けない（`SkinnedHeroModel.bodyWornGear`。前腕追従用の空の entity だけ残す）。
  `Prop_stoneFist.usdz` / `Prop_azureClaw.usdz` は置いても読まれず、assets.json の `bodyWorn` により取り込みもしない。

## ヒーロー本体（normalize_hero.py の出力）
- Y 上・メートル・正面 -Z・右手 +X・足元 y = 0・腰（Hips）を水平原点・身長 1.70 m（外接箱の高さ）。
- UsdSkel のスキンメッシュ 1 つ・スケルトン 1 つ、レスト = バインド。UsdPreviewSurface（テクスチャ 1024 px 以下、
  不透明な PNG は JPEG 化）。
- レストは T ポーズでも A ポーズでもよい（Tripo Studio の Mixamo リグは腕が約 60° 下がる）。実行時（HeroSkeletonRig）が
  四肢の骨ごとにレストの向きを手続きのレスト方向（真下）へ補正する。腕の下がり角はレポートの `armDownDegrees`
  （-5〜70° の外は警告）。
- 必須の骨（`HeroJointRole.required`）: Hips, Spine, Head, LeftArm, LeftForeArm, LeftHand, RightArm, RightForeArm, RightHand,
  LeftUpLeg, LeftLeg, RightUpLeg, RightLeg。欠けると実行時は手続きモデルへ戻す。
  照合規則（`HeroJointRole.normalize`）: USD の joint パスの最後の要素を小文字にし、先頭の `mixamorig` + 数字 + `:` / `_`
  を 1 回だけ外して完全一致（`mixamorig_LeftArm`・`mixamorig1:LeftArm`・`LeftArm` は可、`Left_Arm`・`L_Arm` は不可）。
  Blender の USD 書き出しは骨名の `:` を `_` にする。
- 任意の骨: Spine1/Spine2（背骨の分担・翼の位置）、Neck、Left/RightShoulder、Left/RightHandIndex1（握りの位置）、
  Left/RightFoot・Left/RightToeBase（向きの判定）。

### 向きと左右（正規化の判定）
- 向き（auto）: 左右の Foot → ToeBase の水平方向の平均。左右そろって水平に近く（水平成分が長さの 50% 以上）互いに 45° 以内なら
  「確か」。つま先が無ければ腕・脚の左右（上 × (Right - Left)）。90° 単位に近ければ（±20°）スナップする。
- 不合格（終了コード 1、レポートの `errors`）:
  - 必須の骨が実行時の規則で見つからない（書き出し前の骨名と、書き出し後の USD の joints の両方で調べる）
  - 確かでないつま先（片方だけ・互いに 45° 超）と腕・脚の向きが 45° 超食い違う（`--forward` で明示すれば通る）
  - 正面を -Z へ回した後で Right* の骨（RightArm / RightUpLeg / RightHand の平均）が Left* より +X 側にない
    （左右の名前が入れ替わったリグか鏡像のメッシュ）
  - スキンがダミー（HeroPose が曲げる骨のどれかが 1 頂点も支配しない、または 1 本が半数超を支配）
  - 骨とメッシュの食い違い（主要な骨がメッシュの外接箱 +5% の外、腰・頭・足の高さの割合が範囲外）。
    Tripo の GLB で起きたら、同じリグの FBX を `build/tripo/<cat>/<id>/rigged.fbx` に置くと取り込みがそちらを使う。

## 武器・副手（normalize_prop.py の出力 = Prop 空間）
- 静的メッシュ。握りが原点、長さ方向 +Y（y = -grip … 1 - grip、長さ 1.0 m。実行時に手続きメッシュの Y の長さへ拡縮）。
  握りは assets.json の `grip`（下端から長さの割合）の断面中心。
- 長軸（面積重み付き PCA。鉛直から 30° 以内なら元の上、`axis: vertical` なら元の上そのまま）を Y、最も薄い向きを ±X に置き、
  元モデルの正面（Tripo の glTF +X = コンセプト画像で見る側）を +X 側にする。このとき画像の右は -Z、左は +Z。
  最後に assets.json の `yaw`（Y 軸回り）を掛ける: +90 で正面 -Z、-90 で正面 +Z、180 で正面 -X。
- `side: gun` は上面（面積の多い側）が +Z かを確かめて逆なら警告、`side: bow` は弦の側を +Z へ回す。
- 実行時（`SkinnedHeroModel.propFit`・`HeroGearBuilder.propMount`）: Y の長さを手続きメッシュに合わせ、横の広い向き（X と Z の
  幅が 1.25 倍以上違う側）が手続きメッシュと食い違えば Y 軸回りに 90° 回し、種類ごとの残りの回転と置き方を足す。
  下表の「Prop 空間」はその回転前の形（取り込みの検査が見る形）、「手続き」は HeroGear.swift の weapon() / offhand() の形。

| kind | grip | 正規化 | Prop 空間（yaw 後） | 手続き（HeroGear） / 実行時 |
|---|---|---|---|---|
| broadsword | 0.10 | | 刃の面 ±X、刃幅・鍔 ±Z、切先 +Y | 同じ |
| starRapier | 0.12 | | 細身の刃 +Y、椀鍔、護拳 -Z（画像の右） | 護拳は YZ 面の z = -0.04、星の柄頭の面 ±X |
| tideStaff | 0.32 | | 杖 +Y、頭の三日月と飾りの面 ±X（広がり ±Z） | 三日月は XY 面（広がり ±X）→ 実行時 90° 回す |
| lightningSpear | 0.27 | | 稲妻形の穂先の面 ±X（広がり ±Z）、穂先 +Y | 同じ |
| crescentDagger | 0.18 | | 刃の面 ±X、三日月の刃先 -Z | 同じ |
| windBanner | 0.30 | | 柄 +Y、葉形の穂先の面 ±X。旗布なし | 旗布は実行時の手続きメッシュ（flagAnchor y = 1.14） |
| mechCrossbow | 0.35 | yaw -90, side gun | 銃床 +Y、弓 ±X、上面（矢溝・照準）+Z、最も薄い Z | 同じ（広い向き X が一致するので回さない） |
| handFlame | 0.15 | 任意 | 炎 +Y（回転対称） | 既定は手続きの発光のまま |
| aegisStaff | 0.30 | | 杖 +Y、頭の翼飾りは ±Z に広がる | 同じ |
| glassDagger | 0.20 | 左右共用 | 結晶の刃 +Y、鍔の結晶 ±X | 同じ |
| boneClub | 0.15 | | 棍頭 +Y（回転対称） | 同じ |
| mistKatana / shortBlade | 0.12 / 0.15 | | 刃の面 ±X、刃（反りの外側）-Z、切先 +Y | 同じ（shortBlade は 0.62 倍） |
| bellBlunderbuss | 0.33 | side gun | 銃口のラッパ +Y、上面（撃鉄）+Z | 同じ |
| haloStaff | 0.30 | | 杖 +Y、光輪は YZ 面（面 ±X） | 光輪は XY 面 → 実行時 90° 回す |
| abyssCenser | 0.94 | | 上端の吊り輪が握り、本体は -Y に吊り下がる | 同じ（本体 y = -0.4） |
| petalBlade | 0.20 | 左右共用 | 花弁形の刃の面 ±X、+Y | 同じ |
| siegeHammer | 0.20 | | 柄 +Y、槌頭の長さと打撃面 ±Z、面 ±X | 同じ |
| lightArrowBlade | 0.20 | | 矢じり形の刃の面 ±X、鍔 ±Z、+Y | 同じ |
| sandRifle | 0.29 | side gun | 銃身 +Y、上面（照準器）+Z | 同じ |
| thunderLance | 0.20 | | 円錐の槍 +Y（回転対称）、椀鍔 | 同じ |
| dreamNeedle | 0.13 | 左右共用 | 針 +Y（回転対称） | 同じ |
| gateShield | 0.50 | yaw 90 | 盾面（正面）-Z、城壁の上辺 +Y、幅 ±X、最も薄い Z | 同じ形を腕の外へ（propMount center, ry(0.4)） |
| harpBow | 0.10 | yaw 90 | 竪琴の面（正面）-Z、角 ±X、底の握り棒から +Y | XY 面（propMount center） |
| ashBow / lightBow | 0.50 | side bow | 弓は YZ 面（面 ±X）、弓先 ±Y、弦と反った弓先 +Z、腹 -Z | bow() と同じ、実行時 ry(0.6) |
| moonLantern | 0.95 | | 上端の吊り輪が握り、灯籠は -Y に吊り下がる | 同じ |
| grimoire | 0.50 | yaw 180 | 表紙（正面）-X、高さ +Y、幅 ±Z、厚み ±X | 同じ（留め具 -Z、propMount center） |
| hideShield | 0.50 | axis vertical, yaw 90 | 丸盾の面（中央の突起）-Z、元画像の上 +Y、最も薄い Z | 同じ（propMount center） |
| stoneFist / azureClaw | - | bodyWorn | 取り込まない | 付けない（本体に含む） |

## 生成（tools/tripo.mjs run）
- ヒーロー: concept（画像）→ model（P1 image-to-model、face_limit 10000、PBR・HD テクスチャ）→ rigcheck → rig（Mixamo 骨の biped）。
  進捗は `tools/tripo/state.json`、ダウンロード物は `build/tripo/heroes/<ID>/`（`concept.png` / `model.glb` / `rigged.glb`）。
- 既定の concept は Tripo の text-to-image（`assets.json` の `style` + ヒーロー別の `prompt`、5 credits）。
- `--concept-source fullbody`: concept を Tripo で作らず、`tools/heroref/fullbody.py` が作った全身 T ポーズの採用版
  `build/heroref/<ID>/fullbody.png`（`HEROREF_BUILD_DIR` で変更可）を `concept.png` へ写す（0 credits、PNG・256 px 以上・20 MB 以下）。
  model はその `concept.png` を `POST /files`（無料）で上げた file_token を `input` にして作る（予算・残高の確認を通った後、送信の直前に上げる）。
  ```sh
  python3 tools/heroref/fullbody.py generate H004 --tag t1 && python3 tools/heroref/fullbody.py select H004 t1
  node tools/tripo.mjs run heroes H004 --concept-source fullbody --dry-run      # 計画だけ（送信・state・ファイルに触れない）
  node tools/tripo.mjs run heroes H004 --concept-source fullbody --until rig    # 85 credits（model 60 + rig 25）
  node tools/tripo.mjs import heroes H004
  ```
  - state.json の concept は `local: true`・`task_id: null`・`source {kind, path, sha256, tag, width, height}`・`credits_consumed: 0`。
    model には上げた画像の控え `upload {file, sha256, file_token}` が残る（API キーは残さない）。
  - 前回の concept が Tripo 製か、sha256 の違うローカル画像なら、concept 以降（model / rigcheck / rig。`--until` より後の段階も）を
    `--force` と同じく `history` へ移して作り直す。同じ画像なら何も作り直さない。
  - 一度ローカル画像にした concept は、`--concept-source` を付けない run でも `concept.png` を上げて使い続ける
    （`concept.png` が記録の sha256 と違えば止まる → `--concept-source fullbody` で写し直す）。Tripo の画像へ戻すなら `--force concept`。
  - 参照画像が無い・使えないヒーローが 1 体でもあれば run は何も始めない（`--dry-run` は一覧を出して終了コード 1）。
- タスクは作った API キーからしか見えない。キーを差し替えると古いタスクの `GET /tasks/{id}` は存在しないタスクと同じ
  HTTP 404 / code 2001 になる（ダウンロードし直し・再開・`task` はその旨を表示する）。作り直しは新しいタスクなので影響しない。

## 取り込みの関門（tools/tripo.mjs import）
1. `normalize_hero.py` / `normalize_prop.py` で一時ディレクトリ（`$TMPDIR/velstria-import-*`。このフォルダの外）へ正規化する。
   不合格なら理由がレポート（`build/tripo/<cat>/<id>/import_report.json` の `errors`）に残る。
2. `tools/blender/verify_usdz.swift`（`build/tripo/verify_usdz` に swiftc で 1 度だけコンパイルし、ソースより新しければ再利用）で
   RealityKit から読み直して検査する。
   - ヒーロー・スキン: `--expect hero --height 1.7`（必須の骨・レスト = バインド・RightArm が +X・つま先が -Z・ダミーのスキン・
     骨がメッシュ内・足元 0・身長・腰の水平位置）
   - Prop: `--expect prop --grip <grip> --length 1 --thin-axis <x|z|any> --long-axis <y|any>`。薄い向きは yaw ±90 なら z、
     0/180 なら x。長軸 y（Y が最も長い）は薄い向きが x で `axis: vertical` でないときだけ。
3. 終了コード 0 のときだけこのフォルダの `<name>.usdz` へ rename で置き換える。不合格なら既存のファイルはそのまま、
   state.json の `import.status` は `failed`（`stage: normalize | verify`）、不合格の出力は `build/tripo/<cat>/<id>/rejected_<name>.usdz`。
- `--dry-run` は 3 段のコマンドを表示するだけ。`TRIPO_STATE_DIR` / `TRIPO_BUILD_DIR` / `TRIPO_RESOURCES_DIR` で置き場所を
  一時ディレクトリへ向けると、リポジトリに触れずに取り込みを試せる（合成リグは `make_test_rig.py -- --variants` の
  `build/tripo/test/variants/*.glb`）。
