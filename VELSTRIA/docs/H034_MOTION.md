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
- スキル（S1 鎖鉤・S2 鉄鎖旋・奥義）は従来どおり `Motion_H034` の詠唱（KitTimes に合わせた打撃）。prime の hook / slam / ult は
  生成・抽出済み（`tools/motion/h034-prime-source-clips.json`）で、次の段で詠唱へ組み込む。

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
キー・署名 URL はコミットしない。比較動画は Actions「H034 Motion Preview」（before = 変更前の main、after = この版）。
実機 FPS は計測していない。追加はクリップ 4 本（約 380 KB、参加時のみ読む）で、三角形・Entity・演出の予算は変えていない。
