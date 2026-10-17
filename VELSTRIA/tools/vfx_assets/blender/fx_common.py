# 担当: battle-renderer（スキル演出の素材）。Blender をヘッドレスで回す素材づくりの共通の小道具。
# fx_meshes.py（UV 付きメッシュ → .fxm）・fx_render.py（コマ送り・模様の画像を Cycles で描く）から読む。
# 座標: Blender は Z が上・+Y が前。実行時（RealityKit）は Y が上・-Z が前なので、書き出しで (x, y, z) → (x, z, -y)。

import math
import os
import struct
import sys

import bpy


def script_args():
    """`blender -b -P script.py -- ...` の `--` より後ろの引数。"""
    argv = sys.argv
    return argv[argv.index("--") + 1:] if "--" in argv else []


def reset_scene():
    """空の場面にする（工場出荷の立方体・光・カメラを消す）。"""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    return scene


# --- .fxm（演出のメッシュの小さなバイナリ。App/Battle/Render/SkillFX/FXMeshes.swift の FXModelFile が読む） ---
# 形式（little endian）:
#   "FXM1"（4 バイト）, 頂点数 uint32, 添字数 uint32, 予約 uint32（0）,
#   境界 min xyz・max xyz（float32 × 6）,
#   頂点 × 頂点数: 位置 float32 × 3、法線 float32 × 3、UV float32 × 2（32 バイト。実行時の頂点の並びと同じ）,
#   添字 uint32 × 添字数（三角形のリスト。表は反時計回り。材質は両面で描くので向きは見た目に効かない）。

def to_runtime(v):
    """Blender の座標 → 実行時の座標（x 右・y 上・-z 前）。"""
    return (v[0], v[2], -v[1])


def write_fxm(path, positions, normals, uvs, indices):
    """頂点（Blender の座標）と添字を .fxm に書く。位置・法線は実行時の座標へ直す。"""
    assert len(positions) == len(normals) == len(uvs)
    assert len(indices) % 3 == 0
    n = len(positions)
    rp = [to_runtime(p) for p in positions]
    rn = [to_runtime(v) for v in normals]
    lo = [min(p[i] for p in rp) for i in range(3)]
    hi = [max(p[i] for p in rp) for i in range(3)]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"FXM1")
        f.write(struct.pack("<III", n, len(indices), 0))
        f.write(struct.pack("<6f", *lo, *hi))
        for p, q, t in zip(rp, rn, uvs):
            ln = math.sqrt(q[0] ** 2 + q[1] ** 2 + q[2] ** 2) or 1.0
            f.write(struct.pack("<8f", p[0], p[1], p[2], q[0] / ln, q[1] / ln, q[2] / ln, t[0], t[1]))
        f.write(struct.pack("<%dI" % len(indices), *indices))
    return {"vertices": n, "triangles": len(indices) // 3, "bounds": [lo, hi], "bytes": os.path.getsize(path)}


def mesh_arrays(obj):
    """評価後（モディファイア適用後）のメッシュ → 角ごとの頂点（位置・法線・UV）と三角形の添字。
    UV の継ぎ目で頂点を分けるため、ループ（角）単位で頂点を作り、同じ（位置・法線・UV）の角は 1 つにまとめる。"""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    uvl = me.uv_layers.active.data if me.uv_layers.active else None
    mw = obj.matrix_world
    nm = mw.to_3x3().inverted().transposed()
    corner_normals = None
    if hasattr(me, "corner_normals"):
        corner_normals = me.corner_normals
    positions, normals, uvs, indices = [], [], [], []
    seen = {}
    for tri in me.loop_triangles:
        for li in tri.loops:
            loop = me.loops[li]
            p = mw @ me.vertices[loop.vertex_index].co
            if corner_normals is not None:
                nv = corner_normals[li].vector
            else:
                nv = loop.normal
            q = (nm @ nv).normalized()
            t = tuple(uvl[li].uv) if uvl else (0.0, 0.0)
            key = (round(p.x, 5), round(p.y, 5), round(p.z, 5), round(q.x, 3), round(q.y, 3), round(q.z, 3),
                   round(t[0], 5), round(t[1], 5))
            k = seen.get(key)
            if k is None:
                k = len(positions)
                seen[key] = k
                positions.append((p.x, p.y, p.z))
                normals.append((q.x, q.y, q.z))
                uvs.append((t[0], t[1]))
            indices.append(k)
    ev.to_mesh_clear()
    return positions, normals, uvs, indices


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_object(name, verts, faces, uvs_per_face_corner):
    """頂点・面（頂点の添字の並び）と、面の角ごとの UV から Blender のオブジェクトを作る。"""
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    uv = me.uv_layers.new(name="UVMap")
    k = 0
    for poly in me.polygons:
        for j, li in enumerate(poly.loop_indices):
            uv.data[li].uv = uvs_per_face_corner[k]
            k += 1
    obj = bpy.data.objects.new(name, me)
    link(obj)
    return obj
