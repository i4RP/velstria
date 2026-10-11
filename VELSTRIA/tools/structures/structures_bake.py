# 担当: battle-renderer（構造物・ミニオンの生成モデル）。Blender 5.2 headless で実行する:
#   Blender -b --factory-startup --python tools/structures/structures_bake.py -- --id tower --glb build/structures/tower/model.glb \
#       --out App/Resources/Structures --work build/structures/tower --faces 5000 --size '{"height": 4.35}'
# tools/structures/structures.mjs bake から呼ぶ。
#
# 1. GLB を読み、メッシュを 1 つに結合・変換を適用する（Blender は Z 上。USD 書き出しで Y 上・正面 -Z = Blender +Y）
# 2. 仕様の yaw（Z 軸回り、度）で正面を合わせ、size（height / diameter / length）で拡縮する
#    origin: base = 足跡の中心が原点・最も低い点が 0（地面に置く物）、center = 外接箱の中心が原点（浮遊する物）
# 3. 三角形数が faces を超えたら Collapse で間引く
# 4. ベースカラーを texture px（既定 1024）に縮め、発光マスク（明るく彩度の高い青〜紫の画素）から発光テクスチャを作る。
#    赤チーム用に色相を付け替えたベースカラー・発光テクスチャを Struct_<id>_red.jpg / Struct_<id>_red_emit.jpg として書く
#    （メッシュは 1 つ。実行時に材質のテクスチャだけ差し替える）
# 5. 材質は 1 つ（ベースカラー + 発光、粗さ・金属は定数）にして USDZ（Struct_<id>.usdz）へ。確認用の画像を work に置く
import argparse
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "blender"))
import norm_common as nc  # noqa: E402

# 赤チームへ付け替える色相の範囲（度）。青緑〜青〜紫 → マゼンタ〜赤（金・茶・灰は触らない）
TEAM_HUE = (165.0, 300.0)
RED_HUE = (328.0, 378.0)
TEAM_MIN_SAT = 0.14


def log(msg):
    print(f"[bake] {msg}", flush=True)


def parse():
    p = argparse.ArgumentParser(prog="structures_bake.py")
    p.add_argument("--id", required=True)
    p.add_argument("--glb", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--work", required=True)
    p.add_argument("--faces", type=int, default=5000)
    p.add_argument("--size", default="{}")
    p.add_argument("--origin", default="")
    p.add_argument("--yaw", type=float, default=None)
    p.add_argument("--texture", type=int, default=0)
    return p.parse_args(nc.script_args())


def transform(obj, m):
    obj.matrix_world = m @ obj.matrix_world
    nc.apply_transforms([obj])


def base_image(obj):
    for m in obj.data.materials:
        if not m or not m.node_tree:
            continue
        for n in m.node_tree.nodes:
            if n.type != 'BSDF_PRINCIPLED':
                continue
            inp = n.inputs.get("Base Color")
            if inp is None or not inp.is_linked:
                continue
            src = inp.links[0].from_node
            # 間に色の補正ノードがあれば 1 段たどる
            for _ in range(3):
                if getattr(src, "image", None):
                    return src.image
                ins = [i for i in src.inputs if i.is_linked]
                if not ins:
                    break
                src = ins[0].links[0].from_node
    for img in bpy.data.images:
        if img.size[0] > 0 and "normal" not in img.name.lower() and "rough" not in img.name.lower() \
                and "metal" not in img.name.lower():
            return img
    return None


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = np.max(rgb, axis=-1)
    mn = np.min(rgb, axis=-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rm = nz & (mx == r)
    gm = nz & (mx == g) & ~rm
    bm = nz & ~rm & ~gm
    h[rm] = ((g[rm] - b[rm]) / d[rm]) % 6
    h[gm] = (b[gm] - r[gm]) / d[gm] + 2
    h[bm] = (r[bm] - g[bm]) / d[bm] + 4
    h = h * 60.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    h = (h % 360.0) / 60.0
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p = v * (1 - s)
    q = v * (1 - s * f)
    t = v * (1 - s * (1 - f))
    out = np.zeros(h.shape + (3,), dtype=np.float32)
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k
        out[m, 0] = a[m]
        out[m, 1] = b[m]
        out[m, 2] = c[m]
    return out


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def team_textures(px):
    """px: (h, w, 4) の 0〜1（sRGB の値）。(発光, 赤のベース, 赤の発光) を返す。"""
    rgb = px[..., :3]
    h, s, v = rgb_to_hsv(rgb)
    in_team = (h >= TEAM_HUE[0]) & (h <= TEAM_HUE[1])
    # 発光: 明るく彩度の高い青〜紫（結晶・光点）。白に近い明るい青も含める
    glow = in_team * np.maximum(smoothstep(0.5, 0.75, v) * smoothstep(0.3, 0.55, s),
                                smoothstep(0.8, 0.95, v) * smoothstep(0.08, 0.2, s))
    emit = rgb * glow[..., None]
    # 赤: 範囲内の色相を一次で付け替え。彩度の低い所は元の色との間で混ぜる（灰色の石が赤くならない）
    t = (h - TEAM_HUE[0]) / (TEAM_HUE[1] - TEAM_HUE[0])
    h2 = RED_HUE[0] + np.clip(t, 0, 1) * (RED_HUE[1] - RED_HUE[0])
    red = hsv_to_rgb(np.where(in_team, h2, h), s, v)
    w = (in_team * smoothstep(TEAM_MIN_SAT * 0.5, TEAM_MIN_SAT * 1.5, s))[..., None]
    red = rgb * (1 - w) + red * w
    red_emit = red * glow[..., None]
    return emit, red, red_emit, float(glow.mean())


def np_image(name, arr):
    """(h, w, 3) → Blender の画像（RGBA、生の値）。"""
    hgt, wid = arr.shape[:2]
    img = bpy.data.images.new(name, wid, hgt, alpha=False)
    rgba = np.ones((hgt, wid, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(arr, 0, 1)
    img.pixels.foreach_set(rgba.ravel())
    img.update()
    return img


def save_jpeg(arr, path, quality=88):
    img = np_image(os.path.basename(path), arr)
    img.filepath_raw = path
    img.file_format = 'JPEG'
    scene = bpy.context.scene
    scene.render.image_settings.file_format = 'JPEG'
    scene.render.image_settings.quality = quality
    img.save_render(path, scene=scene)
    bpy.data.images.remove(img)


def make_material(obj, sid, base, emit):
    mat = bpy.data.materials.new(f"Struct_{sid}")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tb = nt.nodes.new("ShaderNodeTexImage")
    tb.image = base
    nt.links.new(tb.outputs["Color"], bsdf.inputs["Base Color"])
    te = nt.nodes.new("ShaderNodeTexImage")
    te.image = emit
    nt.links.new(te.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.65
    bsdf.inputs["Metallic"].default_value = 0.0
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.material_index = 0
    return mat


def preview(obj, path):
    """確認用: 正面（USD -Z = Blender +Y）の斜め上からと、ゲームのカメラ（南 = USD +Z から 56° 見下ろし）からの 2 枚。"""
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'TEXTURE'
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("w")
    lo, hi = nc.bbox(nc.world_verts(obj))
    c = (lo + hi) * 0.5
    r = max((hi - lo).length * 0.5, 0.1)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = r * 2.3
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for tag, az, el in [("front", 90.0 + 30.0, 25.0), ("game", -90.0, 56.0)]:
        a, e = math.radians(az), math.radians(el)
        d = Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
        cam.location = c + d * r * 4
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = path.replace(".png", f"_{tag}.png")
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main(a):
    size = json.loads(a.size or "{}")
    origin = a.origin or size.get("origin", "")
    nc.reset_scene()
    nc.import_glb(a.glb)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    if not meshes:
        raise SystemExit("no mesh")
    for m in meshes:
        nc.unparent_keep(m)
        for mod in list(m.modifiers):
            m.modifiers.remove(mod)
        m.vertex_groups.clear()
    nc.delete_except(meshes)
    nc.apply_transforms(meshes)
    obj = nc.join_meshes(meshes)
    obj.name = f"Struct_{a.id}"
    obj.data.name = obj.name
    if obj.data.shape_keys:
        nc.select_only([obj])
        bpy.ops.object.shape_key_remove(all=True, apply_mix=False)
    raw_tris = nc.tri_count(obj)

    yaw = a.yaw if a.yaw is not None else float(size.get("yaw", 0.0))
    if yaw:
        transform(obj, Matrix.Rotation(math.radians(yaw), 4, 'Z'))
    lo, hi = nc.bbox([v.co for v in obj.data.vertices])
    ext = hi - lo
    if "height" in size:
        s = size["height"] / max(ext.z, 1e-6)
    elif "diameter" in size or "length" in size:
        s = size.get("diameter", size.get("length")) / max(ext.x, ext.y, 1e-6)
    else:
        s = 1.0
    transform(obj, Matrix.Diagonal((s, s, s, 1.0)))
    lo, hi = nc.bbox([v.co for v in obj.data.vertices])
    c = (lo + hi) * 0.5
    if origin == "center":
        transform(obj, Matrix.Translation(-c))
    else:
        transform(obj, Matrix.Translation((-c.x, -c.y, -lo.z)))

    if raw_tris > a.faces * 1.05:
        nc.decimate(obj, a.faces)
    # 法線は角度で分割（硬い縁は硬く、曲面は滑らか）
    nc.select_only([obj])
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    except Exception:  # noqa: BLE001
        bpy.ops.object.shade_smooth()

    tex = a.texture or int(size.get("texture", 1024))
    img = base_image(obj)
    if img is None:
        raise SystemExit("no base color image")
    img.colorspace_settings.is_data = False
    if max(img.size) > tex:
        img.scale(tex, tex)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    emit, red, red_emit, glow_frac = team_textures(px)
    base = np_image(f"Struct_{a.id}_base", px[..., :3])
    emit_img = np_image(f"Struct_{a.id}_emit", emit)
    for im in (base, emit_img):
        im.pack()
    make_material(obj, a.id, base, emit_img)
    os.makedirs(a.out, exist_ok=True)
    save_jpeg(red, os.path.join(a.out, f"Struct_{a.id}_red.jpg"))
    save_jpeg(red_emit, os.path.join(a.out, f"Struct_{a.id}_red_emit.jpg"))
    # 確認用（work）: 青のベース・発光・赤のベース
    save_jpeg(px[..., :3], os.path.join(a.work, "tex_blue.jpg"))
    save_jpeg(emit, os.path.join(a.work, "tex_emit.jpg"))
    save_jpeg(red, os.path.join(a.work, "tex_red.jpg"))

    lo, hi = nc.bbox([v.co for v in obj.data.vertices])
    tris = nc.tri_count(obj)
    preview(obj, os.path.join(a.work, "bake.png"))
    out = os.path.join(a.out, f"Struct_{a.id}.usdz")
    textures = nc.export_usdz([obj], out, skinned=False, texture_size=tex)
    report = {"id": a.id, "rawTriangles": raw_tris, "triangles": tris, "vertices": len(obj.data.vertices),
              # USD 空間（Y 上）の寸法 m
              "size": [round(hi.x - lo.x, 3), round(hi.z - lo.z, 3), round(hi.y - lo.y, 3)],
              "origin": origin or "base", "yaw": yaw, "glowFraction": round(glow_frac, 4), "textures": textures,
              "bytes": os.path.getsize(out)}
    with open(os.path.join(a.work, "bake.json"), "w") as f:
        json.dump(report, f, indent=2)
    log(json.dumps(report))


main(parse())
