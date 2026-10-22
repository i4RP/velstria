# 担当: battle-renderer（スキル演出の素材）。fxm_sk*.bin を読み戻して 1 枚の一覧（6 列）に描く（向き・形の目視用）。
# VELSTRIA/ で: Blender -b --factory-startup -P tools/vfx_assets/blender/skill_mesh_preview.py -- --out build/skill-meshes/sheet.png

import glob
import math
import os
import struct
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fx_common as fc


def read_fxm(path):
    b = open(path, "rb").read()
    n, ni, _ = struct.unpack_from("<III", b, 4)
    v = [struct.unpack_from("<8f", b, 40 + k * 32) for k in range(n)]
    idx = struct.unpack_from("<%dI" % ni, b, 40 + n * 32)
    # 実行時 (x, y, z) → Blender (x, -z, y)
    verts = [(p[0], -p[2], p[1]) for p in v]
    faces = [idx[i:i + 3] for i in range(0, ni, 3)]
    return verts, faces


def main():
    a = fc.script_args()
    out = a[a.index("--out") + 1] if "--out" in a else "build/skill-meshes/sheet.png"
    fc.reset_scene()
    files = sorted(glob.glob(a[a.index("--glob") + 1] if "--glob" in a else "App/Resources/FX/Meshes/fxm_sk*.bin"))
    cols = 6
    for i, f in enumerate(files):
        verts, faces = read_fxm(f)
        me = bpy.data.meshes.new(os.path.basename(f))
        me.from_pydata(verts, [], faces)
        o = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(o)
        o.location = ((i % cols) * 3.0, -(i // cols) * 3.0, 0)
        # 前（+Y）を示す小さな棒
        cu = bpy.data.objects.new("fwd%d" % i, None)
        bpy.context.scene.collection.objects.link(cu)
        txt = bpy.data.curves.new("t%d" % i, "FONT")
        txt.body = os.path.basename(f)[4:-4]
        to = bpy.data.objects.new("lbl%d" % i, txt)
        to.location = o.location + Vector((-1.2, -1.4, 0))
        to.scale = (0.35, 0.35, 0.35)
        bpy.context.scene.collection.objects.link(to)
    rows = (len(files) + cols - 1) // cols
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    bpy.context.scene.collection.objects.link(cam)
    cx, cy = (cols - 1) * 1.5, -(rows - 1) * 1.5
    cam.location = (cx, cy - 14, 14)
    cam.rotation_euler = (math.radians(45), 0, 0)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(cols, rows) * 3.2
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.render.resolution_x, sc.render.resolution_y = 1800, 1500
    sc.render.filepath = os.path.abspath(out)
    bpy.ops.render.render(write_still=True)
    print("[preview]", out, len(files))


main()
