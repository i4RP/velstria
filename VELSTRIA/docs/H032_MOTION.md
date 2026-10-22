# H032 ディアスの待機・移動・通常攻撃・スキル（初版）

対象は「赤拳のディアス H032」（`Kit_H032` の Dyrroth 相当）。試合では `Hero_H032.usdz`（2026-10-11 の Tripo 製、
23 骨・指なし）を `SkinnedHeroModel` が再生する。モデル・顔・衣装・体形・籠手の刃の輪（`Prop_abyssRing`）は作り直していない。

## 変更前

- 待機 `HeroIdle`（abyssChallenger の手続き）、歩行・走行 `HeroGait` の手続き。
- 通常攻撃 `dual_combo_a / b / c`（二刀の剣の収録の流用。拳の打撃ではない）、3 回目の強い通常攻撃「円撃」は
  `Motion_H032.empoweredAttack`。
- スキルは `FX_H032.motion` の手続きの詠唱。

## 取得（Meshy、計 130 credits）

`node tools/h032_motion_api.mjs rig|motions|library|apply|status|manifest`（状態 `build/h032-motion/api-state.json`、
記録 [MOTION_H032_API.json](MOTION_H032_API.json)。キー・署名 URL は保存しない）。

- 自動リグ（5）: 既存の Tripo のメッシュ（`vel-h25` の `build/tripo/heroes/H032/rigged.glb`）から骨を外し、正面 +Z の
  静的 GLB にして渡した。Meshy の骨は抽出の元リグとしてだけ使い、ゲームのモデルは差し替えない。
- Text to Motion prime（8 × 10）: 待機・歩行・走行・左右の連打・S1・S2 突進・S2 飛びかかり・奥義。各 1 案。
- Animation API（ライブラリ 7 動作 21 + prime の適用 8 × 3）: 同じリグに載せた GLB を `extract_clips.py` で 15 区間化。

## 採用

| クリップ | 素材 | 仕上げ |
|---|---|---|
| `idle_h032` | prime 待機（左足前・拳を顎の高さで左右ずらす・呼吸） | f20〜110 の 1 周、継ぎ目 10 フレームを混ぜる。胴を -20° 回してジャブの構えへ寄せる |
| `walk_h032` | ライブラリ 21 Walk Fight Forward | 50 フレーム 1 周（構えたまま）。groundSpeed 1.25 m/s |
| `run_h032` | prime 走行（深い前傾・膝を高く・拳を体の近くで振る） | f8〜27 の 1 周。腰の前進から groundSpeed 3.3 m/s |
| `punch_jab_l_h032` / `punch_cross_r_h032` | ライブラリ 191 / 192（構えから） | 全伸展の最初のフレームを impact（12 / 13） |
| `punch_s1_h032` | ライブラリ 192 → 191 → 192 | 右・左・右の全伸展を 0.26 / 0.46 / 0.66 秒に（発動の瞬間から再生） |
| `dash_s2_h032` | prime 飛びかかりの低い踏み出し | 0.4 秒の突進の間、低い前傾を保つ（castLocksLegs: 移動中も下半身を走らせない） |
| `punch_s2_strike_h032` | prime 飛びかかり + ライブラリの左右 | 到着 0.27 秒（振りかぶり 0.06 + 2.5 m / 12 m/s の目安）→ +0.13 左 → +0.2 右 |
| `punch_ult_h032` | ライブラリ 210 Prep Straight Punch | 0.62 秒かけて引き絞り（足は動かさない）→ 0.76 秒に右の全伸展 → 構え |

prime の連打（combo・S1）と奥義は腕が伸び切らず向きもずれたので、打撃はライブラリの拳を使った。prime の突進（s2dash）は
四つ這いになったので使っていない。3 回目の「円撃」は既存の `Motion_H032.empoweredAttack`（判定半径 2.0m の 1 回転）のまま。

合成は `tools/motion/h032_compose.py`（区間ごとの slerp で切り出し・伸縮・つなぎ、腰の水平移動を消して上下だけ残す）。
解析は `tools/motion/h032_analyze.py`（胴の向き・腕の伸び・打撃の向き）。

## ゲームへの組み込み

- `H032MotionClips.json` を試合に出る時だけ読む（`HeroMotionClips.dedicatedHeroes`）。
- `HeroMotionSets` の H032 を `dedicatedIdle`（`HeroIdle` で上書きしない）・walk / run・casts・`stageCasts`（S2 の段 1）に。
- 刃の輪（`Prop_abyssRing`）はクリップ中、前腕に沿う縦の刃として付ける（`gripOnForeArm`・`SkinnedHeroModel.forearmBlade`）。
  拳の握り（fistGrip）のままだと顎の前の構えで輪の面が顔を覆い、手・前腕の区間の向きは素材ごとにねじれるので、
  前腕の向きと胴の正面から毎フレーム組み立てる。
- 詠唱のクリップ: `castsFromStart`（発動の瞬間から再生）・`castLocksLegs`（S2 は突進中も全身）。段 1 の専用クリップ
  （`stageCasts`）は同じスロットの詠唱中でも始め直す。ダメージ・射程・移動・発射時刻・操作可能時間は変えていない（見た目だけ）。

## 確認

- 録画: `tools/capture_h032_motion.sh <app> <出力> <ラベル>`（ギャラリーの idle / walk / run / attack / S1 / S2 / ULT と
  練習試合。iPhone 17 シミュレータ、Debug。実機 FPS の根拠にはしない）。
- `HeroMotionClipTests.testBundledDyrrothClipsGroundAndSkillTiming`（接地・S1/ULT の打撃時刻・S2 段 1 の切り替え）。

## 未対応（次の候補）

- 指の骨が無いので拳の握りは作れていない（手首の角度だけ）。Tripo の rig（25）で指を足すと H025 と同じ経路で握れる。
- S2 致命の一撃の到着時刻は距離で変わるが、クリップは目安の 0.27 秒で打つ。
- 籠手の刃と衣装の干渉は録画の目視のみ。
