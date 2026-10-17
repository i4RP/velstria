# スキル演出を MLBB に近づける（2026-10-17〜）

10 体（H025〜H034）のスキル演出の輪郭・色・動き・発生の時刻・残光を、オーナーの MLBB の画面収録 12 本に近づける作業の記録。
判定・数値（`Kit_H0xx.swift`・VelstriaCore）は変えない。見た目（`App/Battle/SkillFX`・`App/Battle/Render/SkillFX`）とカメラだけ。
ブランチ `vfx/mlbb-parity`（main へのマージはこの作業の範囲外）。

## 進め方

1. 比較の基準: 決まった条件でスキルを撃って戦闘画面を撮る（`FXCapture`・`.github/workflows/fx-capture.yml`）。
   従来のカメラの画を残してから、MLBB に合わせたカメラ（[CAMERA.md](CAMERA.md)）に切り替える。
2. 共通の演出の機能: メッシュごとに選べる加算合成、粒子のコマ送り（`imageSequence`）とスプライトシート
   （`tools/vfx_sprites`。Python で作る手続きの画像）、演出用のシェーダー 1 本（流れる模様・色の段階）。
3. ボルグ（H029）の全スキルで使い方を固める → 4. 残り 9 体へ。
5. CI（アプリのテスト・撮影）と、TestFlight で実機の録画（ブルーム・FPS・発熱はシミュレータでは確かめられない）。

## 撮り方

`fxcap-*` のタグを push すると CI がシミュレータ（iPhone 17、Debug、画質 high、練習場 Lv4）で撮る:

```sh
git tag fxcap-<名前> <コミット> && git push origin fxcap-<名前>
```

成果物 `fx-capture-<run>` に `<カメラの組>/<ヒーロー>/<スキル>_<ms>.jpg`（幅 1108 px）と `manifest.json`
（要求・実際の時刻、カメラ、画質、スキルごとの予算の観測）。シミュレータは後処理（ブルーム）が無い。

## 記録

### 2026-10-17 工程 1・2（比較の基準・共通の機能）

- 撮影: `FXCapture`（`-fxCapture`）。練習場の人形の南 4 m に北向きで置き直し（`controller.restore`。sim の規則は変えない）、
  S1・S2・奥義（再使用の段は 2 回目も）を実際の入力で撃ち、発動から 0〜2.8 秒の 10 時刻で ARView を撮る（HUD・Effekseer は写らない）。
  `-fxCaptureRings` で半径 3 m・6 m の水色の輪（カメラの確認用）。CI: `.github/workflows/fx-capture.yml`（タグ `fxcap-*`。
  `--H029_H030` でヒーロー、`@mlbb` でカメラの組を絞れる）、`tools/fx_capture/run_ci.sh`、比較の一覧画像 `tools/fx_capture/compare.py`。
  最初の撮影は撮影コードの型の誤りでビルドが落ちた（fxcap-baseline-1）。2 回目（fxcap-baseline-2、共通の機能を足した後・レシピは従来）が変更前の基準。
- カメラ: `CameraRig.Preset`（legacy / mlbb）。この時点の既定は legacy（同じ日の後半に mlbb を既定にした。下の「工程 5」）。
  mlbb の値の導き方は [CAMERA.md](CAMERA.md)。
- 共通の機能（既定の見た目は変えない）:
  - `FXMesh.blend = .add`（加算）: `CustomMaterial.Program`（blendMode .add・unlit）+ `FXShaders.metal`。フェードは明るさの段階
    （`FXMaterialLibrary.addLevels` = 10）の材質を差し替える（`OpacityComponent` が加算に効くかに頼らない）。
  - `FXMesh.flow`（流れる模様）: 同じシェーダーで、繰り返しの模様（`FXFlowTex`: noise / streaks / cells。256 px、読み込み時に作る）を
    UV で流し、2 色を混ぜ、縁を模様の暗い所から欠けさせる。
  - `FXEmit.sheet`（粒子のコマ送り）: `imageSequence`（4 × 4 = 16 コマ）。スプライトシート 12 枚（`App/Resources/FX/Sheets`、
    512 × 512・白 + アルファ・26〜78 KB、`tools/vfx_sprites/gen_sheets.py` が決まった乱数で作る。目録は `tools/vfx_sprites/manifest.json`）。
    試合に出るヒーローのレシピが使うシートだけを読み込む（アルファ用と加算用の輝度版）。
  - 事前準備: Program は読み込みの始めに作り（`BattlePreload`）、幕の前の待ち合わせ（`warmupGates` の fxPrograms）で材質まで作り切る。
    シミュレータは撮影（`-fxCapture`）の時だけ作る（GPU の無い CI でロードを止めないため。作らない時・作れない時は従来の材質で代える）。
  - 使い回し: メッシュの枠は出すたびに材質（段階・模様）と不透明度を書き直す。放出体はコマ送りの有無を毎回書き直す。
  - テスト（`SkillFXTests`）: 既定がアルファ合成のまま・Program が作れる・加算の段階のフェードと使い回しの戻り・コマ送りの付け外し・
    全シートの同梱・全レシピを準備してからの再生でプレイ中の生成 0。
- 部品: `FXEmit.sheet / groundSheet`、`FXMesh.glowing() / flowing(...)`（`FXKit.swift` 末尾）。

### 2026-10-17 撮影・描画の不具合と直したこと

- 撮影の方式: 最初は ARView の画（`ARView.snapshot`）を書き出したが、HUD と Effekseer が写らないので、撮る時刻に sim・演出の時刻・
  粒子（`simulationState = .pause`）を止め、`/tmp/velstria-fxcap` の合図で CI が `simctl io screenshot` を撮る方式にした（HUD を含む画面。
  合図の done には画の名前を書き、遅れた done で次を撮らずに進まないようにした）。CI のシミュレータでは起動直後に音声の初期化が固まって
  （`AudioService` → `AVAudioEngine` → AURemoteIO の RPC timeout）落ちることがあるので、落ちたら 3 回まで起動し直す。
- 加算・模様の部品が何も映らなかった: unlit の CustomMaterial は `set_emissive_color` の値だけで描く（Apple の
  `CustomMaterial.LightingModel.unlit` の説明: ほかの出力は無視）。`FXShaders.metal` が base_color だけに出していた。
  切り分け（`-fxCaptureProbe`。部品の種類を 1 つずつ足して撮る）で、emissive にも出す単色のテスト用シェーダーだけが映ったことで分かった。
  途中で、法線が無いことも疑って演出の単位メッシュに法線を足した（Unlit の見た目は変わらない。これだけでは直らなかった）。
- カメラの確認（寸法が既知の地面の輪。fxcap-h029v2、MLBB の組）: 半径 3 m・6 m の輪を `measure.py` の写像で当てはめて
  u0 = 553.4・v0 = 293.1・c = 0.7114・q = 6.2 × 10⁻⁴・縮尺 62.5 px/m（残差 1.3 px）。MLBB の画面収録は u0 = 556.7・v0 = 294.6・
  c = 0.7107・q = 7.7 × 10⁻⁴・62.3 px/単位。c・縮尺・足元の高さは合う。q（遠近の強さ）は外側の輪が画面の一部しか拾えず精度が低い（推定）。

### 2026-10-17 工程 3（ボルグ）

[H029.md](H029.md)。S1・S2・再使用・奥義を画面収録に寄せた（予算内）。撮影 `fxcap-h029v1--H029@mlbb`。

### 2026-10-17 工程 4（残り 9 体）

1 体ずつ画面収録のコマを読み、ずれの大きい所から直した（同じ光り方を全員に配らない）。対応・保留・推定はヒーローごとの記録:

| ヒーロー | 記録 | 主な変更 |
|---|---|---|
| H025 ルミナ（ミヤ） | [H025.md](H025.md) | 月光の水色へ。光る部品（気・光の柱・矢）だけ加算、光の檻はアルファ。S1 の気の殻・S2 の光の帯に模様 |
| H026 エウリア（エウドラ） | [H026.md](H026.md) | 紫 → 青白の雷。S1 は扇の 7 方向の雷 + 敵へ伸びる鎖の筋、奥義は直径 14 m の淡い光で画面の閃光の代わり |
| H027 ジャルド（子龍） | [H027.md](H027.md) | 金・青・赤 → 水色・青緑・深紅。三日月は太い → 細いの 3 枚の時間差 + 弧に沿って流れる模様 |
| H028 ザイル（セイバー） | [H028.md](H028.md) | 深紅 + 濃紺の剣（剣が減る組 `FXMesh.group` とテストはそのまま）。飛び出しだけ 1.2 m の星形の板 |
| H029 ボルグ（ティグラル） | [H029.md](H029.md) | 工程 3。炎・煙のコマ送り、光る部品の加算、縁の帯の流れる筋、焦げ跡と光るひび |
| H030 ライナ（ライラ） | [H030.md](H030.md) | 青白の砲。奥義の溜めは青 → 金の 2 段、ビームは加算の帯 + 流れる筋 |
| H031 オーリア（オーロラ） | [H031.md](H031.md) | 氷の青白。雹の砕けはパッシブの 5 点、氷河の縁は最大の幅で 1.1 秒から |
| H032 ディアス（Dyrroth） | [H032.md](H032.md) | レイジ 50% 以上の強化はパッシブのバッジを `countedSlot` にして通常版だけの青紫の部品を消す（強化 ⊆ 通常） |
| H033 ヴァルド（アルカード） | [H033.md](H033.md) | 既定スキンの蒼・藍・瑠璃へ（紅は命中の閃きだけ） |
| H034 ゴルム（フランコ） | [H034.md](H034.md) | 光らない鉄の鎖と鉤。光るのは命中の閃き・S2 の炎の輪・奥義の金の振りと円・闘気の光だけ |

予算はどれも上限の内（Windows の Swift でレシピを組んで数えた。違反 0。数はヒーローごとの記録）。判定・数値・`Kit_H0xx.swift`・
VelstriaCore は変えていない。詠唱モーションも変えていない。

### 2026-10-17 工程 5（撮影の結果・カメラの切り替え・見つけた不具合）

- 撮影 fxcap-after1（c89c874、MLBB の組、iPhone 17 シミュレータ、画質 high、10 体）: 326 コマ。33 のスキル・段のうち 30 を撃てた。
  撃てなかった 3 つ（H027 S1・H028 奥義・H034 奥義）は対象が英雄だけのスキルで、練習場の人形は対象にならない（撮影の範囲外。実機の対戦で見る）。
  326 コマのうち 3 コマ（H025 S1 1.4 s・H026 奥義 2.0 s・H028 S1 0.75 s）は合図の時間切れで ARView の画（HUD 無し）になった。
- 写ったもの: メッシュの部品（加算・流れる模様を含む）は場所・時刻・色が出ている。**粒子（コマ送りのスプライトシートを含む）は CI の
  シミュレータで一度も写らない**（fxcap-probe6moving で粒子を止めずに撮っても写らない）ので、粒子の部品は実機でしか確かめられない。
  ブルーム（後処理）も無いので、シミュレータの画は実機より暗く細い。比較の一覧画像（`compare.py`。MLBB のコマ | 変更前 | 変更後）は
  作業用の手元だけに置いた（MLBB の画面収録はリポジトリに入れない）。
- 見つけて直した不具合（0e0f7da）: ゴルムのスキル2・奥義は「MLBB で光らない振りかぶり」を空の cast にしたが、`SkillFXCatalog.recipe` が
  空の段を既定演出（`FXGeneric`）で補うので、S2 の前に金の魔法陣（selfAoE の runeCircle）と光、奥義の前に光と粒が出ていた（fxcap-after1 の
  S2 0.13〜0.37 s）。`SkillFXRecipe.fillsEmptyPhases = false` で空のまま残す（既定は true。ほかのヒーローは変わらない）。
  10 体のほかの補い（H028・H029・H033・H034 のパッシブの hit、H029・H032 の S2 の telegraph）は再生されない経路（パッシブのダメージは
  `.skill` でない、2 体の S2 はゾーンを作らない）なので触っていない。確認の撮影（fx-capture の手動実行 38987829944、0e0f7da、H034・
  MLBB の組）: S2 の 0.1 s（振りかぶり）は何も出ず、0.33 s に叩きつけの淡い橙の円と外の赤い線が出る。S2 の要求は放出体 3 → 2・
  メッシュ 4 → 3（魔法陣と光が消えた分）。この撮影では Program の作成に 9.7 秒かかった（after1 は 0.5 秒。CI の機械の差か、
  シェーダーのキャッシュの有無か未確認。実機のロードの時間で見る）。
- 見つけて直した不具合（2）: 読み込み幕は 3 秒（`WarmupScheduler.Config.hardCap`）で待つのをやめるので、Program がそれより遅いと、
  幕の後に Program が出来た時点で加算・模様の材質をプレイ中に作っていた（生成 0 の約束を破る。上の撮影の 9.7 秒で気づいた）。
  幕を上げる時に `SkillFXPlayer.sealShadedMaterials()` で、作り切れていなければその試合は従来の材質で出す（`createsShaded = false`）。
  あわせて、従来の材質で代えた加算のメッシュは明るさの段階では変わらず出たまま急に消えていたので、不透明度で落とすようにした。
  撮影（Debug の `-fxCapture`）だけは幕の待ちを 60 秒にして Program を待つ（撮影の目録の `sealed=` で確かめられる）。
- カメラ: 撮影の輪の当てはめが MLBB の画面収録と合ったので（[CAMERA.md](CAMERA.md)）、プレイの既定を mlbb の組にした（42d7868）。
  `-cameraPreset legacy` で従来に戻せる（Debug の起動引数）。

### 2026-10-17 予算の観測（fxcap-after1。画質 high・練習場に 1 体だけ。シミュレータ）

`budgetSnapshot()`（スキルごとに数え直す）の結果。打ち切り（cut）・取り上げ（reclaimed）・拒否（rejected）・合図の破棄（overPerPlay /
overPending）は 30 のスキルすべてで 0。

| | 最大 | どのスキル |
|---|---|---|
| 放出体の同時使用 | 28 / 34（high のプール） | H026 奥義。次は H031 奥義 16、H025 S2 15、H031 S2 14、H026 S2 13 |
| メッシュの同時使用（形ごとの最大の和） | 22 / 103 | H031 奥義。次は H026 S1・奥義 21 |
| 待ちの合図 | 29 / 512 | H032 S1。次は H029 S1 26 |

画質 medium（放出体 22）・low（10）は撮っていない。high で 22 を超えたのは H026 奥義（28）、10 を超えたのは 10 のスキル。
低い画質では `minQuality` の合図が減るので、打ち切りが起きるかは未計測。数え方・上限は変えていない。1 体ずつの撮影なので、
集団戦で重なったときの値ではない。

### 2026-10-17 CI・配信

- テスト（TestFlight の run_tests 付きの実行 #180、7b983ff。macOS 26 の CI、iPhone 17 シミュレータ）:
  - コアのテスト（VelstriaCore 1159 件）: 失敗 0。
  - アプリのテスト: main で前から落ちているもの（CoreFinaleTests.testShotsStayInsideTheMapClearOfStructuresAndFrameTheCore・
    FriendTests.testErasedInboxIsReplacedWithANewCodeAndReconnects・HUDShopTests.testShopStateMarksCurrentBlessingAndProgress・
    BattleHUDUITests.testRankedLeaveIsRecordedAsLoss・testTutorialMoveStepAdvancesWithJoystick（不安定）・
    SpectatorHUDUITests.testSpectatorMenuPanelsSeekTacticalMapAndCinematic・ReplayLibraryUITests.testReplayListDetailAndPlayback（不安定））は
    直していない。このブランチで新しく落ちた 2 件は直した（下）。SkillFXTests は 40 件のうちその 1 件のほかは通った（この作業で足した
    加算・模様・コマ送り・空の段・幕の封じのテストを含む）。
  - 直した 2 件: `SkillFXTests.testLuminaMoonArrowBuffFollowsCastDuration`（H025 の効果中の足元の三日月を外したのに 2 つを数えていた →
    弓のきらめき 1 つ）、`SpectatorCameraTests.testFollowCentersEveryEdgeAtEveryZoom`（注視点の前ずれが 0 の前提だった → 同じファイルの
    ほかのテストと同じく `focusLead` を足して比べる。端で丸めないことは変えずに確かめる）。
- 配信: build 24973840（7b983ff、#179）が内部グループ In に届いた（テスター 2 人）。その前の 24971429（42d7868）には
  ゴルムの直しと幕の封じが入っていない。
- 撮影 #16（7b983ff、H029・H034、MLBB の組）: どちらも `sealed=false`（Program を待ってから幕を上げた）。H029 の回は Program の作成に
  7.2 秒かかった。予算の打ち切り 0。H029 の放出体の最大は S1 15・S2 18・奥義 10（after1 は 12・12・7。同じレシピで回によって違う。
  理由は調べていない）。

### 実機で確かめること（TestFlight の build 24973840 以降。練習場で 10 体の S1・S2・奥義を撃って画面を録画）

- 粒子の部品（コマ送りのスプライトシートの炎・煙・火花・雷など）が出ているか・大きさ・向き（CI では一度も写らない）。
- 加算の部品の明るさ・白飛び・ブルームの掛かり方（シミュレータには後処理が無い）。暗い所・明るい所での見え方。
- 読み込みの時間と、`fx programs built in … ms` / `fx shaded materials not ready at curtain` の記録（性能記録。幕に間に合わなかった試合は従来の材質）。
- FPS・発熱（集団戦で演出が重なったとき。画質 medium・low で放出体の打ち切りが起きるか）。
- カメラの操作感（mlbb の組: 見える範囲・指の操作・地図の端）。
- 撮影で撃てなかったスキル（H027 S1・H028 奥義・H034 奥義。英雄にだけ撃てる）を対戦か Bot 相手で。
