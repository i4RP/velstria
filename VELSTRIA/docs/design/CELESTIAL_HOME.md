# Celestial Saber ホーム

2026-10-19 のユーザー採用案（3 枚目）に基づく。

## 素材

- `App/Resources/Assets.xcassets/CelestialAtlas.imageset/CelestialAtlas.png`: 採用原画。イベントカードの上部・ナビゲーションのアイコン・開始ボタン・外枠の角を、SwiftUI のクリップと輝度マスクで参照する。原画の架空プロフィール・フレンド・通貨は表示しない。
- `App/Resources/Assets.xcassets/CelestialLobby.imageset/CelestialLobby.png`: 組み込み image_gen による UI 除去済みキービジュアル。背景と人物は一枚の季節ビジュアルで、現在選択中のヒーローの立ち絵ではない。中央からヒーロー一覧へ移動できる。
- 原画のキャンバスは 1774 × 887。実装は 1024 × 512 に正規化し、セーフエリア内に縦横比を保って収める。

## 動作

通貨・プロフィール・ランク・フレンドは実データ。フレンドがいない場合は空状態を表示する。全ボタンは既存の画面に接続。外枠のセイバー光と固定 18 個の粒子は局所的な 30 Hz TimelineView、ボタンは SwiftUI の位相アニメーション。別画面・戦闘中・非アクティブ時・視差効果を減らす設定時には停止する。実機 FPS の改善は未計測。

## 画像生成プロンプト

組み込み image_gen、採用原画を編集対象として以下を指定した。

> Edit this exact image to extract the full-screen background illustration for a working game UI. Keep EXACT same aspect ratio, hero identity, hero pose, hero scale and position, sword, blue silver palette, castle, magic circle and all visible background pixels as closely as possible. Remove ALL UI: outer luminous border, title text, logo, profile and currency at top, event cards and buttons on left, friends panel on right, whole bottom navigation and battle button. Inpaint just those removed UI areas with continuous background castle/nebula illustration. Keep the main silver-haired knight centered in the same center-left place and his glowing sword crossing toward lower right. No text, no icons, no frames, no HUD anywhere. This is a precise background extraction, NOT a redesign. Full bleed 2:1 landscape artwork.

## 比較確認

iPhone 17 Pro / iOS 26.3 シミュレータ、Debug、ARM64 で起動。スクリーンショットのセーフエリア内キャンバスを原画サイズに正規化し、50% 重ね合わせと絶対差分画像を出力。ローカル成果物は `build/celestial-review/`。

重ね合わせで発見したノッチへの重なり、アイコンの矩形背景、開始ボタンの形、下部バーの透けすぎを修正。

対戦開始 → モード選択 → ホーム復帰、およびメニュードロワーの開閉もシミュレータ上で確認した。

ピクセル完全一致ではない。主な残差は UI 除去で再生成した背景、ネイティブ文字と一部システムアイコン、実データによるランクとフレンドの差、アニメーション位相、セーフエリア対応。比較画像はこれらを隠さず表示する。
