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

（工程ごとに追記する）
