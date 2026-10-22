# H033 ヴァルドの待機・移動・通常攻撃・スキル（初版）

対象は「紅牙のヴァルド H033」（`Kit_H033`、Alucard 相当）。同梱の `Hero_H033.usdz`（23 骨・Tripo 製・
顔／紺のコート／右腕の銀の籠手／体形はそのまま）を `SkinnedHeroModel` が再生する。モデル・リグは作り直していない。
大剣は `Prop_bloodGreatsword`（右手の片手持ち。`HeroMotionSet.fistGrip` = 手の区間の -Z が刃の向き）。

## 変更前

- 通常攻撃: 共有ライブラリの `sword_slash_r` / `sword_combo_3` / `sword_slash_l2`（剣の汎用クリップ）
- 待機: `HeroIdle`（bloodHunter）の手続き。`combat_idle` は HeroIdle があるため使われていなかった
- 歩行・走行: `HeroGait`（bloodStride）の手続き
- スキル: `FX_H033.motion` の手続き（MotionBuilder）

## 制作

- Meshy Animation Library（678 件）は照会したが、Meshy の rig_task_id が必要なうえ、片手の大剣の持ち方に合う動作がなかった。
  そのため全動作を **Meshy text-to-motion `mode: prime`** で生成した（各 1 案。走行だけ 2 案目）。
  1 本 10 クレジットで計 11 本、**110 クレジット**。Tripo は使っていない（既存リグを維持。指の骨の補修はしていない）。
- タスク ID・プロンプト・費用は [API 記録](MOTION_H033_API.json)。原本の FBX と状態は `build/h033-motion/`
  （コミットしない）。`tools/h033_motion_api.mjs run` は再開できる。キュー満杯（429）は課金されないため、空くまで待つ。
- 走行の 1 案目は 5 m/s の全力疾走で、滞空が長く前傾も強かった。2 案目（重い小走り）を採用した。

## 仕上げ（`tools/blender/author_h033_motion.py`）

- SMPL-H → 15 区間: `extract_h033_prime.py`（H025 と同じ往復検証。四肢の誤差は最大 0.011°）
- 待機（`idle_h033`、4 秒ループ）: 剣側の肩を前（上体を 0.22 rad ひねる・右鎖骨を前へ）。両足は平均位置に IK で固定する。
  末尾 25% を先頭の姿勢へ補間して継ぎ目をなくした。大剣は低く前・外へ構え、刃先が地面より上になるよう補正する。
- 歩行（`walk_h033`、48 コマ）／走行（`run_h033`、22 コマ）: ソースから最適なループ区間を自動で選ぶ。
  水平の移動は除き、毎フレーム最も低い足を接地させる。対地速度は支持脚の後退速度から測った
  （歩行 1.22 m/s・走行 3.34 m/s）。実行時は `groundSpeed` で再生速度を合わせる。
  歩行は上体をほぼ直立、走行は前傾 0.26 rad。大剣は体に沿わせ、後ろ下へ流す。
  かかとが上がる間は、つま先の骨を曲げる。
- 通常攻撃: `sword_slash_h033`（斜めの斬り下ろし。impact 12/34）と `sword_chop_h033`（頭上からの叩き割り。impact 13/36）を
  交互に出す。ソースで手の速さが最大のコマを impact に置き、溜め → 振り抜き → 体幹で止めて構えへ戻るよう時間を詰めた。
  刃は前腕の延長（55%）とソースの手首の向きの混合。接地中の足は位置を固定し、踏み込みは 35%（最大 0.22 脚長）に抑える。
  先頭 4 コマと末尾 9 コマは待機の姿勢へ補間する。
  ソースの薙ぎ払い（attack2）は、俯瞰で弧が読み取れないため不採用。
- スキル（クリップは castLead 0.12 秒前から再生）:
  - S1 `leap_slam_h033`: 詠唱の tick に跳び、空中で大剣を頭上へ、10.6 コマ（+0.34 秒）の着地で振り下ろす。高さは原本の 40%。
  - S2 `spin_slash_h033`: 構えと腕だけ（原本の体の回転は除く）。回転は既存の `FX_H033.motion` の spin
    （左回り 1 周・+0.06 秒から）がモデル全体を回す（`motion.orientation = ry(p.yaw)` はクリップ中も効く）。
  - 奥義の段 0 `ult_absorb_h033`: 大剣の切っ先を上へ掲げて吸い込み（約 0.6 秒）、下ろす。
  - 奥義の段 1 `ult_wave_h033`: 0.16 秒の振りかぶりから前へ振り抜く（5 コマ目 ≒ 衝撃波の発射）。

## ゲームへの組み込み

- `HeroMotionClips.dedicatedHeroIDs = ["H025", "H033"]`: `H033MotionClips.json` は H033 が参加した時だけ読む（全ヒーローの一括ロードはしない）。
- `HeroMotionSets` の `vald`: `dedicatedIdle`（HeroIdle より優先）、walk / run、`casts`、`recasts`（段 1 の専用クリップ）、
  `castsFullBody`（S1 の跳び込みの移動中も全身で再生）。`set(heroID:)` が専用の待機を消していた不具合も直した（H025 にも効く）。
- `HeroAnimator`: `playCast(slot, stage:)` の段を覚え、段 1 に専用クリップがあれば同じ詠唱中でもクリップを始め直す
  （`castRestarts` が真になり、描画側が `playCast` を呼ぶ）。
- ダメージ・射程・移動・発射時刻・操作可能時間（sim）は変えていない。通常攻撃の命中はランタイムが impact を windup に合わせる
  （攻撃速度が上がると溜めが縮み、戻りは次の振りまでに収まる）。

## 確認

- Blender の比較動画: `blender -b -P tools/blender/preview_h033_motion.py` → `build/h033-motion/H033_motion_comparison.mp4`
  （左が変更前のクリップ、右が今回。Blender で姿勢を描いたもので、ゲーム画面の録画ではない。変更前の歩行・走行・スキルは
  手続きだったので、参考の汎用クリップか「表示なし」になる）。
- ゲーム内の再生: Actions「H033 Motion Preview」（`tools/capture_h033_motion.sh`）。iPhone 17 シミュレータで
  ギャラリー（待機・歩行・走行・攻撃・S1・S2・奥義 × 正面と横）と練習場（実際の通常攻撃・S1・S2・奥義）を録画し、
  HeroMotionClipTests ほかを実行する。シミュレータの値から実機の FPS は判断しない。
- 未対応: 指の骨が無いので握りの指は動かない。コートの布は骨に追従するだけで、大剣との干渉は刃の向きで避けているだけ。
  移動しながらの攻撃（下半身は移動クリップ、上半身は攻撃）と、パッシブの追撃の見た目は、コミュニティでの確認が必要。
