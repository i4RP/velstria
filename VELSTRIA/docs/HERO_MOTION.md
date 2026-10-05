# ヒーローのモーションクリップ（区間回転クリップ）

モーションキャプチャ由来の動き（Meshy のアニメーションライブラリ）を、どのヒーローのスキンメッシュにも流用するための形式。
骨そのものの回転ではなく、実行時の手続きアニメーション（`HeroSkeletonRig` / `HeroSkeletonPoser`）が使う
**区間回転**（ヒーロー空間で「真下を向いた四肢」を回す回転）で持つ。A ポーズ・T ポーズのどちらのリグにも、
実行時の既存のレスト補正でそのまま載る。

## 座標と記号
- ヒーロー空間: Y 上・正面 -Z・キャラの右手 +X・メートル（`SkinnedHeroModel` の motion エンティティのローカル）。
- `R0_j`: 骨 j のレスト（= バインド）のヒーロー空間回転。`P0_j`: レストのヒーロー空間位置。
- `R_j(t)`: 時刻 t の骨 j のヒーロー空間回転。`P_j(t)`: 位置。
- `C_j`: 四肢のレスト補正 = `rotationBetween(レストの骨の向き, (0,-1,0))`（最小回転。反平行は Swift の `rotationBetween` と同じ処理）。
  骨の向きは次の関節へのベクトル: 上腕 = 前腕 - 上腕、前腕 = 手 - 前腕、腿 = 脛 - 腿、脛 = 足 - 脛（`HeroSkeletonRig.init` と同じ）。
  手は前腕の C、足は脛の C を使う。腰・胴・頭は C = 単位。

## 区間（15 個、この順）
| # | 名前 | 骨（Mixamo 名） | C |
|---|---|---|---|
| 0 | hips | Hips | 単位 |
| 1 | torso | 最上段の背骨（Spine2 → Spine1 → Spine の順で存在するもの） | 単位 |
| 2 | head | Head | 単位 |
| 3 | armR | RightArm | C_RightArm |
| 4 | foreArmR | RightForeArm | C_RightForeArm |
| 5 | handR | RightHand | C_RightForeArm |
| 6 | armL | LeftArm | C_LeftArm |
| 7 | foreArmL | LeftForeArm | C_LeftForeArm |
| 8 | handL | LeftHand | C_LeftForeArm |
| 9 | thighR | RightUpLeg | C_RightUpLeg |
| 10 | shinR | RightLeg | C_RightLeg |
| 11 | footR | RightFoot | C_RightLeg |
| 12 | thighL | LeftUpLeg | C_LeftUpLeg |
| 13 | shinL | LeftLeg | C_LeftLeg |
| 14 | footL | LeftFoot | C_LeftLeg |

区間回転 `Q_s(t) = R_j(t) · R0_j⁻¹ · C_j⁻¹`。実行時は `R_j = Q_s · C'_j · R0'_j`（' は表示するヒーローのリグ）で骨を置く
（`HeroSkeletonPoser.solve`）。レストでは `Q_s = C_j⁻¹`（T ポーズの元リグなら腕は水平）。
背骨の途中・首は実行時に腰と胴（胴と頭）の間を slerp する。肩・指・つま先などその他の骨は親に追従（レストのローカル）。

手続きの姿勢（`HeroSegmentRotations(HeroPose)`）では handR = foreArmR、footR = shinR（手首・足首を曲げない）。
これは手・足を前腕・脛に追従させていた従来の結果と一致する（`C_hand = C_foreArm` の定義による）。

## 腰の位置
`root(t) = (P_Hips(t) - P0_Hips) / L`。L = 元リグの脚の長さ（レストの Hips の高さ - 左右の Foot の高さの平均）。
実行時は表示するリグの脚の長さを掛けて腰（Hips）を動かす。水平成分はクリップの `rootXZ`（0〜1）倍し、
ヒーローの位置そのもの（シミュレーションが決める）は動かさない。

## ファイル `App/Resources/Heroes/HeroMotionClips.json`
```json
{
  "version": 1,
  "fps": 30,
  "segments": ["hips", "torso", "head", "armR", "foreArmR", "handR", "armL", "foreArmL", "handL",
               "thighR", "shinR", "footR", "thighL", "shinL", "footL"],
  "clips": [
    {
      "name": "sword_slash_a",
      "source": "meshy:97",
      "frames": 24,
      "loop": false,
      "rootXZ": 0.3,
      "events": { "impact": 9.0 },
      "rot": [x, y, z, w, ...],
      "root": [dx, dy, dz, ...]
    }
  ]
}
```
- `rot` はフレーム × 区間 × (x, y, z, w) の平坦な配列（小数 4 桁、w ≥ 0 に揃えない＝前フレームとの内積が正になる符号に揃える）。
- `root` はフレーム × 3。
- `events` はクリップ先頭からのフレーム（小数可）。`impact` = 打撃・発射の瞬間（通常攻撃ではシムの命中・発射にこの瞬間を合わせる）。
  `release`（弓を離す等）、`end`（戻りの終わり。省略時は最終フレーム）を使ってもよい。
- `loop: true` のクリップは最終フレームの次が先頭（先頭と末尾は滑らかにつながるよう切り出す）。

## 抽出（tools/blender/extract_clips.py）
- 入力: Meshy の animations API の GLB（メッシュ・骨・クリップ入り、骨名は Meshy 名 → `norm_common.MESHY_TO_MIXAMO` で読み替え）。
- 仕様: `tools/heroref/clips.json`（出力クリップごとに元の action_id・切り出す範囲・左右反転・Y 軸回りの回転・ループ・rootXZ・events）。
- 左右反転: R と L の区間を入れ替え、各回転を YZ 平面で鏡映（(x, y, z, w) → (x, -y, -z, w)）、root は dx → -dx。
- yaw: 全区間に `ry(yaw)` を左から掛け、root も回す（打撃の向きを正面 -Z へ合わせる）。
- 検証: 抽出したクリップを元リグに実行時と同じ計算で戻し、四肢の骨の向き（次の関節へのベクトル）が元のアニメーションと
  一致すること（1° 以内）を毎回確かめる。

## 実行時
- `HeroMotionClips`（App/Battle/Heroes/HeroMotionClips.swift）が JSON を 1 度だけ読み、区間回転を補間（slerp）して返す。
- `HeroAnimator` は手続きの `HeroPose` に加えて「重ねるクリップ・時刻・重み・マスク（全身 / 上半身）」を持ち、
  `SkinnedHeroModel.apply` が区間ごとに手続きとクリップを slerp してから `HeroSkeletonPoser.solve` する。
- クリップ再生中、武器は手の区間（handR / handL）に追従する（手続きの武器角とは重みで混ぜる）。
- 手続きモデル（スキンメッシュが無いヒーロー）は従来の手続きクリップのまま。
