# H028 ザイルの待機・移動・通常攻撃・スキル（初版）

対象は「断空のザイル H028」（`Kit_H028` の Saber 相当）。`HeroAssetLibrary` が `Hero_H028.usdz` を読み、
`SkinnedHeroModel` が再生する（手続きモデルへのフォールバックではない）。

## モデル

完成済みのモデル（vel-h25 の `build/tripo/heroes/H028/model.glb`、10/11 の Tripo 生成）の形状・テクスチャをそのまま Tripo へ渡し、
骨だけを補修した（`/v3/animations/rig-check` → `/v3/animations/rig`、v3.0-20260909・mixamo）。
元のリグは 23 骨で指が無く、剣の握りと空いた手の指先を動かせなかった。補修後は 65 骨（指 30・つま先・肩）。
顔・機甲・体形・テクスチャ 3 枚・9,723 面は同じで、モデルは再生成していない。剣は従来の `Prop_photonBlade.usdz`（赤い刃縁の黒い長剣）。
取り込みは `node tools/tripo.mjs import heroes H028`。検査の不合格は「HeadTop_End ≈ 身長 1.7（±0.1）」の 1 件だけで、
高い結い髪が身長に入るため頭頂の骨が 1.59 m になる（旧リグは HeadTop_End が無く検査を飛ばしていた）。不合格の出力をそのまま採用した。
旧モデルは `build/h028-motion/Hero_H028_original.usdz`（git 管理外）に保管。

## 武器（光刃の長剣、10/23 作り直し）

旧 `Prop_photonBlade.usdz` は 2,400 面で低ポリゴンだったので、生成用の 2D 画像から作り直した。
`tools/tripo/assets.json` のプロンプトを詳細化（面取りした黒い刃・全長の赤い刃縁・刻線のある銀の峰・中央の赤い溝・
重ねた翼形の鍔と多面の赤い宝石・革巻きの柄と銀の帯・多面の柄頭）し、Tripo text-to-image（5）→ image-to-model（60、
`--faces 5400`）→ `import props photonBlade --max-faces 5400`（既定 3,000 では間引かれる）。5,399 面・テクスチャ 3 枚。
スキンモデルの総三角形は本体 9,723 + 剣 5,399 + 浮遊の小剣など ≈ 15,900（剣は予算テストの対象外: `HeroModelTests` の 14,000 は手続きモデル、`SkinnedHeroModelTests` は本体のテンプレートだけ。H034 の鎖鉤 7,728 面より少ない）。比較画像は `build/h028-preview/sword_old_vs_new_lit.png`（git 管理外）。

## 素材（API）

記録は [MOTION_H028_API.json](MOTION_H028_API.json)（task_id・条件・消費。キー・署名 URL は含めない）。
取得は `node tools/h028_motion_api.mjs inventory|rigcheck|rig|motions|manifest`（状態は `build/h028-motion/api-state.json`）。

- Meshy Animation Library（678 件）を照会。剣の候補（Right-hand Sword Slash 219・Triple Combo 105・Weapon Combo 2 241・
  Charged Slash 242・Walk Fight Forward 21/689・Combat Idle 89 など）は既存の `HeroMotionClips.json` に抽出済み
  （現行の `sword_slash_r` / `sword_combo_2` / `sword_combo2_b` / `ready_idle`）。低い片手剣の構え・剣を持った低い歩行/走行・
  ダッシュ斬りは無いので、ライブラリの購入（Meshy の rig が要る）はせず Text to Motion を使った。
- Meshy Text to Motion（prime、1 本 10）: 待機・歩行・走行・3 連の通常攻撃・S1・S2・ULT の 7 本。
  待機（深くしゃがみ両手が膝）と歩行（途中で振り返る）は質が足りず、2 案目を 1 本ずつ（計 9 本・90 credits）。
- Tripo: rig-check（無料）・rig（25）。プリセットの idle/walk/run は Meshy の専用の動作で足りたので使っていない。

## 仕上げ（`tools/blender/author_h028_motion.py`）

`extract_h028_prime.py` が SMPL-H の FBX を区間回転へ変換（往復誤差 0.01° 未満。腰の固定の持ち上げは足の最下点で除く）し、
H028 の実際の寸法（脚の長さ 0.847 m）で仕上げる。切り出しの時刻は `h028_specs.py`。

| クリップ | 元 | 仕上げ |
|---|---|---|
| `idle_h028` | idle2 0〜120 | 3.2 秒ループ（末尾 24 フレームを先頭へ重ねて継ぎ目 0）。頭・胴・剣の手を平滑化（周期的な跳ね・震えを除く）、頭は胴より 0.2 秒先行、左肩・左腕は 0.27 秒遅れて追従。腰を 3.5 cm 上げて低い半身の構えに。両足は固定。剣は下段（前へ・切っ先を下げる）。左手の指はゆっくり開閉 |
| `walk_h028` | walk2 の 1 周（37 フレーム） | 前進を除いてその場に、進む向きを正面へ。胴・頭のねじれを抑え、腰を 7 cm 下げる。支持脚は groundSpeed（1.49 m/s）で等速に後退（足滑りなし）、足は交差させない。剣は後ろ下へ |
| `run_h028` | run の 1 周（18 フレーム） | 元は 7.9 m/s の全力疾走なので、歩調はそのまま歩幅を縮めて 3.0 m/s に。前傾を深く、足の持ち上げを 6 割（地面近くで回収）、剣は後方へ流す |
| `sword_slash_a/b/c_h028` | attack の 3 斬（f12・f35.5・f97.5） | 0.8 秒、打撃 0.3 秒（9 フレーム）。打撃の瞬間の胴を正面へ。両端は待機の先頭の姿勢（構え）へつなぐ。踏み込みの腰の移動は 55% |
| `sword_whirl_h028`（S1） | skill1 | 0〜0.2 秒で剣を体の周りに一回し（元の 1 回転を圧縮）→ 0.2 秒に両腕を開いて放つ → 構え |
| `dash_charge_h028`（S2） | skill2 | 0〜0.2 秒 深い前傾で剣を後ろへ引いて駆ける → 到着で剣を引いた構え（強化通常攻撃の前）→ 構え |
| `sword_triple_h028`（ULT） | ult | 突進（0.33 秒まで）→ 到着で斬り上げ → +0.39 返し → +0.78 大きく振り下ろす → +1.0 まで残心 → 構え。打撃ごとに胴を対象へ向け、元の 4 撃目は前後の姿勢の補間で消した |

共通: 足首は元の接地区間で地面に固定（二関節 IK、遊脚は補正量を滑らかにつなぐ）、つま先が潜る時は足首を上げる。
剣（右手の区間の -Z）は手首の可動域（前腕に対し 25〜125°）に収め、胴・頭・脚（太さ込み）を貫く向きは前腕のまわりに回して避ける。
右手は柄を握る指、左手は動作ごと（構え・走りは軽く握る、S1 の放つ瞬間は開く）。肩・つま先は元の局所回転。

## ゲームでの再生

- `HeroMotionClips.dedicatedHeroes` に H028 を足し、専用ファイル `H028MotionClips.json`（548 KB）を H028 が試合に出る時だけ読む。
- `HeroMotionSets` の H028 = 上の 9 本。`dedicatedIdle` の時は `HeroIdle`（riftWatch）の手続きの待機で消さない
  歩行・走行は速さで選ぶ（境 2.24 m/s ± 0.15）。待機・移動の切り替えは 0.18 秒のクロスフェード（`stateBlend`）。
- 通常攻撃: 打撃 = sim の命中（予備動作 = 間隔の 25%）。H025・H031 と同じく `attackReleased` で打撃へ同期する（`SkinnedHeroModel.releaseSyncHeroIDs`、`release` = `impact`）。
  移動中は上半身だけ。攻撃速度が上がると打撃までを最大 4 倍、戻りを次の攻撃までに収める。強化通常攻撃・S1 の剣撃は演出側で、動作は同じ 3 段。
- スキル: 詠唱は専用のクリップを先頭から再生（`impact` = castLead）。S2・ULT は sim が動かす突進の間も脚をクリップのまま
  （`lockLowerUntil`。突進の後は移動すれば上半身だけ）。ULT は到着（`hit`）の手前で待ち、sim の 1 撃目の命中
  （`noteSkillHit` → `playCastHit`）で到着へ進める（最長 0.2 秒待って来なければそのまま）。ダメージ・射程・移動・発射時刻・操作可能時間は変えていない。

## 確認

- `HeroMotionClipTests.testBundledZailClipsGroundAndSync`: 割り当て・接地・攻撃速度 2 段の打撃の時刻と戻り・ULT の脚と到着の同期。
- Blender のコンタクトシート（`preview_clip.py --hero H028 --weapon R`）: 地面の最下点 −1.7 cm（歩行）〜 −3 cm（ULT の 1 コマ）。
- シミュレータのスクリーンショット: `bash tools/capture_h028_motion.sh [app] [接頭辞] [UDID]`（ギャラリーの各状態と、練習モードで
  sim の通常攻撃・S1・S2・ULT。変更前の main の app でも同じ条件で撮れる）。録画はしていない。
- 実機の FPS は測っていない。予算の上限は変えていない（骨は 23 → 65 で H025・H031・H034 と同じ。剣の面数は上の通り増えた）。

## 残り（未確認・保留）

- 急な旋回・坂・通信遅延時の見た目、実機での剣と装甲の細かな干渉はコミュニティ側の確認対象。
- ULT の打撃の軌跡（武器の軌跡）は 1 撃目の窓だけ（`weaponSwing` は 1 クリップ 1 打撃）。
- 歩行は元の動作の継ぎ目の誤差がやや大きい（1 周に配って 0 にしている）。
