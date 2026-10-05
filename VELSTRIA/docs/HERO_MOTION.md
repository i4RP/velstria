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
- `melee`（省略可）: 打撃が武器・拳の近接の振りか（武器の軌跡を出す）。省略時は名前の頭（最初の `_` まで）が
  `cast` / `bow` / `gun` / `javelin` / `dodge` でなく、`impact` があれば近接。

## 抽出（tools/blender/extract_clips.py）
- 入力: Meshy の animations API の GLB（メッシュ・骨・クリップ入り、骨名は Meshy 名 → `norm_common.MESHY_TO_MIXAMO` で読み替え）。
- 仕様: `tools/heroref/clips.json`（出力クリップごとに元の action_id・切り出す範囲・左右反転・Y 軸回りの回転・ループ・rootXZ・events）。
- 左右反転: R と L の区間を入れ替え、各回転を YZ 平面で鏡映（(x, y, z, w) → (x, -y, -z, w)）、root は dx → -dx。
- yaw: 全区間に `ry(yaw)` を左から掛け、root も回す（打撃の向きを正面 -Z へ合わせる）。
- 検証: 抽出したクリップを元リグに実行時と同じ計算で戻し、四肢の骨の向き（次の関節へのベクトル）が元のアニメーションと
  一致すること（1° 以内）を毎回確かめる。

## 実行時
- `HeroMotionClips`（App/Battle/Heroes/HeroMotionClips.swift）が JSON を 1 度だけ読む（戦闘はロード中にテンプレートと並行して
  非同期で読む。プレビュー・テストは同期）。無い・壊れていれば空のライブラリ = 手続きアニメーションだけで動く。
- `HeroMotionSets`（HeroMotionSets.swift）がヒーローごとの割り当て: 通常攻撃（順に繰り返す）、Skill1〜Ultimate の詠唱、
  待機・死亡・勝利。ライブラリに無い名前は黙って落とす。移動は手続き（速度に合わせた歩幅）、帰還の膝立ちも手続き。
- `HeroClipLayer`（HeroAnimation.swift）が手続きの `HeroPose` に重ねるクリップ・時刻・重み・マスクを持ち、
  `SkinnedHeroModel.apply` が区間ごとに手続きとクリップを slerp してから `HeroSkeletonPoser.solve` する。
- 通常攻撃: シムの `attackStarted` で描画側が `setState(.attack)` → `HeroModelHandle.playAttack(windup:interval:)` の順に呼ぶ
  （windup = シムの予備動作の残り = 命中・発射までの秒）。クリップの `impact` が windup 秒後に来るよう、打撃までを 0.5〜4 倍速で
  再生し（範囲外なら開始位置をずらす）、打撃の後は次の攻撃までに戻りが収まる速さ（1 倍以上）。`setState(.attack)` だけなら
  既定の拍（windup 0.3 秒・間隔 0.9 秒）で回す（プレビュー・ギャラリー）。
- 詠唱: 呼び出しの 0.12 秒後に `impact` が来る位置から等速で再生（シムの効果は詠唱の tick に出るため予備動作は短い）。
- マスク: 立ち止まっていれば全身、移動中は上半身だけ（攻撃・詠唱とも。足の滑りを避ける）。全身の間は手続きの全身の傾き・
  浮き沈み・腰の沈みをクリップの重みの分だけ止める。
- ループのクリップは状態（待機など）の時だけループする。攻撃・詠唱・死亡に割り当てたループのクリップは 1 周で終える。
- `impact` が無いクリップは `release`、それも無ければ全長の 40% を打撃とする。
- 手・足の区間で骨を駆動するのは、手首・足首が前腕・脛の子孫で、間の骨がすべてレスト（未駆動）の時だけ。それ以外は従来どおり親に追従。
- 死亡クリップは最後のフレームで止め、倒れきってから（クリップの終わり + 0.15 秒）透明にする。
- 武器: クリップ再生中は手の区間に付ける（位置）。向きは割り当ての grip があれば手の区間 × grip（振る武器。既定の拳の握り =
  +Y を手の区間の正面 -Z へ）、grip が nil なら手続きの武器角をクリップの胴に対して保つ（杖・槍・銃・弓・盾・灯籠）。
  体に付ける籠手・爪は手の区間そのもの。
- 手続きモデル（スキンメッシュが無いヒーロー）は従来の手続きクリップのまま。

## 武器の軌跡・発射位置（HeroModelHandle.weaponTrailSample / attackLaunchPoint）
- 打つ手 `strikeHand`（right / left / both）: 読み込み時にクリップごとに 1 度だけ決める（`HeroMotionLibrary.measureStrikeHand`）。
  振りの区間（下記）の各フレームで、胴に対する foreArmR / foreArmL の回転の角速度（前後フレームの中心差分）を平均し、
  片方が 1.5 倍より速ければその手、どちらでもなければ両手。胴に対して測るのは、体のひねり・回転が左右の腕を同じだけ回し、
  打つ腕の見分けを鈍らせるため（同梱では hook_l・punch_a が左、uppercut_r・elbow・剣の連撃が右、二刀の回転斬りは両手）。
- 振りの区間: 通常攻撃・詠唱のクリップのうち `melee` のものの、`impact` の前 0.18 秒〜後 0.06 秒（クリップ時刻なので
  再生速度に比例して実時間は縮む）。この間だけ `strikeHand` の手の `swing` が真。拍待ちで最後の姿勢に止まっている間は偽。
  クリップが無い時（手続きモデル・割り当ての無い動作）は手続きの通常攻撃（近接の型）の打撃区間（予備動作の終わり〜
  打撃の終わり + 0.06 秒）、左右交互の型は奇数回目が左手。
- 点は武器・副手エンティティのローカル（握りが原点）: 根元 = 原点、先端 = `HeroMeshSet.weaponTip` / `offhandTip`
  （Prop は propFit で同じ座標、weaponScale はエンティティの拡縮）。左手の軌跡は二刀の近接（硝子の短剣・花弁の双刃・夢の針・
  小太刀・三日月の短刀と組む月の灯籠）だけ。返す座標はワールド（`Entity.convert(position:to: nil)`、最後の update 時点）。
- 発射位置: 武器の先端（杖・槍・銃口・掌の炎）。素手で副手に弓を持つ H003 は弓の握り、体に付ける籠手・爪は手のひら。
  左右に同じ武器（爪・拳・二刀）を持ち、再生中のクリップの `strikeHand` が左なら左手の側（H022 の hook_l は左の爪）。
- 描画側の使い方（App/Battle/Render）: ヒーロー別の演出表 `HeroFXProfiles`（色は設計図の glow / accent、Theme.heroHue は
  使わない）。近接は `WeaponTrail`（LowLevelMesh の帯。読み込み中にヒーローの見た目 1 体につき 1〜2 本作り、`swing` の間だけ
  標本を積む。低画質・軌跡を切った自動調整では出さない）、遠隔は `ProjectileLayer` のヒーロー別の弾（`attackLaunchPoint` から
  出し、ずれは残り距離に比例して消す）と `HeroAttackFX` の発射炎（`.attackReleased` の後、姿勢の更新後に発射位置へ）・着弾。

## クリップの作り方（tools/heroref）
1. 動作の購入: `node tools/meshy.mjs anim --rig H002 --actions <id,...>`（1 動作 3 credits、既存の rig を使う。rig は 3 日で失効）。
2. 全長の抽出（解析用）: `build/heroref/raw_spec.json`（全 action を範囲指定なしで並べたもの）→ `build/heroref/raw_clips.json`。
3. 切り出し表 `tools/heroref/clip_defs.json`（元フレーム = 最初のキーが 1、impact、yaw の決め方）→
   `python3 tools/heroref/make_clips.py` が `tools/heroref/clips.json` を作る。yaw: 省略 = 打撃の瞬間の胴を正面へ、
   `hand` / `handL` = 肩 → 手首を正面へ、`travel` = 腰の移動方向を正面へ、数値 = 度。
4. 抽出: `extract_clips.py --spec tools/heroref/clips.json --out App/Resources/Heroes/HeroMotionClips.json`。
5. 目視: `preview_clip.py --clip <名前> --hero H001 --weapon R,L --at "impact-6,impact,impact+4" --view overhead`
   （overhead = 真上、正面が画面の上。棒は握りの向き）。
