# H030 ライナの待機・移動・通常攻撃（初版）

対象は「星砲のライナ H030」（`Kit_H030` の Layla 相当）。`HeroAssetLibrary` が `Hero_H030.usdz` を読み、
`SkinnedHeroModel` が `H030MotionClips.json` を再生する（参加した時だけ読む。`HeroMotionClips.dedicatedHeroes`）。

## モデル

完成済みモデル（Tripo model `38220600…`、23 骨・指なし）の形状・テクスチャをそのまま Tripo v3 リグへ渡し、65 骨（指・つま先）へ補修した。
モデルの再生成はしていない。8,864 三角形・テクスチャ 3 枚は同じ。旧リグはツインテールが腕の骨に乗っていて、腕を上げると髪が
伸びて崩れていた（補修後は髪が頭に乗る）。元の USDZ は `build/h030-motion/Hero_H030_original.usdz`。

## 使ったサービス

- Tripo v3: rig-check（0）→ rig（25）、プリセット idle / walk / run（30、`animate_in_place`）。プリセットは取得したが、
  砲を抱える腕・前傾が合わないので採用していない（比較用に `build/h030-motion/` に保存）。
- Meshy: Animation Library 678 件を照会（550 Carry Heavy Cannon Forward、511/654 Rifle Charge、104 Side Shot など）。
  ライブラリの適用には Meshy の rig が要り、どれも砲を腰に抱える持ち方ではないため使っていない。
- Meshy text-to-motion prime（各 10）: 砲撃（3 秒）、奥義のビーム（3.5 秒）、砲を抱えた歩行（2 秒）。計 30。

タスク ID・プロンプト・費用は [API 記録](MOTION_H030_API.json)。中断後は `tools/h030_motion_api.mjs` の状態記録
（`build/h030-motion/api-state.json`）から再開する。

## 仕上げ（tools/blender/author_h030_motion.py）

- 砲: 実行時は `handR × fistGrip` の向きに、砲の軸で `weaponOffset (0, 0, -0.16)` ずらして置く（右の掌を砲身の上に乗せる。
  `HeroMotionSet.weaponOffset`）。仕上げは砲の芯の位置・砲口の向きを決め、右手首を IK で合わせる。砲口・発射位置は武器の
  先端（`weaponTip`）なので、砲の向きと弾の出る位置は常に一致する。
- 待機 `idle_h030`（3.2 秒ループ）: 右手だけで砲を腰に支え、左手は腰に当てて指先を軽く叩く。呼吸・右脚への重心・
  砲へ視線を落として首を傾ける。両端は同じ姿勢。
- 歩行 `walk_h030`（0.96 秒、基準 1.0 m/s）・走行 `run_h030`（0.62 秒、2.4 m/s）: 両手で砲を抱え、左手は砲身の左。
  支持脚は移動速度を打ち消す足運び（足滑りなし）、短く弾む歩幅。走行は砲を体へ寄せて前傾。腰・胴の揺れは prime の歩行から
  上限付きで取る。速度で歩行／走行を切り替え、位相を引き継ぐ（H025 と同じ実行時）。
- 通常攻撃 `gun_cannon_h030`（36 フレーム、11 フレーム目に発射）: 砲を上げて照準 → 7〜11 で膝を沈めて踏ん張る → 発射 →
  反動で砲口が上がり砲が後ろへ、胴が反って肩（補助関節）が上がり、腰で受ける → 構えへ戻る。人差し指は発射で引き金を絞る。
  発射の表示はシムの `attackReleased` に合わせる（H025 と同じ `awaitAttackRelease` / `synchronizeAttackRelease`）。
  高速連射は戻りの速度を上げる（既存の `startAttackClip`）。移動中の攻撃は下半身の歩行を保つ。

## 確認

Windows / Blender 4.5.10 LTS: 手足の目標への到達誤差 0 mm、ループ・攻撃の両端の差 0°、メッシュの最下点 -0.7〜+4.7 mm。
比較動画（Blender の姿勢プレビュー、ゲームの描画ではない）: `build/h030-motion/H030_motion_comparison.mp4`。
実際の RealityKit の再生は Actions の `H030 Motion Preview`（シミュレータの録画。実機 FPS の根拠にはしない）。

スキル（S1 遠星弾・S2 星爆弾・ULT 星砕の大砲）の詠唱は従来どおり FX_H030 の手続きモーション。
