# H027 竜槍のジャルドの待機・移動・通常攻撃・スキル動作と竜槍（初版）

対象は「竜槍のジャルド H027」（`Kit_H027` の子龍相当）。`HeroAssetLibrary` が `Hero_H027.usdz` を読み、`SkinnedHeroModel` が
`H027MotionClips.json` のクリップを再生する（手続きモデルへのフォールバックではないことをシミュレータのギャラリー・練習場で確認）。

## モデルと竜槍

- 体: 10/11 に Tripo で作った完成モデル（task `d2273084…`、9,342 三角形、テクスチャ 3 枚）をそのまま使う。元のリグは 23 骨で指が無く
  槍を握れないため、同じ `model.glb` を Tripo v3 の自動リグ（`v3.0-20260909`、mixamo、65 骨）へ渡して付け直した（25 credits）。
  形状・テクスチャは同じ（面数 9,342 で一致、テクスチャは同名・同解像度。腰を原点に置き直したため全体が前後に 1.8 cm ずれるだけ）。
  元の USDZ は `build/h027-motion/Hero_H027_original_23j.usdz`。
- 竜槍（`Prop_dragonSpear.usdz`）: 低ポリゴン（2,472 面）だったので 2D 生成画像から作り直した。Tripo text-to-image（seedream_v5、5）→
  image-to-model（P1、face_limit 20,000、60）→ `tools/blender/lod_h027_spear.py` で UV の継ぎ目を溶接してから穂先・竜頭 3,898 / 柄 300 に
  配分して 4,198 面へ（一律の減面は柄に面を使い、継ぎ目で穴が開いた）。ヒーローの予算（体 + 武器 < 14,000）内。取り込みは
  `node tools/tripo.mjs import props dragonSpear --max-faces 4200`、`assets.json` の yaw は 0（竜の顔と刃の面が +Z。-90 だと横向き）。

## 制作

1. Meshy: Animation Library 678 件を照会し、Spear Walk（560/672）・Thrust Slash（240）などをプレビュー GIF で確認。どれも片手剣・
   素手の動作で両手の長柄を保たないため不採用。Text to Motion の prime で 9 本（待機・歩行・走行・突き・払い・切り上げ・跳槍撃・
   竜牙突き・至高の武人）を各 1 案だけ生成（90 credits、指示は `tools/motion/h027-prime-spec.json`）。
2. Tripo: v3 リグに idle / walk / run のプリセット（animate_in_place）を当てた（30 credits）。比較の素材（`tools/motion/h027-source-clips.json`）。
3. `tools/blender/extract_h027_prime.py` が SMPL-H の FBX を区間回転 + 肩・つま先の差分へ変換（往復の誤差は 0.01° 未満）。
4. `tools/blender/author_h027_motion.py` で仕上げる。prime は体（腰・胴・頭の回転と腰の高さ）の動きとして時間を合わせて重ね、
   槍は「握りの位置 + 柄の向き」をキーで振り付ける。右手は柄の向きと前腕から手首の向き（親指 = 穂先側）を決め、左手は柄の上の点へ
   2 骨 IK（肘は蝶番の軸、前腕のねじれは 55% を前腕へ）。指は握り（左右）・空いた手の握り直し。足は接地のまま（歩行・走行は支持脚が
   地面の速さを打ち消す）。石突・穂先と地面・脚・胴・マントの距離、IK の届かない量、ループの継ぎ目をレポート（`build/h027-motion/finish-report.json`）。

再現（`VELSTRIA/` で）:

```sh
node tools/h027_motion_api.mjs poll          # 取得済みの task から再開（有料の再送はしない）
/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/extract_h027_prime.py
/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/author_h027_motion.py
/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/preview_h027_motion.py -- --view 34 [--prop App/Resources/Heroes/Prop_dragonSpear.usdz]
tools/shoot_h027_motion.sh <UDID> idle run attack skill1 skill2 ult   # シミュレータのギャラリーの静止画
```

## クリップ（30fps）

| クリップ | 長さ | 内容 |
|---|---|---|
| h027_idle | 6.0 秒ループ | 胸を張った前後の構え。槍は右手で前上へ傾けて保ち（穂先は動かさない）、呼吸 2 回・前後の重心移動・左 → 右の見渡し・空いた左手の握り直し |
| h027_walk | 1.0 秒ループ（1.15 m/s） | 上体を起こし、槍を立てたまま膝を送り出す |
| h027_run | 0.733 秒ループ（3.0 m/s） | 前傾し、槍を右腰に沿わせて穂先を前へ低く寝かせる（石突は外へ） |
| h027_thrust | 28 フレーム、打撃 10 | 引き（柄が左手の中を滑る）→ 左足の踏み込みと腰 → 胸 → 肩の回転で突く → 引き戻し |
| h027_sweep | 30 フレーム、打撃 10 | 右へひねって引き、左手を離して腰の高さで右 → 左へ払う |
| h027_rising | 30 フレーム、打撃 10 | 前下へ下ろし、脚と腰で伸び上がって頭上へ切り上げ |
| h027_flurry | 34 フレーム、打撃 10 / 14 / 18 | 竜の三連突き（sim の 4 tick おき）。打撃の後は等速 |
| h027_flip | 40 フレーム、打撃 4 | 跳槍撃: 掬い上げ → 頭上で保持（〜12）→ 背を反らして頭上を越えて背後へ（12〜18） |
| h027_strike / h027_strike_hit | 14 / 22 フレーム | 竜牙突き: 突進の姿勢（脚もクリップ）→ 命中で到着の突き（打撃 3） |
| h027_warrior | 24 フレーム、打撃 4 | 至高の武人: 槍を右手で立て、左の拳を胸の前で握って気を高める（移動中は上半身だけ） |

## ゲームへの組み込み

- `HeroMotionClips.dedicatedHeroes` に H027 を加え、専用ファイルを参加時だけ読む。`HeroMotionSets` の H027 は専用の待機（`dedicatedIdle`）を
  HeroIdle より優先し、歩行 / 走行の切り替え、槍の握り `rx(-π/2)·ry(-0.1658)`
  （仕上げで解いた値。クリップ中は槍が右手の区間に追従）。
- 三連突きは専用クリップ（`HeroMotionSet.empowered`、`HeroAnimator.playAttack(empowered:)`）。打撃の後を等速にして 2・3 発目を sim の時刻に保つ。
  手続きの `Motion_H027.empoweredAttack` はクリップの無いモデル用に残る。
- 詠唱はクリップ（打撃 = 呼び出しの 0.12 秒後。演出の時刻は FX_H027 のまま）。竜牙突きは `castLocksLegs`（突進中に足を回さない）と
  `castHits`（sim の命中で到着の突き。手続きの命中の後のモーションを持つ H034 の経路は変えない）。ダメージ・射程・移動・発射時刻・操作可能時間は変えていない（sim は無変更）。
- 速度: 移動ループは速度に比例して再生（奥義の 3.7 m/s で 1.24 倍）、攻撃は打撃を windup に合わせ、戻りを次の攻撃までに縮める。

## 確認（2026-10-23、macOS / Xcode 26.2 / iPhone 17 Pro シミュレータ、Blender 5.2.1）

- Blender: IK の届かない量は切り上げの 18 mm 以外 0、ループの継ぎ目 0°、地面との距離は最小 6.5 cm（奥義の石突）。
  石突と胴の近接（2〜6 cm 食い込み）が突き・払い・三連突きの一部のフレームに残る（判定はカプセル近似）。
- シミュレータ: ギャラリーの待機・走行・通常攻撃・奥義、練習場（`-efkAuto s1`）で新しいモデル・槍・クリップが表示されることを静止画で確認
  （`build/h027-motion/H027_before_after_game.png` は変更前の main のビルドとの比較）。シミュレータの値から実機 FPS は主張しない。
- 未確認: 実機、スキルの各フレームのゲーム内の静止画（ギャラリーは詠唱を 1 度しか流さず、練習場は撮影間隔が 1 秒前後）、
  急旋回・傾斜・通信遅延時の見た目。詳細な検証はコミュニティ側の確認対象。
