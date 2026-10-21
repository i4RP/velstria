# ヒーローのモーションクリップ（区間回転クリップ）

モーションキャプチャ由来の動き（Meshy のアニメーションライブラリ）を、どのヒーローのスキンメッシュにも流用するための形式。
骨そのものの回転ではなく、実行時の手続きアニメーション（`HeroSkeletonRig` / `HeroSkeletonPoser`）が使う
**区間回転**（ヒーロー空間で「真下を向いた四肢」を回す回転）で持つ。A ポーズ・T ポーズのどちらのリグにも、
実行時の既存のレスト補正でそのまま載る。

## 現行10体の固有歩行（2026-10-21）

`HeroGait.swift` で H025〜H034 の歩容を個別に定義する。ルミナは静かな大股、エウリアは小刻み、
ジャルドは槍を安定させる行進、ザイルは低い足運び、ボルグは長い接地、ライナは弾む小股、
オーリアはローブを乱さない歩行、ディアスは高い膝の回収、ヴァルドは重い大股、ゴルムは横への重心移動。
性格表現は今回の演出設計であり、新しい公式身長・設定値を追加したものではない。

接地率・歩幅・足の回収弧・腰の沈み・肩の遅れを別々に設定。支持脚の前後移動と移動速度から周期を求め、
モデルの脚長を反映する。膝は2骨の逆運動学で求め、スキンメッシュでは実リグの腿／脛比と足首の返しも使う。
従来の手続きメッシュは靴と脛が一体なので、足首だけの回転はスキンメッシュに限る。
地形への足裏固定や旋回時の足の再配置までは行わない。攻撃・詠唱・停止への既存ブレンドを維持する。
タイマー・Entity・メッシュ・外部クリップの追加はなく、既存の画面外更新抑制と予算上限を維持する。

確認: Windows / Node.js の参照計算で10設定の周期境界、支持脚速度、各速度65秒相当の有限値を確認。
`HeroModelTests` に同等のSwift回帰テストを追加。WindowsではXcode/iOSテスト・描画・実機FPSは未検証。
SSS級の品質達成を示す検証ではない。目視は既存ギャラリーの
`-heroGallery -galleryState run -galleryDetail H025 -galleryYaw 90`（IDを各ヒーローへ変更）で
側面・正面、歩き始め／停止、移動攻撃を確認する。

## 現行10体の固有待機（2026-10-21）

`HeroIdle.swift` に停止時の立ち姿・呼吸・視線・肩の追従・時折見せる仕草を定義する。
共通の `ready_idle` / `combat_idle` 等はこの10体の待機を上書きしない。プレビュー・バトルとも同じ経路を使う。

| ヒーロー | 立ち姿と仕草 |
| --- | --- |
| H025 ルミナ | 脚をほぼ平行にして背筋を伸ばす。弓を安定させ、静かに視線を送る |
| H026 エウリア | 球電を見せる非対称の構え。視線に遅れて右手を持ち上げる |
| H027 ジャルド | 胸を張った前後の構え。槍を支えたまま周囲を見渡す |
| H028 ザイル | 低い半身の構え。視線を先行させ、肩と空いた手が追従する |
| H029 ボルグ | 巨体を支える足幅。重い呼吸と、ゆっくり顔を上げる仕草 |
| H030 ライナ | 大砲を支える非対称の構え。砲へ視線を落とし、首を傾ける |
| H031 オーリア | 狭い足幅と高い顎。穏やかに手を上げる |
| H032 ディアス | 前足と左右の腕の高さをずらす。顎を上げ、腕を引き締める |
| H033 ヴァルド | 剣側の肩を前へ出す。周囲へ視線を送り、空いた手を動かす |
| H034 ゴルム | 幅のある構えと大きな呼吸。左手を腹の近くへ持ち上げる |

脚・骨盤の姿勢は待機中固定し、上半身だけを動かす。呼吸は3.1〜6.4秒、仕草は9.2〜16秒の個別周期。
仕草の始終は速度・加速度とも0へ戻す。停止専用の時計は移動・攻撃でリセットし、復帰時は静かな立ち姿から始める。
攻撃や詠唱の `profile.rest` と、足接地の基準は維持する。待機は `plant = 0` とし、戦闘用の足目標へ戻されるのを防ぐ。
Entity・クリップ・タイマー・装飾の追加なし。`HeroIdleTests` に全10体の65秒評価、ルミナの足幅、共通クリップ上書き防止、
歩行／攻撃からの復帰、周期境界の回帰テストを追加。WindowsではXcode/iOSテスト・実機の見た目は未確認。
目視は `-heroGallery -galleryDetail H025 -galleryState idle` で約20秒待ち、各ID・側面でも確認する。

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
- `HeroMotionSets`（HeroMotionSets.swift）がヒーローごとの割り当て: 通常攻撃（順に繰り返す）・待機・死亡・勝利。
  ライブラリに無い名前は黙って落とす。移動は手続き（速度に合わせた歩幅）、帰還の膝立ちも手続き。
  スキルの詠唱はスキル演出の手続きモーション（SkillMotion の MotionClip、docs/SKILL_FX.md。全身のモーションのヒーローは
  下の「全身のモーション」）に任せる。演出の打撃の時刻は
  そのモーションのキーに合わせてあり、クリップを重ねるとずれるため（HeroMotionSet.casts の仕組みは残してあるが使わない）。
- `HeroClipLayer`（HeroAnimation.swift）が手続きの `HeroPose` に重ねるクリップ・時刻・重み・マスクを持ち、
  `SkinnedHeroModel.apply` が区間ごとに手続きとクリップを slerp してから `HeroSkeletonPoser.solve` する。
- 通常攻撃: シムの `attackStarted` で描画側が `setState(.attack)` → `HeroModelHandle.playAttack(windup:interval:)` の順に呼ぶ
  （windup = シムの予備動作の残り = 命中・発射までの秒）。クリップの `impact` が windup 秒後に来るよう、打撃までを 0.5〜4 倍速で
  再生し（範囲外なら開始位置をずらす）、打撃の後は次の攻撃までに戻りが収まる速さ（1 倍以上）。`setState(.attack)` だけなら
  既定の拍（windup 0.3 秒・間隔 0.9 秒）で回す（プレビュー・ギャラリー）。
- 詠唱（割り当てた場合のみ。今は使っていない）: 呼び出しの 0.12 秒後に `impact` が来る位置から等速で再生。
- マスク: 立ち止まっていれば全身、移動中は上半身だけ（攻撃・詠唱とも。足の滑りを避ける）。全身の間は手続きの全身の傾き・
  浮き沈み・腰の沈みをクリップの重みの分だけ止める。
- ループのクリップは状態（待機など）の時だけループする。攻撃・詠唱・死亡に割り当てたループのクリップは 1 周で終える。
- `impact` が無いクリップは `release`、それも無ければ全長の 40% を打撃とする。
- 手・足の区間で骨を駆動するのは、手首・足首が前腕・脛の子孫で、間の骨がすべてレスト（未駆動）の時だけ。それ以外は従来どおり親に追従。
- 死亡クリップは最後のフレームで止め、倒れきってから（クリップの終わり + 0.15 秒）透明にする。
- 武器: クリップ再生中は手の区間に付ける（位置）。向きは割り当ての grip があれば手の区間 × grip（振る武器。既定の拳の握り =
  +Y を手の区間の正面 -Z へ）、grip が nil なら手続きの武器角をクリップの胴に対して保つ（杖・槍・銃・弓・盾・灯籠）。
  体に付ける籠手・爪は手の区間そのもの。
  - 状態のクリップ（待機・勝利など、腕を下ろした立ち姿）の間は、割り当ての `idleWeaponR` / `idleWeaponL`（胴座標の武器角）へ
    0.1 秒ほどで寄せる（攻撃・詠唱のクリップへ移ると手続きの角へ戻る）。槍（H005・H008・H023）は -0.22 で立て、
    弓（H003・H020）は -0.38 で上の弓先を前へ傾け、H015 の鐘口の大筒は -2.2 で銃口を前の下へ下ろす（腰だめの構えのままだと
    穂先が顔の前を横切る・下の弓先が足元に立つ・鐘口が顔に重なる）。
  - 灯籠（`SkinnedHeroModel.hangingGear`）は武器角に関係なく胴の向きのまま真下へ吊るす。
  - スキンメッシュだけの装備の拡縮 `SkinnedHeroModel.gearScale`（弩 0.78・月弓/光の弓 0.84。entity の拡縮なので先端・発射位置も縮む）。
  - 確認: `-heroGallery -galleryHeroes H003,H020,H006 -galleryState idle -galleryFreeze 1.5 -galleryYaw 270`（左の側面）。
    検査は AppTests/HeroGripTests（同梱ヒーロー全員の握りの距離・槍・弓・灯籠の向き）。
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

## 全身のモーション（HeroSkillMotions・ヒーローごとの opt-in）

スキルの詠唱・再使用の段・命中の後・通常攻撃を、上半身だけでなく踏み込み・腰のひねり・跳びまで全身で書く仕組み。
目録 `HeroSkillMotions.scripts`（App/Battle/Heroes/HeroSkillMotions.swift）にあるヒーローだけが使い（2026-10-18: H029 ボルグ・
H034 ゴルム、2026-10-21: H025 ルミナ。定義は App/Battle/Heroes/Motions/Motion_H0xx.swift）、それ以外のヒーローの動きは変わらない（演出の定義
H034 ゴルム、2026-10-21: H030 ライナ（スキルだけ。通常攻撃はモーションクリップのまま）。定義は App/Battle/Heroes/Motions/Motion_H0xx.swift）、それ以外のヒーローの動きは変わらない（演出の定義
`FX_H0xx.motion` の詠唱とモーションクリップの通常攻撃のまま。AppTests/HeroFullBodyMotionTests が確かめる）。

- **打撃の時刻 = sim の判定の時刻**: キーの時刻は `KitTimes`（HeroSkillMotions.swift）が `HeroKits.fxValues`（キットの Tune を名前・
  単位つきで返す読み取り専用の口。照準・判定・演出の FXSkillInfo と同じ。docs/vfx/RANGES.md）から読んで作る。値を写さないので、
  sim の時刻を変えるとモーションの打撃も一緒に動く。無い key は `KitTimes.misses` に残る（テストが空を確かめる）。
  ヒーローごとの時刻の表は docs/vfx/H0xx.md「モーション（打撃の時刻）」。
- **描画だけの体の位置**: `HeroPose.offset`（踏み込み・跳び。motion エンティティの位置）は sim の位置を動かさない。
  キーで書いたずれはクリップの終わり（`total`）で 0 に戻る（最後のキー → 待機の姿勢へ `recover` 秒で戻す）。水平のずれは 0.6 m 未満。
- **強い通常攻撃だけのモーション**（2026-10-21: H027 子龍の三連突き・H032 ディアスの円撃。`HeroMotionScript.empoweredAttack`）:
  sim の `attackStarted` で次の通常攻撃が強い（`HeroKits.empoweredAttackReady`）とき、描画が `playAttack(windup:interval:empowered: true)`
  を呼び、普段の通常攻撃（モーションクリップ）の代わりに全身のモーションを 1 回振る。打撃（impact）= windup 秒後 = 1 発目の命中。
  打撃の後は等速（三連突きの 2・3 発目のキーが sim の命中の時刻 = `flurryInterval` おきに来る。攻撃速度で縮めない）。普段の通常攻撃が
  来たら打ち切る。円撃は体の向き（yaw）を 1 回転させ、戻りで巻き戻さない（`MotionClip.wrapsYaw`）。普段の通常攻撃・詠唱は変わらない。
  次の通常攻撃が強い間は武器の先の光（`HeroModelHandle.setEmpoweredReady` → 詠唱の光の下限 0.7）を灯す。
- **足の接地**（`HeroLegIK.swift` の `HeroLegRig`）: `HeroPose.plant`（0〜1）が立つ間、足首を `footR` / `footL`
  （待機の足首からのずれ、ヒーロー空間・m、-z = 前）へ置く腿・脛の角度を 2 関節の IK で解き、作者の脚の角度と plant の重みで混ぜる。
  足首が地面（待機の足首の高さ）より下なら体ごと持ち上げる。寸法は読み込み時に 1 度だけ（手続きモデル = BodyMetrics、
  スキンメッシュ = 骨の待機の位置。腰の沈み hipsDrop は手続きの脚に対する値をスキンの脚へ伸ばす = `hipsDropScale`）。
  キーの間で目標が動く足は弧を描いて踏み出す（上げる高さ = 動く距離の 0.45 倍・最大 0.16 m × sin(πu)。`MotionClip.liftSteps`）。
  クリップの入り・戻りも接地したまま（重みを混ぜると上げた足が地面に残って滑る）。
- **移動中は下半身を移動の姿勢へ**（`MotionClip.yieldsLowerWhenMoving`）: 立ち止まっていれば全身、移動中（sim が動かす突進を含む）は
  下半身・体の位置・接地を 0.12 秒で移動の姿勢へ寄せる（`HeroAnimator.actionLower`）。上半身の振りは移動中も出す。
- **角度を体の鉛直に対して書く**（`MotionBuilder.worldAngles`）: 腕の pitch・武器角・頭の pitch を、胴ではなく体の鉛直に対して書き、
  胴の前傾（torsoPitch）の分を足し引きして胴の座標で積む（胴を大きく倒しても武器が胴と一緒に後ろへ回らない）。
  腕の pitch 0 = 真下・π/2 = 前・π = 真上、武器角 0 = 真上・-π/2 = 前・±π = 真下・+ = 後ろ。
- **盾**: 盾持ちの左腕は既定で胸の前に固定（`MotionBuilder.shieldGuard`）。外すと盾を掲げる・叩きつける技も書ける。
- **再使用の段**（`HeroMotionScript.cast(slot, stage:)`、stage >= 1）: 描画側は `SkillCastEvent.stage` を
  `HeroVisual.noteCast(_:stage:time:)` へ渡し、段に固有のモーションがあれば同じスロットの詠唱中でも始め直す
  （`HeroModelHandle.castRestarts / playCast`）。無い段は従来どおり（詠唱中なら続ける）。
- **命中の後のモーション**（`HeroMotionScript.onHit`）: 詠唱中のスロットのスキルのダメージ（`DamageEvent.source = .skill`）が
  最初に来た時に、今の姿勢からつないで始める（1 回の詠唱で 1 度。`HeroModelHandle.playCastHit`。詠唱状態をその長さだけ延ばす）。
  距離で時刻の変わる判定（鎖鉤の命中 → 0.45 秒後の引き寄せ）に打撃のキーを合わせるため。
- **全身の通常攻撃**（`HeroMotionScript.attacks`、`HeroMotionProfile.attackMotions`）: `impact`（`MotionBuilder.markImpact`）を
  `playAttack(windup:interval:)` の windup 秒後へ合わせる（打撃まで 0.5〜4 倍速、打撃の後は戻りが interval - windup に収まる速さ。
  モーションクリップの通常攻撃と同じ規則）。攻撃状態が終わっても戻りの終わりまで再生し、それから待機のクリップへ。
  武器の軌跡の振りは打撃の前 0.18 秒〜後 0.06 秒（クリップ時刻）。この間、割り当て表（HeroMotionSets）の通常攻撃のクリップは使わない。
- **長さの上限**: 通常スキル 1.1 秒・奥義 1.7 秒（SkillFXTests）。sim が術者を止めておく奥義（`MotionClip.simLock`。ゴルムの拘束
  2.05 秒）は拘束 + 0.6 秒まで。命中の後のモーションも 1.1 秒以内。
- **性能**: クリップはロード時に 1 度だけ作る（値型・配列はプロファイルが持つ）。毎フレームは姿勢の補間と、plant > 0 の間だけ
  脚 2 本の IK（三角関数数回）。ユニットごとのタイマー・全キャラの走査は足していない（状態は HeroAnimator の中）。

確認: 手元（Windows）は MotionLab（%TEMP%/vfxwork/motion/harness。モーションの純粋な部分だけを Swift でビルドして、接地・足の滑り・
体の位置の戻りを測り、棒人形を描く）、実機に近い画は演出の撮影の `fxcap-motion-*` タグ（体の横が見える向き・細かい時刻・
通常攻撃。tools/fx_capture/run_ci.sh の MOTION）。目録の notes にスキンの脚の寸法（`legRig`）が出る。

## クリップの作り方（tools/heroref）
1. 動作の購入: `node tools/meshy.mjs anim --rig H002 --actions <id,...>`（1 動作 3 credits、既存の rig を使う。rig は 3 日で失効）。
2. 全長の抽出（解析用）: `build/heroref/raw_spec.json`（全 action を範囲指定なしで並べたもの）→ `build/heroref/raw_clips.json`。
3. 切り出し表 `tools/heroref/clip_defs.json`（元フレーム = 最初のキーが 1、impact、yaw の決め方）→
   `python3 tools/heroref/make_clips.py` が `tools/heroref/clips.json` を作る。yaw: 省略 = 打撃の瞬間の胴を正面へ、
   `hand` / `handL` = 肩 → 手首を正面へ、`travel` = 腰の移動方向を正面へ、数値 = 度。
4. 抽出: `extract_clips.py --spec tools/heroref/clips.json --out App/Resources/Heroes/HeroMotionClips.json`。
5. 目視: `preview_clip.py --clip <名前> --hero H001 --weapon R,L --at "impact-6,impact,impact+4" --view overhead`
   （overhead = 真上、正面が画面の上。棒は握りの向き）。
