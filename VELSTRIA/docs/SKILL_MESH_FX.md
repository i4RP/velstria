# スキルの攻撃の模型（参照画像 → メッシュ → 演出）

名簿の 10 体（H025〜H034）のスキル 1・スキル 2・アルティメット、計 30 スキルに、攻撃の瞬間の模型を 1 つずつ重ねる。

1. 参照画像: Tripo `POST /v3/generation/text-to-image`（seedream_v5、5 credits）。単体の造形・無色のガラス質で描かせ、色は実行時の
   ヒーローのパレット（FXTint）で付ける。
2. メッシュ: Tripo `POST /v3/generation/image-to-model`（P1-20260311、face_limit 2000、テクスチャ無し、40 credits）。
3. 演出の模型: `tools/vfx_assets/blender/skill_mesh_to_fxm.py` が結合 → 1400 三角形まで間引き → 向き（orient）→ 単位の大きさ →
   スマート UV → `App/Resources/FX/Meshes/fxm_sk<番号><段>.bin`（既存の .fxm 形式。FXShape の `sk025s1` など）。
4. 再生: `App/Battle/SkillFX/FXSkillMeshes.swift` の表が、各ヒーローの演出（FX_H0xx）を組み立てた後に段（cast / impact / hit）へ
   メッシュ 1 枚を足す（色・大きさ・寿命・回転・上昇・前進）。プールは形ごとに 2（試合のレシピが使う形だけ）。

仕様は `tools/vfx_assets/skill_meshes.json`（造形の指示・向き）、task_id と費用は `tools/vfx_assets/skill_meshes_state.json`。
生成物（画像・GLB）は `build/skill-meshes/<id>/`（git 管理外）。30 件で 1350 credits（Tripo）。

```sh
node tools/vfx_assets/skill_meshes.mjs run all --max-credits 1400   # 429（生成の上限）は課金なしで待って送り直す
node tools/vfx_assets/skill_meshes.mjs status
Blender -b --factory-startup -P tools/vfx_assets/blender/skill_mesh_to_fxm.py [-- --only h031_s1]
Blender -b --factory-startup -P tools/vfx_assets/blender/skill_mesh_preview.py   # build/skill-meshes/sheet.png
```

向き（orient）: upright = 長い軸を上、forward = 長い軸を前（-Z）・薄い軸を上、facing = 長い軸を上・薄い軸を前、
ground = 薄い軸を上（地面に寝かせる）、asis = 生成のまま。先端がどちらを向くか（矢の頭など）は自動では決めていない。

予算: H029 スキル1 はメッシュの合図の上限（20）に当たるため、1 回目の小さな爆ぜの焦げたひびを省いて枠を空けた（上限は上げていない）。
