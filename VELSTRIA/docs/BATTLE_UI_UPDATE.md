# 戦闘UI・ミニマップ更新

Pokémon UNITEの[公式バトル紹介](https://unite.pokemon.com/en-us/overview/)を参考に、戦場を見ながら素早く状況を読める情報配置へ更新した。VELSTRIAの3レーン地形、チーム色、戦闘ルールを利用する。

## 表示と操作

- ミニマップは実際の`SimContext.map`から河川・通路・壁・草むら・泉を描く。通常表示を拡大し、地形、マーカー、タッチ位置に共通の余白付き投影を使用する。
- 白いカメラ枠はレンダラーのカメラ姿勢と画面比率から求めた地面の四角形。ズーム、追従の平滑化、端の制限、振動を反映し、地図の境界と交差する辺をクリップする。観戦一時停止中も更新する。
- ヒーローは頭文字、チーム色、円/ひし形で識別。自分と追従対象には白いリングと方向矢印を付ける。視界外の敵は最後の目撃位置に点線の残像を最大3秒表示する。
- 塔/コアのHPリング、破壊済み拠点、視界の霧、中立モンスターの種別を表示。通常キャンプの視界外での撃破は更新せず、観測できた再出現予定のみタイマーにする。ボスの予定は共有する。
- 「全体マップ」ボタンで拡大。ドラッグでカメラを移動し、通常プレイでは指を離すと自分へ戻る。観戦ではその地点に留まる。マップを開くと移動・攻撃・照準を解除し、閉じると操作を再開できる。試合は進行し続ける。
- 左利き配置ではマップと上部操作も反転し、攻撃群との重なりを防ぐ。マップの拡大ボタンは44ptのタッチ領域を持ち、移動入力領域から除外する。
- 時計、チーム撃破数と破壊タワー数、K/D/A、HP/リソース、装備、スキルの残り時間と必殺技の準備状態を整理。濃紺の面と明るいリングで戦場から分離し、日本語/英語とVoiceOverを維持する。

## 観戦の操作

- 下部の観戦ドック: 一時停止、速度（0.5/1/2/4/8 倍）、視界（全体 / Blue / Red）、自動カメラ、HUD を隠す、前後のヒーロー、10 人の追従ボタン（44pt 以上）。iPhone SE など狭い画面では引き出しに収める。
- 再生バー: ドラッグでシーク、±10/30 秒、最初から、一時停止中のコマ送り、次の見どころ。キル・構造物・目標の印と、計算済みの範囲を表示する。オンラインの観戦席は LIVE と遅延秒数だけを出す。
- 画面の操作: ドラッグで自由カメラ、ピンチで倍率（0.7〜2.5）、ダブルタップで追従に戻る。手動で動かすと自動カメラは 10 秒控える。
- 情報パネル: 追従中のヒーローの詳細、ゴールド/経験値の差のグラフ、目標のタイマー、イベント一覧（タップでその時刻へ）。スコアボードの行をタップすると追従する。
- 死亡中（プレイヤー）: 死亡カードに味方の一覧が出て、タップでその味方を見られる（敵は不可）。「自動」で戦っている味方を追う。

## 確認

`HUDMinimapPrecisionTests`に投影の往復、境界交点、カメラの逆投影、停止中のカメラ更新、敵の最終目撃、描画補間、キャンプの視界制御の回帰テストを追加した。`HUDTacticalMapTests`は4画面サイズ・左右配置・安全領域・操作解除と復帰、`HUDTacticalMapUITests`は拡大・ドラッグ・閉じる操作とスクリーンショットを対象にする。

Windows上でSwift構文解析、投影計算の数値確認、差分検査を実施。SwiftUI/RealityKitの型検査、XCTest、実画面の描画確認はmacOS/Xcodeで実行が必要。

```sh
cd VELSTRIA
xcodegen generate
xcodebuild -project VELSTRIA.xcodeproj -scheme VELSTRIA \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VELSTRIATests/HUDMinimapPrecisionTests \
  -only-testing:VELSTRIATests/HUDTacticalMapTests \
  -only-testing:VELSTRIATests/HUDLayoutTests \
  -only-testing:VELSTRIATests/HUDAimTests \
  -only-testing:VELSTRIATests/RenderLogicTests \
  -only-testing:VELSTRIAUITests/HUDTacticalMapUITests \
  -only-testing:VELSTRIAUITests/BattleHUDUITests \
  test CODE_SIGNING_ALLOWED=NO
```

シミュレータ名はインストール済みの機種に合わせる。画面確認では明暗の異なる戦場、左利き、色覚対応、観戦一時停止、マップ端、通常/拡大表示を確認する。
