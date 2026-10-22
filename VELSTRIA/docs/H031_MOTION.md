# H031 オーリアの待機・移動・通常攻撃・スキル詠唱（初版）

対象は「氷嵐のオーリア H031」（Aurora 相当）。`Hero_H031.usdz` を `SkinnedHeroModel` が再生する。
モデル（顔・ローブ・体形・氷の光輪の冠・氷華の右手）は 10/11 の Tripo 生成物をそのまま使い、作り直していない。

## モデルとリグ

元のリグは 23 骨で指が無く、掌・指の形を作れないため、同じ元メッシュ（Tripo model task の `model.glb`）を
Tripo v3 の rig-check → rig（mixamo 仕様 65 骨）に通し、既存の `tripo.mjs import heroes` の正規化で USDZ 化した。
三角形数 8805・テクスチャ 3 枚・身長 1.7 m は変わらず、レスト姿勢の見た目は元と同一（比較画像は build/h031-motion/sheets/rest_compare.png）。
取り込み検査の「HeadTop_End ≈ 身長」だけが不合格（冠の分だけ身長が頭頂より高い。旧 23 骨には HeadTop_End が無く検査されていなかった）なので、
検査の出力（rejected_Hero_H031.usdz）を目視確認のうえ採用した。

## 素材（API の記録は docs/MOTION_H031_API.json）

- Meshy text-to-motion（mode prime、1 動作 1 案、各 10 credits）: 待機 4 秒・歩行・走行・通常攻撃・S1・S2・ULT。
- Meshy Animation Library（678 件）を照会。魔法の候補（Mage Spell Cast 129〜137・Charged Ground Slam 127）は
  既に `HeroMotionClips.json` の cast_* / ground_slam として同梱済みで、旧割り当て（cast_throw / cast_point）と比較の基準にした。
  新規購入はしていない（Library の適用には Meshy の rig_task_id が要る）。
- Tripo: rig-check（0）・rig（25）・idle/walk/run プリセット（その場、30）。プリセットの歩行は体全体が左右へ大きく揺れ、
  女王の歩様に合わないため比較のみで不採用。

prime の歩行・走行は「その場」と指示しても腰が流れ、足の運びがループにならないため足には使わない。

## 仕上げ（tools/blender/author_h031_motion.py）

- 待機（4 秒ループ）: prime の待機の体幹に、呼吸・小さな左右の重心移動・高い顎・頭の小さな振り。右手は腰の高さで掌を上へ、
  指を 1 本ずつずらしてゆっくり曲げ伸ばし。左手は腰の前。継ぎ目は終わりの 20% で先頭へ戻す（継ぎ目 0°）。
- 歩行 1.25 m/s・走行 2.7 m/s（素の移動速度 2.5 m/s で走行を 0.93 倍速）: 狭い足幅（±7 cm）の接地 IK、
  支持脚は移動速度を打ち消す。歩行は上体をほぼ動かさず、走行は軽い前傾と肘を曲げた小さな腕振り。手は体の外側に保つ。
- 通常攻撃（1.0 秒、放つ瞬間 = 12 フレーム）: 右手を胸へ引き寄せ（掌を丸め、腰・胸を右へひねる）→ 敵へ差し出し、
  指先まで伸ばして掌を前へ → 肩と体幹で反動 → 待機姿勢へ。release を持ち、シムの attackReleased（弾の発射）に同期する
  （H025 の仕組みを H031 にも有効化）。高速連射は既存の速度調整（打撃まで 0.5〜4 倍、戻りは次の攻撃まで）に任せる。
- S1（0.9 秒）: 右手を掲げて前方の地面を人差し指で指し、0.45 秒から戻る（着弾 0.57 秒まで硬直させない）。
- S2（1.0 秒）: 0.2 秒に右手を体の横で丸めて冷気を集め、0.22〜0.38 秒に掌を右→左へ払い、0.48 秒に前へ押し出す（扇の向き）。
- ULT（1.1 秒）: 右手を頭上へ掲げ、0.27 秒に掌を前方の地面へ振り下ろす（屈みは prime の 4 割程度に抑える）→ 0.45 秒から起き上がる。
- 詠唱クリップは先頭 = 呼び出しの瞬間（impact 3.6 フレーム = castLead 0.12 秒）。移動中は上半身だけ（既存の規則）。
- 足は全クリップで狭い足幅に接地 IK、攻撃・詠唱の始まりと終わりは待機の先頭姿勢と一致（戻り 0〜0.22°）。

既存 15 区間に加え、肩 2・つま先 2・指 30 を `detailJoints` / `detailRot`（H025 と同じ形式）で出力。

## ゲームへの組み込み

- `HeroMotionClips.dedicatedHeroes` に H031 を追加（参加した時だけ `H031MotionClips.json` を読む）。
- `HeroMotionSets` の H031: 攻撃 `cast_frost_h031`、待機 `idle_h031`（dedicatedIdle で HeroIdle の待機に消されない）、
  歩行・走行 `walk_h031` / `run_h031`（HeroGait の手続きを全身で上書き）、詠唱 `cast_s1_h031` / `cast_s2_h031` / `cast_ult_h031`。
- ダメージ・射程・移動・発射時刻・操作可能時間は変更していない。新しい Entity・演出・毎フレームの確保は無い。

## 再現

```sh
node tools/h031_motion_api.mjs prime            # 状態は build/h031-motion/api-state.json（再実行は取得だけ）
Blender -b -P tools/blender/extract_h031_prime.py -- --input build/h031-motion/h031_prime_<name>.fbx ...
Blender -b -P tools/blender/author_h031_motion.py
bash tools/capture_h031_motion.sh               # シミュレータ（実機 FPS の根拠にはならない）
```
