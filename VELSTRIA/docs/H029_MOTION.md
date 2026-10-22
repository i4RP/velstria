# H029 ボルグの待機・移動・通常攻撃・スキル詠唱（初版）

対象は「聖槌のボルグ H029」（`Kit_H029` のティグリアル相当）。`HeroAssetLibrary` が
`Hero_H029.usdz` を読み、`SkinnedHeroModel` が再生する。変更前の main でもスキンメッシュで表示されていた
（手続きモデルへのフォールバックではない）。動きは、通常攻撃と詠唱が `Motion_H029` の全身モーション、
待機が `HeroIdle`（holyBulwark）、歩行が `HeroGait`（bulwarkTread）の手続きだった。

## モデル

完成済みのモデル（Tripo v1 リグ・23 骨、`33788ac` 由来）を保ち、指だけを足した。
元のリグは指が無く、平らな手で聖槌の柄を握れない。同じ形状を Tripo の v3 で 65 骨にリグし直すと
全身のウェイトが変わり、深くかがんだ時にマントが後ろへ板のように張り出したため、全身には使わなかった。
`tools/blender/graft_h029_fingers.py` で v3 の指 40 骨（20 骨＋指先）を v1 の手の子として同じ位置に足し、
v3 が指へ割り当てたウェイトの分だけを該当する 506 頂点へ移した（残りは v1 の比率のまま縮める）。
取り込みは従来の `node tools/tripo.mjs import heroes H029`（検査 PASS、9,508 面、5,125 頂点、元の 5,120 頂点・境界辺 598 とほぼ同じ）。
テクスチャ・UV・面は再生成していない。元の USDZ は `build/h029-motion/Hero_H029_original.usdz` に保管している。

## 素材（API）

- Meshy text-to-motion prime（10 credits × 8）: 待機・歩行・走行・通常攻撃・S1・S2 突進・S2 打ち上げ・ULT を各 1 案。
  プロンプトと秒数は `tools/motion/h029-prime-spec.json`。SMPL-H の FBX を `extract_h029_prime.py` で 15 区間へ変換
  （往復誤差 0.01° 以下）。2 案目は作っていない。
- Meshy Animation Library（678 件）を照会した。候補のうち既に同梱の抽出がある Heavy Hammer Swing（128 = hammer_swing）・
  Charged Ground Slam（127 = ground_slam）・Charged Upward Slash（221 = sword_upward）・Combat Idle（89 = combat_idle）を
  H029 のリグに載せて見比べた（`preview_clip.py --weapon R,L`）。槌は両手持ち・地面打ちは左の素手・振り上げは剣のひねり・
  待機は盾の腕が下がり、片手の聖槌と構えた盾に合う動作が無かった。H029 の Meshy リグも無いため Animation API は使っていない。
- Tripo: rig-check（無料）→ v3 リグ（25）→ idle / walk / run（animate_in_place、30）。v3 リグは指の提供元にだけ使った。
  idle / walk / run のプリセットは prime と比べて採用していない（汎用の歩きで盾と槌の構えが無い）。

タスク ID・費用・公式仕様は [API 記録](MOTION_H029_API.json)。原本は `build/h029-motion/`（git 管理外）。
状態は `tools/h029_motion_api.mjs` の journal（`build/h029-motion/api-state.json`）に残し、有料の送信は自動で再送しない。

## 仕上げ（`tools/blender/author_h029_motion.py`）

prime から、移動の腰・胴・頭の揺れ（歩行 f12→54、走行 f9→42 を 1 周に切り出し、終わり 15% を先頭へ混ぜる）と、
待機の体の揺れを差分として弱めて重ね、体の角度・手足は H029 の実寸で手付けして拘束した。

- 足: 接地中は地面に固定。移動は支持脚を移動速度を打ち消す一定速度で流し、離地は弧。かかと接地 → つま先の蹴り出し。
  水平の腰の移動は書き出さない（移動クリップは `rootXZ = 0`）。攻撃・スキルは足を地面に置いたまま腰を前後へ移す（`rootXZ = 1`）。
- 聖槌: 右手の区間の -Z（親指の側）を柄、前腕の向きを打撃面にし、手首の曲がりを 55〜130° に収める。
  打撃の間は槌頭の位置と柄の向きで右手を決め（打撃面が地面に当たる）、槌頭が地面より下へ入らないよう柄を起こす。
- 盾: 前腕に付けた向き（`HeroMotionSets.borgShieldGrip`: 盾の上 = 親指の側、盾の面 = 前腕を胸の前で横にした時の正面）。
  手続きの盾の角度（胴に対する絶対角）は使わず、クリップの左手に付いて動く。
- 肩（鎖骨）・指（握り、待機の握り直し）・つま先は `detailJoints`（H025 と同じ局所のレスト後差分）。

| クリップ | 長さ | 中身 |
| --- | --- | --- |
| `idle_h029` | 4.0 秒ループ | 広い足幅、4 秒の重い呼吸、頭と胸をゆっくり上げる、柄の握り直し（0.55〜0.75）。盾と槌は動かさない |
| `walk_h029` | 1.4 秒ループ | 接地 56%、上体は起こしたまま。groundSpeed 1.32 m/s |
| `run_h029` | 1.1 秒ループ | 接地 36%、盾を前にした前傾。groundSpeed 2.77 m/s（基本 2.6 m/s） |
| `maul_smash_h029` | 0.87 秒 | 振りかぶり 0.24 → 溜め 〜0.30 → 打ち下ろし → 0.40 命中 → 反動を肩と膝で受けて構えへ |
| `maul_wave_h029` | 1.0 秒 | 後ろ下 → 頭上 → 0.25 地を打つ → 低い構えのまま 0.75 で構えへ（2・3 回目の波を待たない） |
| `shield_charge_h029` | 1.0 秒 | 盾を前に 0.67 秒走り抜け → 押し込んで止まる。移動中も脚はクリップ（`castLocksLegs`） |
| `maul_upswing_h029` | 0.83 秒 | 右後ろ下へ引く → 0.2 で下から振り上げ → 頭上 → 構え |
| `maul_sanctuary_h029` | 1.7 秒 | 槌を掲げ盾を上げて反る（引き寄せ 0.67）→ 1.0 で前の地面へ叩き落とす → 沈んで構えへ |

## 再生経路

- `HeroMotionClips.dedicatedHeroes` に H029 を足し、参加時だけ `H029MotionClips.json` を読む（約 0.6 MB、全ヒーローの一括読み込みはしない）。
- `HeroMotionSets["H029"]`（borg）: `dedicatedIdle`（HeroIdle より優先。`set(heroID:)` は専用の待機を外さない）、
  `dedicatedAttack`（`HeroMotionProfile` が Motion_H029 の全身の通常攻撃を使わない）、`walk` / `run`（速度で切り替え）、
  `casts` と `stageCasts`（S2 の再使用の段）、`castLocksLegs`（S2 の突進）、`stateBlend` 0.2 秒、`offhandGrip`（盾）。
- 通常攻撃は既存の規則（`startAttackClip`）で命中を sim の windup（攻撃間隔 × 0.25）へ合わせる（打撃まで 0.5〜4 倍速）。
- 詠唱のクリップは `Motion_H029.clipStrike`（KitTimes）から開始位置を決め、発動から判定の時刻に打撃が来る
  （S1 `waveFirstDelay` / S2 `dashRange / dashSpeed` / 再使用 `smashDelay` / ULT `ultTotal`）。判定・数値・操作可能時間は変えていない。
  詠唱の状態の長さは従来どおり Motion_H029 の手続きのモーション（光の演出も手続きのまま）。
- クロスフェード: 待機・移動は `stateBlend` 0.2 秒、通常攻撃と詠唱はクリップの JSON の `blend`（攻撃 0.12 = windup の 65% まで、詠唱 0.06〜0.08 秒）。

詠唱の手続きのモーション（Motion_H029.cast）はクリップの下に敷かれ、クリップが無い・読めない時はそれだけで動く。

## 再現と確認

`VELSTRIA/` で実行する。

```sh
node tools/h029_motion_api.mjs inventory          # 無料
node tools/h029_motion_api.mjs prime               # 送信済みなら取得だけ
blender -b -P tools/blender/extract_h029_prime.py
blender -b -P tools/blender/author_h029_motion.py
blender -b -P tools/blender/preview_h029_motion.py -- --view 34,overhead [--video]
bash tools/capture_h029_motion.sh <Debug のシミュレータ .app> build/h029-motion/capture-after after
```

`AppTests/H029MotionClipTests` が、割り当て・手続きに上書きされないこと・命中の時刻（基本と攻撃速度上昇時）・
詠唱の打撃 = KitTimes・歩行と走行の切り替えを確かめる。
`HeroFullBodyMotionTests` は、通常攻撃を専用の収録で振るヒーロー（`dedicatedAttack`: H029・H034）の全身の通常攻撃の検査を外す。

2026-10-23 の確認（macOS / Xcode 26.2 / iPhone 17 シミュレータ iOS 26.3、Debug）:
H029MotionClipTests・HeroMotionClipTests・SkinnedHeroModelTests・HeroFullBodyMotionTests・HeroModelTests は通過。
RenderWarmupTests の 5 件（試合中のアセット生成 entity 6 / material 2、ゾーンのプール 29 ≠ 12）は、変更前の origin/main でも同じ値で落ちる既存の失敗。
実際の RealityKit 再生をギャラリー（待機・歩行・走行・攻撃・S1・S2・ULT、正面と側面）と練習場（-efkAuto atk / s1 / s2 / ult）で
変更前・変更後とも録画した（`build/h029-motion/compare/`、git 管理外）。並行セッションでシミュレータが高負荷のため、ギャラリーの録画は
コマが落ちて止まって見える区間がある（HeroAnimator の単体の追跡では 0.8 秒ごとに振り続けている）。
シミュレータの録画は実機の FPS の根拠にしない。既存の三角形・Entity・演出の予算は引き上げていない。
