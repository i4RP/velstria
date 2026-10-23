# 担当: battle-renderer（スキル演出の素材）。Tripo で作ったスキルのメッシュ（build/skill-meshes/<id>/model.glb）を
# 演出の模型（App/Resources/FX/Meshes/fxm_<shape>.bin）へ直す: 結合 → 三角形を上限まで間引き → 向きをそろえる → 単位の大きさ →
# UV（スマート投影）→ write_fxm。向き（tools/vfx_assets/skill_meshes.json の orient）:
#   upright  いちばん長い軸を上へ（柱・落ちる氷塊・立てた三日月）
#   forward  いちばん長い軸を前（-Z）、いちばん薄い軸を上へ（斬撃・突き・地割れ・扇）
#   facing   いちばん長い軸を上・いちばん薄い軸を前へ（盾の面を正面へ）
#   ground   いちばん薄い軸を上へ（輪・手裏剣・星・紋章を地面に寝かせる）
#   asis     生成のまま（竜・檻・氷の群れ）
# 大きさは最大の幅（水平）か高さ（upright）が 1。水平は中心、下端は y = 0（ground・forward は厚みの中心が y = 0）。
# VELSTRIA/ で: Blender -b --factory-startup -P tools/vfx_assets/blender/skill_mesh_to_fxm.py [-- --only h031_s1]

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fx_common as fc

ROOT = os.getcwd()
SPEC = os.path.join(ROOT, "tools/vfx_assets/skill_meshes.json")
OUT = os.path.join(ROOT, "App/Resources/FX/Meshes")
MAX_TRIS = 1400


def shape_name(asset_id):
    # h031_s1 → sk031s1（FXShape の case 名と同じ）
    h, s = asset_id.split("_")
    return "sk" + h[1:] + s


def axis_rotation(order):
    """order: 新しい (x, y, z) に置く元の軸の添字。右手系を保つ回転行列。"""
    cols = [Vector([1.0 if i == k else 0.0 for i in range(3)]) for k in order]
    m = Matrix((cols[0], cols[1], cols[2])).to_3x3()  # 行 = 新しい軸が元のどの軸か
    if m.determinant() < 0:
        m[0] = -m[0]
    return m.to_4x4()


def convert(asset):
    fc.reset_scene()
    src = os.path.join(ROOT, "build/skill-meshes", asset["id"], "model.glb")
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = obj.data
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > MAX_TRIS:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = MAX_TRIS / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    # 向き
    vs = [v.co for v in me.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    ext = hi - lo
    order = sorted(range(3), key=lambda i: ext[i])  # 薄い → 長い
    mode = asset.get("orient", "asis")
    if mode == "upright":
        new = [order[0], order[1], order[2]]           # 長い軸 → Z（上）
    elif mode == "forward":
        new = [order[1], order[2], order[0]]           # 長い軸 → Y（前）、薄い軸 → Z（上）
    elif mode == "facing":
        new = [order[1], order[0], order[2]]           # 長い軸 → 上、薄い軸 → 前（盾・紋章を正面へ向ける）
    elif mode == "ground":
        new = [order[1], order[2], order[0]]           # 薄い軸 → Z
    else:
        new = [0, 1, 2]
    obj.matrix_world = axis_rotation(new) @ obj.matrix_world
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    vs = [v.co for v in me.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    ext = hi - lo
    if mode in ("upright", "facing"):
        s = 1.0 / max(ext.z, 1e-6)
    else:
        s = 2.0 / max(ext.x, ext.y, 1e-6)  # 水平の半幅 1
        s = min(s, 1.6 / max(ext.z, 1e-6))  # 背の高い形でも単位の大きさ（1.8）に収める
    c = (lo + hi) * 0.5
    base_z = lo.z if mode in ("upright", "facing", "asis") else c.z
    for v in me.vertices:
        v.co = Vector(((v.co.x - c.x) * s, (v.co.y - c.y) * s, (v.co.z - base_z) * s))
    me.update()
    # 滑らかな陰影と UV
    for p in me.polygons:
        p.use_smooth = True
    # UV: 連続した投影（スマート投影は島が細かく、流れる模様が三角形ごとに途切れて破片に見えた）。
    # 地面に寝かせる形（ground・forward）は真上から（u = 右、v = 前）、他は縦軸まわりの円筒（u = 角度、v = 高さ）
    uvl = me.uv_layers[0] if me.uv_layers else me.uv_layers.new(name="UVMap")
    flat = mode in ("ground", "forward")
    for poly in me.polygons:
        us = []
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if flat:
                us.append([co.x * 0.5 + 0.5, co.y * 0.5 + 0.5])
            else:
                us.append([math.atan2(co.x, -co.y) / (2 * math.pi) + 0.5, co.z])
        if not flat:
            # 継ぎ目（角度が 1 → 0 へ跨ぐ面）は同じ側へ寄せる
            if max(u[0] for u in us) - min(u[0] for u in us) > 0.5:
                for u in us:
                    if u[0] < 0.5:
                        u[0] += 1.0
        for li, u in zip(poly.loop_indices, us):
            uvl.data[li].uv = u
    pos, nor, uv, idx = fc.mesh_arrays(obj)
    info = fc.write_fxm(os.path.join(OUT, "fxm_%s.bin" % shape_name(asset["id"])), pos, nor, uv, idx)
    info["id"] = asset["id"]
    return info


def main():
    args = fc.script_args()
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None
    spec = json.load(open(SPEC))
    report = []
    for a in spec["assets"]:
        if only and a["id"] not in only:
            continue
        if not os.path.exists(os.path.join(ROOT, "build/skill-meshes", a["id"], "model.glb")):
            print("[skip] %s: model.glb が無い" % a["id"], flush=True)
            continue
        info = convert(a)
        report.append(info)
        print("[fxm] %s → %s %d tris %d bytes" % (a["id"], shape_name(a["id"]), info["triangles"], info["bytes"]), flush=True)
    os.makedirs(os.path.join(ROOT, "build/skill-meshes"), exist_ok=True)
    json.dump(report, open(os.path.join(ROOT, "build/skill-meshes/fxm_report.json"), "w"), indent=1)


main()
