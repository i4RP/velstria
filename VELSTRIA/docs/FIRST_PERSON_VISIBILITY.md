# 一人称の自分の体と視界

通常プレイではキャラの目の位置から見回し、自分の胴・腕・装備を50%の不透明度で表示する。2026-10-27に画面下端の横線による切り取りを撤去した。正面でも下向きでも、画面の高さや占有率による表示制限は行わない。

## 表示の仕組み

- `FirstPersonVisibility` は操作キャラのモデルだけに専用マテリアルを用意する。読み込み中に準備し、プレイ中はパラメータだけを更新する。
- `FirstPersonVisibility.metal` は元の材質とアルファを保ち、画面位置に応じたクリップを行わない。カメラの上下角度は視線だけを変える。
- `HeroVisual.modelRoot` の `OpacityComponent` は一人称へ入るフレームから最大0.5。草むら・ステルス・死亡のフェードはさらに薄くできる。
- 自分の頭部、頭上バー、足元リング、武器の軌跡、モデル付属の発光粒子・オーラは一人称で隠す。他キャラや別レイヤーのスキル範囲・攻撃判定は変更しない。
- 一人称から離れると元のマテリアルへ戻す。材質の変換失敗は検証でエラーとして扱う。

## 検証の範囲

環境はiPhone 17シミュレータ、iOS 26.3.1、Debug、横画面。`FirstPersonVisibilityReview` は戦闘と同じモデル・モーション・レンズ・専用シェーダーを使い、1起動につき1体だけを表示する。

ツールはマスター全34体から対象を選べる。待機の1周期、歩行・走行、通常攻撃の各型、強化攻撃、S1・S2・奥義、専用モーションのある再使用・命中後の動作を、1/60秒刻みで進めて3Hzで撮影する。各キャラに下向き80°の画像も残す。

占有率は参考値として記録し、上限による合否判定は行わない。同じシェーダーの白マスクを黒背景に描き、`simctl io screenshot` で取得する。RGB最大値が8/255を超えるピクセルを丸ごと1と数え、半透明だから面積を半分にする計算はしない。`ARView.snapshot` は使用しない。

各サンプルで実際の不透明度コンポーネントが0.5、シェーダーの準備完了、未対応材質なしであることを確認する。空のスキル撮影、キャラの欠落・重複、不正な数値は合格にしない。下向きの白マスクが0.5%以下なら本体未表示として失敗にし、胴・腕の見え方は一覧画像でも確認する。

3Hzの撮影はモーション中の標本であり、全フレームの実撮影ではない。隔離したモデル表示の検証なので、全スキル演出の読みやすさや実バトル全状況の検証結果ではない。横線で切れていないことと胴・腕の形はカラー画像で確認する。

## 再現

リポジトリ直下から、専用シェーダーを含めたDebugシミュレータアプリをビルドして実行する。`--udid` は使うシミュレータを明示する。

```sh
uv run --with pillow --with numpy python VELSTRIA/tools/fps_visibility_review.py \
  --udid <UUID> --app <VELSTRIA.app> --heroes H025 --hz 3 \
  --out VELSTRIA/build/fps-visibility-unclipped
```

既定の対象はマスターの全定義、撮影頻度は3Hz。中断後は `--resume` を付け、現行仕様で完了済みの撮影を再利用する。旧クリップ版の出力は混ぜず、新しい出力先を使う。並列実行ではシミュレータと出力先を分ける。

```sh
uv run --with pillow --with numpy python VELSTRIA/tools/fps_visibility_review.py \
  --summarize-only \
  --inputs VELSTRIA/build/fps-visibility-unclipped-a VELSTRIA/build/fps-visibility-unclipped-b VELSTRIA/build/fps-visibility-unclipped-c \
  --out VELSTRIA/build/fps-visibility-unclipped-final
```

集計だけの実行はシミュレータにアクセスしない。全34体の一致を検証し、`summary.json`、`coverage.csv`、キャラ別の一覧画像、`roster-contact.png` を出す。元のマスク・サンプル目録は各採取フォルダに残し、集計フォルダからシンボリックリンクで参照する。

現行の撮影形式は `schemaVersion: 3`、`renderingMode: unclippedHalfOpacity`。`currentPlayableRoster` と `allHeroRoster` を明示し、全定義は `master_runtime.json` と照合する。旧形式の採取は現行ツールの再開・集計対象にしない。

## 切り取り撤去後の確認（2026-10-27）

同じiPhone 17シミュレータでH025の10シナリオ・93サンプルを採取。不透明度0.5を維持し、通常攻撃・スキル・下向きのカラー画像で横線による切れ目がないことを確認した。正面最大占有率は17.116%で、表示上限としては使用しない。今回の再撮影はH025のみ。出力は `VELSTRIA/build/fps-visibility-unclipped/`。

関連単体テスト4件が通過。実バトルUIの正面・下向き・見回し画像も取得したが、UIテスト全体はスコアボードの閉じるボタン待ちで失敗し、再実行はテストランナーの終了で中断したため、UIテスト成功とは扱わない。

## 旧仕様の検証記録（2026-10-26）

以下は、画面下9%に切り取っていた旧仕様の結果であり、現行表示の結果ではない。全34体・358シナリオ・2,399サンプルで旧基準の10%未満を満たし、最大占有率は8.414%だった。全サンプルで不透明度コンポーネント0.5、全34体の下向き画像で胴・腕を確認した。

当時の関連テスト82件が通過。H025の実バトルUIで正面・下向き・見回しを確認し、移動・攻撃・スキルを繰り返す65秒の自動操作も終了した。`ledger.live = {}`、`liveSamples = []`。これらも旧仕様の記録として保持する。

[旧仕様の結果JSON](validation/fps-visibility-2026-10-26.json) / [旧仕様の全シナリオCSV](validation/fps-visibility-2026-10-26.csv)。詳細画像・マスクの作業出力は `VELSTRIA/build/fps-visibility-final/`、実バトル画像・65秒レポートは `VELSTRIA/build/fps-visibility-gameplay/`。
