# H034 ゴルムの待機・移動・通常攻撃（初版）

対象は「鎖鉤のゴルム H034」（`Kit_H034` のフランコ相当）。`HeroAssetLibrary` が `Hero_H034.usdz` を読み、
`SkinnedHeroModel` が `H034MotionClips.json` を再生する（参加する時だけ読む: `HeroMotionClips.dedicatedHeroes`）。

## モデル

完成済みの Tripo モデル（task `e732348c`、顔・ひげ・鉄の肩当て・短い脚の体形）はそのまま。元のリグ（Tripo v1.0、23 骨）は
指が無く鉤を握れないので、同じ `model.glb` を Tripo v3 で 65 骨にリグし直し、`normalize_hero.py` で取り込み直した
（9,386 三角形・テクスチャは同じ、再生成なし）。`verify_usdz` は HeadTop_End の高さ（角の分だけ 1.54 m）以外 PASS。
元の USDZ は `build/h034-motion/Hero_H034_original.usdz`。

## 素材と採用

| クリップ | 素材 | 仕上げ |
|---|---|---|
| `idle_h034`（4.4 秒・1 呼吸） | Meshy prime idle は足を踏み替えるので参考のみ | 幅広の構え・膝を外へ・胸と肩と頭の呼吸の連動・鉤は右腰の前で固定・左手は腹の前・指の握り |
| `walk_h034`（0.9 秒、1.3 m/s） | Tripo v3 walk（胴の揺れを 25%） | 支持脚が地面に対して止まる接地 IK、足を広く着き体重を左右へ、上体は直立 |
| `run_h034`（0.63 秒、2.6 m/s） | Tripo v3 run（同上） | 前傾・低い腰・鉤を体へ引き寄せて肩の後ろへ寝かせる・左拳を振る |
| `chain_slam_h034`（37 フレーム） | Meshy prime attack | 構え → 小さな溜め → 頭上へ振りかぶり（9）→ 叩きつけ（13 = impact）→ 手繰って構えへ（36）。原本の腰の回転の 75% を除き、鉤の向きを手首で作り、足は接地 |

- 再生速度は `rate = speed / groundSpeed` なので、パッシブで速くなっても足は滑らない（歩幅一定・周期が速くなる）。
- 打撃は sim の `windup`（攻撃間隔の 25%）に合わせて再生速度を決める既存の経路（`startAttackClip`）。攻撃速度が上がっても
  打撃の時刻は sim と一致し、戻りは次の攻撃までに収まる。移動中は上半身だけ（下半身は歩容）。
- `HeroMotionSet.dedicatedAttack` で `Motion_H034.attacks`（手続きの全身の通常攻撃）より専用クリップを優先し、
  `dedicatedIdle` は `HeroIdle` の個別の待機（chainCaptain）に消されない（`HeroMotionSets.set`）。
- スキルもクリップ（`castsFromStart`: 発動の瞬間から再生し、打撃のフレームを KitTimes に置く。判定・数値は変えていない）。

| クリップ | 素材 | 時刻 |
|---|---|---|
| `hook_throw_h034`（S1） | Meshy prime hook | 背へ振りかぶり → 頭上から投げ放つ（10 = hookDelay 0.33 秒）→ 腕を伸ばして待つ → 外れたら手繰って戻る |
| `hook_pull_h034`（S1 命中） | 同上の後半 | `playCastHit` で始め直す: 鎖を張って踏ん張る（hookHold 0.45 秒）→ 引き寄せ（hookPull 0.25 秒、21）→ 構え |
| `chain_smash_h034`（S2） | Meshy prime slam | 沈んで両手で頭上へ → 叩きつけ（8 = shockDelay 0.27 秒）→ 起き上がる |
| `chain_frenzy_h034`（奥義） | Meshy prime ult | 掴みかかり（7.5 = ultDelay）→ 0.32 秒おきに 2 種の振りを交互（取り戻しを挟む）→ 6 撃目は頭上から最大の叩きつけ（55.5）→ 2.3 秒で構え |

  元の `Motion_H034` の詠唱はクリップが無い時の代わりとして残す。鉤の発射位置（スキル弾の出どころ）は未調整。

## 武器（Prop_hookChain）

旧版（Tripo、face_limit 2500 → 2,562 面）は粗かったので、生成用の 2D 画像から作り直した: `tools/tripo/assets.json` の
hookChain のプロンプトを詳細化（鋲の鉄帯・革巻きの柄・六角の口金・返しの付いた鉤・太い楕円の鎖）→ Tripo text-to-image
（seedream_v5）→ image-to-model（face_limit 8000）→ `node tools/tripo.mjs import props hookChain --max-faces 8000`
（7,728 面、検査 PASS、向きは旧版と同じ: 鉤が +X、棘が -X）。費用 65 credits。旧版は `build/h034-motion/Prop_hookChain_original.usdz`。

## 再現

`VELSTRIA/` で:

```sh
node tools/h034_motion_api.mjs inventory|prime|rigcheck|rig|basics|manifest   # 状態は build/h034-motion/api-state.json
Blender -b --factory-startup -P tools/blender/extract_h034_prime.py
Blender -b --factory-startup -P tools/blender/extract_clips.py -- --spec tools/motion/h034-tripo-spec.json \
  --out tools/motion/h034-tripo-source-clips.json --report build/h034-motion/tripo-report.json
Blender -b --factory-startup -P tools/blender/author_h034_motion.py
tools/capture_h034_motion.sh <VELSTRIA.app> build/h034-preview after
```

タスク ID・費用は [API 記録](MOTION_H034_API.json)（Meshy 70 = prime 7 本、Tripo 55 = v3 リグ 25 + idle/walk/run 30）。
キー・署名 URL はコミットしない。録画は `tools/capture_h034_motion.sh`（手元のシミュレータ用。CI では回さない）。
実機 FPS は計測していない。追加はクリップ 4 本（約 380 KB、参加時のみ読む）で、三角形・Entity・演出の予算は変えていない。

## 2026-10-23 左手首の修正

待機の左手をワールド固定の回転から、IK 後の左前腕に追従するニュートラルな手首へ変更。
手と前腕それぞれのレスト軸補正を使い、籠手の先で手が横へ折れる姿勢を解消した。
同じ構えを使う通常攻撃・スキルの出入りも再生成。歩行・走行、指、他の関節、判定時刻は変更なし。
Blender 5.2.1 の正面プレビュー（待機 3 位相）で確認。実機表示は未確認。
