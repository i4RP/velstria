# 担当: hero-models。Tripo のリグ付きモデル（rigged.glb）の崩れた部品を、取り込み（tools/tripo.mjs import）の前に直す（Blender 5.2 headless）。
# 新しい生成はせず、元の rigged.glb から直した rigged.glb を作り、通常の取り込み（normalize_hero.py → verify_usdz）に通す。
#
# 使い方（VELSTRIA/ で）:
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
#     --python tools/blender/fix_hero_mesh.py -- --in <元の rigged.glb> --out <直した rigged.glb> \
#     [--cut-behind 0.38] [--part-behind 0.85] [--part-min-height 1.0] [--rebind mixamorig:Spine2]
#   直した rigged.glb を一時の build ディレクトリの heroes/<ID>/rigged.glb に置き、
#   TRIPO_BUILD_DIR=<一時> TRIPO_STATE_DIR=<一時> TRIPO_RESOURCES_DIR=<一時> node tools/tripo.mjs import heroes <ID>
#   で正規化・検査し、合格した Hero_<ID>.usdz を App/Resources/Heroes へ写す。
#
# 直すもの（距離・高さは正規化後のヒーロー空間の m = 元の寸法 × 正規化の倍率 --scale、腰が水平原点、前は元の glTF の +X）:
#   背中の後ろへ --part-behind m より遠くまで伸び、最も低い点が --part-min-height m より高い部品（溶接した頂点のつながり）を探し、
#   その部品のうち背中から --cut-behind m より後ろを切り取り、残りを --rebind の骨だけに付け直す。
#   H003 フィリエル（2026-10-11）: 矢筒の矢が背中の後ろへ 1.4 m 突き出した細い部品（頭 0.41・左前腕 0.31・左腕 0.28 の重みで
#   腕を下ろすと横・斜め上へ振れ、背中に剣が浮いて見えた）を、矢羽根の束だけ残して上の背骨に付けた。
#   python 側の読み込みは normalize_hero.py と同じ（merge_vertices = 継ぎ目で分かれた頂点を溶接）なので、部品は実際のつながり。

import argparse
import collections
import sys

import bmesh
import bpy
from mathutils import Vector


def parse():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser(prog="fix_hero_mesh.py")
    p.add_argument("--in", dest="src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--scale", type=float, default=1.703326, help="正規化の倍率（import_report.json の scale）")
    p.add_argument("--forward", default="+x", choices=["+x", "-x", "+y", "-y"], help="元の glTF の正面（Blender の座標）")
    p.add_argument("--part-behind", type=float, default=0.85)
    p.add_argument("--part-min-height", type=float, default=1.0)
    p.add_argument("--cut-behind", type=float, default=0.38)
    p.add_argument("--rebind", default="mixamorig:Spine2")
    return p.parse_args(argv)


def main():
    a = parse()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=a.src, import_pack_images=True, guess_original_bind_pose=True, merge_vertices=True)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    o = max([o for o in bpy.data.objects if o.type == 'MESH'], key=lambda m: len(m.data.vertices))
    hips = arm.matrix_world @ arm.data.bones["mixamorig:Hips"].head_local
    fwd = {"+x": Vector((1, 0, 0)), "-x": Vector((-1, 0, 0)), "+y": Vector((0, 1, 0)), "-y": Vector((0, -1, 0))}[a.forward]
    me = o.data
    mw = o.matrix_world
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    comp = [-1] * len(bm.verts)
    cid = 0
    for v in bm.verts:
        if comp[v.index] >= 0:
            continue
        stack = [v]
        comp[v.index] = cid
        while stack:
            x = stack.pop()
            for e in x.link_edges:
                y = e.other_vert(x)
                if comp[y.index] < 0:
                    comp[y.index] = cid
                    stack.append(y)
        cid += 1

    def behind(v):
        return -((mw @ v.co) - hips).dot(fwd) * a.scale

    max_b = collections.defaultdict(lambda: -1e9)
    min_h = collections.defaultdict(lambda: 1e9)
    for v in bm.verts:
        c = comp[v.index]
        max_b[c] = max(max_b[c], behind(v))
        min_h[c] = min(min_h[c], (mw @ v.co).z * a.scale)
    parts = {c for c in max_b if max_b[c] > a.part_behind and min_h[c] > a.part_min_height}
    keep = [v.index for v in bm.verts if comp[v.index] in parts and behind(v) <= a.cut_behind]
    cut = {v.index for v in bm.verts if comp[v.index] in parts and behind(v) > a.cut_behind}
    print(f"[fix] parts {sorted(parts)} cut {len(cut)} rebind {len(keep)} of {len(bm.verts)} verts", flush=True)
    if not parts:
        print("[fix] 直す部品が見つからない", flush=True)
        sys.exit(1)
    bm.free()

    group = o.vertex_groups[a.rebind]
    for i in keep:
        for g in list(me.vertices[i].groups):
            o.vertex_groups[g.group].remove([i])
        group.add([i], 1.0, 'REPLACE')
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index in cut], context='VERTS')
    bm.to_mesh(me)
    bm.free()
    me.update()
    bpy.ops.export_scene.gltf(filepath=a.out, export_format='GLB', export_skins=True, export_animations=False,
                              export_yup=True, export_apply=False)
    print(f"[fix] wrote {a.out} ({len(me.vertices)} verts)", flush=True)


main()
