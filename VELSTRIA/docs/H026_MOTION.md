# H026 エウリアの待機・移動・通常攻撃・スキルと球電（初版）

H033（[H033_MOTION.md](H033_MOTION.md)）と同じ手順。モデル `Hero_H026.usdz` は作り直していない。

- モーション: Meshy text-to-motion `prime` × 8（各 1 案、80 クレジット。記録は [MOTION_H026_API.json](MOTION_H026_API.json)）。
  `tools/h026_motion_api.mjs` → `tools/blender/extract_h026_prime.py` → `tools/blender/author_h026_motion.py` →
  `App/Resources/Heroes/H026MotionClips.json`。
  - 待機 `idle_h026`（4 秒ループ・足を固定・右の掌を胸の高さ）、歩行 `walk_h026`（1.18 m/s）、走行 `run_h026`（2.93 m/s）
  - 通常攻撃 `cast_bolt_h026`（前へ撃つ）／`cast_flick_h026`（払う）。impact は掌の速さが最大のコマ。名前の頭が cast なので近接扱いにならない
  - スキル（castLead 0.12 秒前から再生）: S1 `cast_fan_h026`（両手を前へ）、S2 `cast_ball_h026`（雷球の投擲）、
    奥義 `cast_thunder_h026`（天へ掲げ、+0.45 秒の落雷に合わせて振り下ろす）
- 球電 `Prop_ballLightning.usdz`（新規。以前は手続きのメッシュ）: Meshy Text to Image のコンセプト画像（6 クレジット）→
  Tripo image-to-model（60 クレジット。Meshy の残高が足りなかったため）→ `tripo.mjs import`（1,806 三角形・1024px）。
  `tools/h026_weapon_tripo.mjs` で再開できる。大きさ・置き方は `SkinnedHeroModel.propFit` が手続きの球電の外形に合わせる。
  Prop は不透明なテクスチャなので、手続き版の光る芯・半透明の殻の発光は無くなる（要確認）。
- 未確認: RealityKit の検査（macOS 専用）・アプリのテスト・実機の見た目。
