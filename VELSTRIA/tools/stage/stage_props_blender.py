# ステージ小物の Blender 側の処理（Blender 5.2 headless）。tools/stage/stage_bake.py から呼ぶ。
#
#   Blender -b --factory-startup --python-exit-code 1 --python tools/stage/stage_props_blender.py -- \
#       bake --glb build/stage/meshy/boulder/model.glb --tris 1200 --out build/stage/props/boulder.npz
#   Blender -b --factory-startup --python-exit-code 1 --python tools/stage/stage_props_blender.py -- \
#       render --bin App/Resources/Stage/StageProps.bin --atlas App/Resources/Stage/StagePropsAtlas.jpg \
#       --outdir build/stage/preview/props
#
# bake: GLB を取り込み → 結合・変換の適用 → 位置で溶接（UV は角ごとのデータとして残る）→ Collapse で減面
#       （UV の継ぎ目の頂点は頂点グループの重みで潰れにくくする）→ 三角形化 → 角度 60° で鋭い辺を付けて角の法線。
#       結果は Blender の座標（Z-up）のまま角ごとの配列で npz に書く。軸の変換・向き・寸法・原点・アトラスの UV は
#       stage_bake.py（numpy）がやる。
# render: 焼いた StageProps.bin とアトラスを読み戻して（GLB は使わない）56° 見下ろしで描く。バイナリの検証用。
#
# norm_common.py（tools/blender/）の書き方に倣うが import はしない（ワークツリーごとに独立して動くように）。

import json
import math
import os
import struct
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector


def log(msg):
    print(f"[stage_props] {msg}", flush=True)


def script_args():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args:
        raise SystemExit("usage: -- bake|render [options]")
    cmd, rest, opts = args[0], args[1:], {}
    i = 0
    while i < len(rest):
        if not rest[i].startswith("--"):
            raise SystemExit(f"unexpected argument: {rest[i]}")
        opts[rest[i][2:]] = rest[i + 1]
        i += 2
    return cmd, opts


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def select_only(objs, active=None):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


# ---------------------------------------------------------------- bake

def import_glb(path):
    """GLB を取り込み、メッシュを 1 つにまとめて変換を頂点へ焼き込む（glTF 取り込みは Y-up → Z-up を頂点に適用済み）。"""
    if not os.path.isfile(path):
        raise SystemExit(f"input not found: {path}")
    bpy.ops.import_scene.gltf(filepath=path, merge_vertices=True)
    for o in bpy.data.objects:
        o.animation_data_clear()
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    if not meshes:
        raise SystemExit(f"no mesh in {path}")
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        if o.data.users > 1:
            o.data = o.data.copy()
    for o in list(bpy.data.objects):
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    select_only(meshes)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        select_only(meshes, meshes[0])
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    if len(obj.data.uv_layers) == 0:
        raise SystemExit("mesh has no UV layer")
    # 2 枚目以降の UV は使わない
    while len(obj.data.uv_layers) > 1:
        obj.data.uv_layers.remove(obj.data.uv_layers[-1])
    # glTF の法線は custom_normal（角ごと）として入る。減面すると補間で壊れるので捨て、形から計算し直す。
    # 取り込み時の鋭い辺の印も捨てる（あとで角度から付け直す）
    me = obj.data
    for name in ("custom_normal", "sharp_edge", "sharp_face"):
        a = me.attributes.get(name)
        if a is not None:
            me.attributes.remove(a)
    if me.has_custom_normals:
        raise SystemExit("custom normals could not be cleared")
    return obj


def uv_seam_edges(bm, uvl):
    """両側で UV が食い違う辺（溶接後の UV の継ぎ目）。"""
    out = []
    for e in bm.edges:
        if len(e.link_loops) != 2:
            continue
        l1, l2 = e.link_loops
        # l1 は e.v1→e.v2 か e.v2→e.v1。同じ頂点の角どうしを比べる
        a1, b1 = l1[uvl].uv, l1.link_loop_next[uvl].uv
        if l2.vert == l1.vert:
            a2, b2 = l2[uvl].uv, l2.link_loop_next[uvl].uv
        else:
            a2, b2 = l2.link_loop_next[uvl].uv, l2[uvl].uv
        if (a1 - a2).length > 1e-6 or (b1 - b2).length > 1e-6:
            out.append(e)
    return out


def weld_and_mark(obj, seam_weight):
    """位置の同じ頂点を溶接し（Meshy の GLB は UV の島ごとに頂点が分かれて届く）、UV の継ぎ目に印を付ける。
    継ぎ目の頂点は頂点グループ uv_keep の重みを seam_weight（< 1）にして Collapse で潰れにくくする
    （Collapse には UV の delimit が効かないので、その代わり）。統計を返す。"""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
    diag = (hi - lo).length
    v0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=diag * 1e-6)
    bmesh.ops.dissolve_degenerate(bm, dist=diag * 1e-7, edges=bm.edges)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    # 3 枚以上の面が付く辺（Meshy のリメッシュで薄い所・葉が触れ合う所にできる）は切り離して境界にする。
    # 残すと Collapse がその周りを一切潰せず、目標の三角形数まで減らない
    nonmanifold = [e for e in bm.edges if len(e.link_faces) > 2]
    if nonmanifold:
        bmesh.ops.split_edges(bm, edges=nonmanifold)
    uvl = bm.loops.layers.uv[0]
    seams = uv_seam_edges(bm, uvl)
    for e in bm.edges:
        e.seam = False
    for e in seams:
        e.seam = True
    bm.verts.index_update()
    seam_verts = {v.index for e in seams for v in e.verts}
    stats = {
        "glbVerts": v0,
        "weldedVerts": len(bm.verts),
        "weldedBoundaryEdges": sum(1 for e in bm.edges if e.is_boundary),
        "splitNonManifoldEdges": len(nonmanifold),
        "uvSeamEdges": len(seams),
        "edges": len(bm.edges),
        "seamVertFraction": round(len(seam_verts) / max(1, len(bm.verts)), 3),
    }
    bm.to_mesh(me)
    bm.free()
    me.update()
    vg = obj.vertex_groups.new(name="uv_keep")
    vg.add([i for i in range(len(me.vertices)) if i not in seam_verts], 1.0, 'REPLACE')
    if seam_verts:
        vg.add(sorted(seam_verts), seam_weight, 'REPLACE')
    return stats


def decimate_to(obj, target, seam_factor):
    """Collapse で target 三角形へ。結果が ±3% に入るまで比率を直して数回やり直す（元のメッシュから毎回）。"""
    src = obj.data.copy()
    faces0 = sum(len(p.vertices) - 2 for p in src.polygons)
    if faces0 <= target:
        return faces0
    ratio = target / faces0
    best = None
    for attempt in range(6):
        if attempt:
            old = obj.data
            obj.data = src.copy()
            bpy.data.meshes.remove(old)
        mod = obj.modifiers.new("Decimate", 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = min(1.0, ratio)
        mod.use_collapse_triangulate = True
        mod.delimit = {'UV'}   # Collapse では効かない（Planar 用）。継ぎ目は頂点グループの重みで守る
        if seam_factor > 0:
            mod.vertex_group = "uv_keep"
            mod.vertex_group_factor = seam_factor
        select_only([obj])
        bpy.ops.object.modifier_apply(modifier=mod.name)
        got = tri_count(obj)
        log(f"decimate ratio {ratio:.4f}: {faces0} -> {got} tris (target {target})")
        if best is None or abs(got - target) < abs(best[1] - target):
            best = (ratio, got)
        if abs(got - target) <= 0.03 * target:
            break
        ratio *= target / max(1, got)
    if abs(tri_count(obj) - target) > abs(best[1] - target):
        old = obj.data
        obj.data = src.copy()
        bpy.data.meshes.remove(old)
        mod = obj.modifiers.new("Decimate", 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = best[0]
        mod.use_collapse_triangulate = True
        if seam_factor > 0:
            mod.vertex_group = "uv_keep"
            mod.vertex_group_factor = seam_factor
        select_only([obj])
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.meshes.remove(src)
    return faces0


def cleanup_triangulate(obj):
    """減面後の潰れた面を消して三角形だけにする。"""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
    diag = (hi - lo).length
    bmesh.ops.dissolve_degenerate(bm, dist=diag * 1e-7, edges=bm.edges)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    boundary = sum(1 for e in bm.edges if e.is_boundary)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return boundary


def duplicate(obj, name):
    dup = obj.copy()
    dup.data = obj.data.copy()
    dup.name = name
    bpy.context.scene.collection.objects.link(dup)
    return dup


def bbox_diag(obj):
    co = np.empty(len(obj.data.vertices) * 3, np.float32)
    obj.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    return float(np.linalg.norm(co.max(axis=0) - co.min(axis=0)))


def voxel_remesh(obj, fraction):
    """葉の集まり（薄い板が離れて並ぶ茂み）を 1 つの閉じた塊にする。ボクセルの大きさ = 外接箱の対角 × fraction。
    減面で葉が三角形の破片になるのを避ける（色は元の葉から焼き付けるので、葉の模様は塊の表面に残る）。"""
    obj.data.remesh_voxel_size = bbox_diag(obj) * fraction
    obj.data.remesh_voxel_adaptivity = 0.0
    select_only([obj])
    bpy.ops.object.voxel_remesh()
    log(f"voxel remesh ({fraction} of diag): {tri_count(obj)} faces")


def smart_uv(obj, margin):
    """減面後のメッシュに新しい UV（Smart UV Project: 角度 66° で島に分けて [0,1] に詰める）。"""
    me = obj.data
    # Meshy の UV の継ぎ目の印（weld_and_mark が付けた）を消す。残すと Smart UV Project がそこでも島を切り、
    # ほぼ三角形ごとの小島になる
    seam = np.zeros(len(me.edges), bool)
    me.edges.foreach_set("use_seam", seam)
    while len(me.uv_layers):
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="UVMap")
    select_only([obj])
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=margin, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    shrunk = shrink_hidden_islands(obj)
    if shrunk:
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.select_all(action='SELECT')
        bpy.ops.uv.pack_islands(rotate=True, scale=True, margin_method='FRACTION', margin=margin,
                                shape_method='CONCAVE')
        bpy.ops.object.mode_set(mode='OBJECT')
    return shrunk


def shrink_hidden_islands(obj, factor=0.15):
    """地面に接する底面（下向き・最も低い所から高さの 6% 以内）だけでできた UV の島を factor 倍に縮める。
    56° 見下ろしのカメラからは見えない面なので、テクスチャの面積を見える面へ回す（このあと詰め直す）。縮めた島の数。"""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv[0]
    zs = [v.co.z for v in bm.verts]
    zmin, height = min(zs), max(zs) - min(zs)
    bm.faces.ensure_lookup_table()
    seams = {e.index for e in uv_seam_edges(bm, uvl)}
    seen, shrunk = set(), 0
    for f in bm.faces:
        if f.index in seen:
            continue
        island, stack = [], [f]
        seen.add(f.index)
        while stack:
            g = stack.pop()
            island.append(g)
            for e in g.edges:
                if e.index in seams:
                    continue
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        hidden = sum(g.calc_area() for g in island
                     if g.normal.z < -0.6 and max(v.co.z for v in g.verts) < zmin + 0.06 * height)
        total = sum(g.calc_area() for g in island)
        if total <= 0 or hidden < 0.9 * total:
            continue
        loops = [l for g in island for l in g.loops]
        c = sum((l[uvl].uv for l in loops), Vector((0.0, 0.0))) / len(loops)
        for l in loops:
            l[uvl].uv = c + (l[uvl].uv - c) * factor
        shrunk += 1
    bm.to_mesh(me)
    bm.free()
    me.update()
    return shrunk


def bake_base_color(high, low, base_color, out_png, size, margin_px):
    """元のメッシュ（Meshy の UV + base_color.png）の色を、減面したメッシュの新しい UV へ焼き付ける。
    元の材質を「base_color をそのまま発光」に差し替えて Cycles の EMIT で焼くので、照明・金属度の影響は入らない。"""
    img_src = bpy.data.images.load(base_color)
    emit = bpy.data.materials.new("bake_src")
    emit.use_nodes = True
    nt = emit.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img_src
    tex.interpolation = 'Cubic'
    em = nt.nodes.new("ShaderNodeEmission")
    outn = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], outn.inputs["Surface"])
    high.data.materials.clear()
    high.data.materials.append(emit)

    target = bpy.data.images.new("bake_target", size, size, alpha=False, float_buffer=False)
    target.generated_color = (1.0, 0.0, 1.0, 1.0)   # 焼かれなかった画素の印（stage_bake.py が埋める）
    dst = bpy.data.materials.new("bake_dst")
    dst.use_nodes = True
    nt = dst.node_tree
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = target
    nt.nodes.active = node
    low.data.materials.clear()
    low.data.materials.append(dst)

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 4
    scene.view_settings.view_transform = 'Standard'
    bk = scene.render.bake
    diag = bbox_diag(high)
    bk.use_selected_to_active = True
    bk.cage_extrusion = diag * 0.03
    bk.max_ray_distance = diag * 0.08
    bk.margin = margin_px
    bk.margin_type = 'EXTEND'
    bk.target = 'IMAGE_TEXTURES'
    bk.use_clear = False   # 新しい画像なので消す必要はない（消すと黒になり、印の色が残らない）
    select_only([high, low], active=low)
    bpy.ops.object.bake(type='EMIT')
    target.filepath_raw = out_png
    target.file_format = 'PNG'
    target.save()
    log(f"baked base color -> {out_png}")


def bake(opts):
    """mode=rebake（既定）: 形だけで減面 → 新しい UV → 元の色を焼き付け（--bake-out の PNG）。
    mode=meshy: Meshy の UV のまま減面（継ぎ目の頂点を重みで守る）。Meshy の UV は数千の小島に分かれていて、
    1/5〜1/10 に減らすと 1 つの三角形が複数の島にまたがり色が崩れる（STAGE.md 3.3 の字義どおりの比較用）。"""
    glb, out, target = opts["glb"], opts["out"], int(opts["tris"])
    mode = opts.get("mode", "rebake")
    angle = math.radians(float(opts.get("angle", "60")))
    seam_weight = float(opts.get("seam-weight", "0.35"))
    seam_factor = float(opts.get("seam-factor", "1.0"))
    remesh = float(opts.get("remesh", "0"))
    reset_scene()
    high = import_glb(glb)
    stats = {"mode": mode, "glbTris": tri_count(high)}
    obj = duplicate(high, "low") if mode == "rebake" else high
    stats.update(weld_and_mark(obj, seam_weight if mode == "meshy" else 1.0))
    if remesh > 0:
        if mode != "rebake":
            raise SystemExit("--remesh needs --mode rebake")
        voxel_remesh(obj, remesh)
        stats["remeshFaces"] = tri_count(obj)
    decimate_to(obj, target, seam_factor if mode == "meshy" else 0.0)
    stats["decimatedBoundaryEdges"] = cleanup_triangulate(obj)
    if mode == "rebake":
        size = int(opts.get("bake-size", "1024"))
        stats["hiddenIslandsShrunk"] = smart_uv(obj, margin=float(opts.get("uv-margin", "0.006")))
        bake_base_color(high, obj, opts["base-color"], opts["bake-out"], size, int(opts.get("bake-margin", "16")))
    me = obj.data
    # 滑らかな法線 + 角度で鋭い辺（Blender 4.1+ の API。自動スムーズは廃止された）
    me.shade_smooth()
    me.set_sharp_from_angle(angle=angle)
    me.calc_loop_triangles()
    nv, nl, nt = len(me.vertices), len(me.loops), len(me.loop_triangles)
    co = np.empty(nv * 3, np.float32)
    me.vertices.foreach_get("co", co)
    cn = np.empty(nl * 3, np.float32)
    me.corner_normals.foreach_get("vector", cn)
    uv = np.empty(nl * 2, np.float32)
    me.uv_layers[0].data.foreach_get("uv", uv)
    lv = np.empty(nl, np.int32)
    me.loops.foreach_get("vertex_index", lv)
    tl = np.empty(nt * 3, np.int32)
    me.loop_triangles.foreach_get("loops", tl)
    stats["tris"] = nt
    stats["verts"] = nv
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    tmp = out + ".tmp.npz"
    np.savez(tmp, co=co.reshape(-1, 3), corner_normal=cn.reshape(-1, 3), corner_uv=uv.reshape(-1, 2),
             corner_vert=lv, tri_loops=tl.reshape(-1, 3), stats=np.array(json.dumps(stats)))
    os.replace(tmp, out)
    log("STATS " + json.dumps(stats))


# ---------------------------------------------------------------- render

def read_props_bin(path):
    """StageProps.bin を読む（docs/STAGE.md 3.3）。[(record, vertices(N,8), indices(M,))]"""
    with open(path, "rb") as f:
        blob = f.read()
    if blob[:4] != b"VSP1":
        raise SystemExit("bad magic")
    version, jlen = struct.unpack_from("<II", blob, 4)
    if version != 1:
        raise SystemExit(f"bad version {version}")
    header = json.loads(blob[12:12 + jlen].decode("utf-8"))
    base = (12 + jlen + 15) // 16 * 16
    out = []
    for p in header["props"]:
        v = np.frombuffer(blob, np.float32, p["vertexCount"] * 8, base + p["vertexOffset"]).reshape(-1, 8)
        i = np.frombuffer(blob, np.uint32, p["indexCount"], base + p["indexOffset"])
        out.append((p, v, i))
    return header, out


def rk_to_blender(a):
    """RealityKit（Y-up）→ Blender（Z-up）: (x, y, z) → (x, -z, y)。行列式 +1 なので巻き順は変わらない。"""
    return np.stack([a[:, 0], -a[:, 2], a[:, 1]], axis=1)


def make_prop_object(rec, verts, idx, atlas_img):
    pos = rk_to_blender(verts[:, 0:3])
    nrm = rk_to_blender(verts[:, 3:6])
    uv = verts[:, 6:8]          # RealityKit の v（下端 = 0）は Blender の UV と同じ向き
    tris = idx.reshape(-1, 3)
    me = bpy.data.meshes.new(rec["id"])
    me.vertices.add(len(pos))
    me.vertices.foreach_set("co", pos.astype(np.float32).ravel())
    me.loops.add(len(idx))
    me.loops.foreach_set("vertex_index", idx.astype(np.int32))
    me.polygons.add(len(tris))
    me.polygons.foreach_set("loop_start", (np.arange(len(tris)) * 3).astype(np.int32))
    me.update(calc_edges=True)
    me.validate(clean_customdata=False)
    uvl = me.uv_layers.new(name="UVMap")
    uvl.data.foreach_set("uv", uv[idx].astype(np.float32).ravel())
    me.shade_smooth()
    me.normals_split_custom_set_from_vertices([tuple(n) for n in nrm])
    mat = bpy.data.materials.get("StagePropsAtlas")
    if mat is None:
        mat = bpy.data.materials.new("StagePropsAtlas")
        mat.use_nodes = True
        mat.use_backface_culling = True   # 巻き順が逆なら穴として見える
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
        bsdf.inputs["Roughness"].default_value = 0.8
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = atlas_img
        tex.interpolation = 'Linear'
        tex.extension = 'EXTEND'
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)
    obj = bpy.data.objects.new(rec["id"], me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def make_ground(size):
    """1 m 格子の地面（寸法の目安）。"""
    img = bpy.data.images.new("checker", 2, 2)
    img.pixels.foreach_set(np.array([0.36, 0.40, 0.34, 1, 0.30, 0.34, 0.28, 1,
                                     0.30, 0.34, 0.28, 1, 0.36, 0.40, 0.34, 1], np.float32))
    img.pack()
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, -0.002))
    g = bpy.context.active_object
    uvd = g.data.uv_layers[0].data
    for l in uvd:
        l.uv = (l.uv[0] * size / 2, l.uv[1] * size / 2)
    mat = bpy.data.materials.new("ground")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    g.data.materials.append(mat)
    return g


def setup_render(scene, res, engine):
    """eevee: 太陽光（56° 上から、暖色）+ 空の環境光、色はそのまま（Standard）。workbench: テクスチャ色・スタジオ照明。
    どちらも背面カリング（材質の use_backface_culling / シェーディングの設定）なので、巻き順の誤りは穴として見える。"""
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new("w")
    scene.world = world
    if engine == "eevee":
        scene.render.engine = 'BLENDER_EEVEE'
        world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        bg.inputs["Color"].default_value = (0.55, 0.62, 0.72, 1.0)
        bg.inputs["Strength"].default_value = 0.9
        sun_data = bpy.data.lights.new("sun", 'SUN')
        sun_data.energy = 3.2
        sun_data.color = (1.0, 0.95, 0.86)
        sun_data.angle = math.radians(8)
        sun = bpy.data.objects.new("sun", sun_data)
        sun.rotation_euler = (math.radians(34), 0.0, math.radians(-35))
        scene.collection.objects.link(sun)
    else:
        scene.render.engine = 'BLENDER_WORKBENCH'
        sh = scene.display.shading
        sh.light = 'STUDIO'
        sh.color_type = 'TEXTURE'
        sh.show_backface_culling = True
        sh.show_cavity = False
        sh.show_shadows = True
        scene.display.shadow_focus = 0.9
        scene.display.light_direction = (0.35, -0.45, 0.82)
        world.color = (0.55, 0.62, 0.70)


def render(opts):
    path_bin, path_atlas, outdir = opts["bin"], opts["atlas"], opts["outdir"]
    res = int(opts.get("res", "512"))
    views = [float(a) for a in opts.get("azimuths", "25,205").split(",")]
    engine = opts.get("engine", "eevee")
    reset_scene()
    scene = bpy.context.scene
    setup_render(scene, res, engine)
    atlas = bpy.data.images.load(path_atlas)
    header, props = read_props_bin(path_bin)
    os.makedirs(outdir, exist_ok=True)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.sensor_fit = 'VERTICAL'
    cam_data.angle_y = math.radians(48)
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    report = []
    for rec, verts, idx in props:
        for o in list(scene.objects):
            if o.type == 'MESH':
                bpy.data.objects.remove(o, do_unlink=True)
        make_prop_object(rec, verts, idx, atlas)
        bmin = np.array(rec["boundsMin"], np.float64)
        bmax = np.array(rec["boundsMax"], np.float64)
        make_ground(max(4.0, math.ceil(float(max(bmax[0] - bmin[0], bmax[2] - bmin[2])) + 2.0)))
        c_rk = (bmin + bmax) / 2
        center = Vector((c_rk[0], -c_rk[2], c_rk[1]))
        radius = float(np.linalg.norm(bmax - bmin)) / 2
        dist = radius / math.sin(math.radians(48) / 2) * 1.05
        for k, az in enumerate(views):
            cam.rotation_euler = (math.radians(90 - 56), 0.0, math.radians(az))
            fwd = cam.rotation_euler.to_matrix() @ Vector((0, 0, -1))
            cam.location = center - fwd * dist
            scene.render.filepath = os.path.join(outdir, f"{rec['id']}_v{k}.png")
            try:
                bpy.ops.render.render(write_still=True)
            except RuntimeError as e:
                if engine == "workbench":
                    raise
                log(f"EEVEE failed ({e}); falling back to Workbench")
                engine = "workbench"
                setup_render(scene, res, engine)
                bpy.ops.render.render(write_still=True)
        report.append({"id": rec["id"], "tris": int(len(idx) // 3), "verts": int(len(verts))})
        log(f"rendered {rec['id']}")
    log(f"RENDERED ({engine}) " + json.dumps(report))


def main():
    cmd, opts = script_args()
    if cmd == "bake":
        bake(opts)
    elif cmd == "render":
        render(opts)
    else:
        raise SystemExit(f"unknown command {cmd}")


main()
