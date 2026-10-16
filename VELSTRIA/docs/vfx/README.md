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
- カメラ: `CameraRig.Preset`（legacy / mlbb）。既定はまだ legacy。mlbb の値の導き方は [CAMERA.md](CAMERA.md)。
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

### 2026-10-17 工程 3（ボルグ）

[H029.md](H029.md)。S1・S2・再使用・奥義を画面収録に寄せた（予算内）。撮影 `fxcap-h029v1--H029@mlbb`。
