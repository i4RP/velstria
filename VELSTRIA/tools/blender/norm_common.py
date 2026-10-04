# 担当: hero-assets。normalize_hero.py / normalize_prop.py の共通処理（Blender 5.2 headless）。
# 座標: Blender は Z-up。USD 出力では (x, y, z)_blender -> (x, z, -y)_usd（Y-up、Blender +Y が USD -Z）。
# この変換は Blender の convert_orientation（/root に rotateXYZ(-90,0,0) を付ける）を使わず、
# 書き出し前に頂点・骨へ焼き込む。ルートのノード変換は単位行列のまま。

import json
import math
import os
import re
import shutil
import sys
import tempfile
import zipfile

import bpy
from mathutils import Matrix, Vector

# Blender 空間 -> USD 空間（Y-up）。書き出し直前に全体へ掛ける。
BLENDER_TO_USD = Matrix.Rotation(-math.pi / 2, 4, 'X')


def script_args():
    """'--' 以降の引数。'--forward -x' のような負号付きの値は '--forward=-x' に詰める。"""
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = []
    i = 0
    while i < len(args):
        if args[i].startswith("--") and "=" not in args[i] and i + 1 < len(args) \
                and re.fullmatch(r"-[xyz]", args[i + 1]):
            out.append(f"{args[i]}={args[i + 1]}")
            i += 2
            continue
        out.append(args[i])
        i += 1
    return out


def log(msg):
    print(f"[normalize] {msg}", flush=True)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    """GLB/glTF（または同じリグの FBX）を取り込む。
    glTF は merge_vertices で UV・法線の継ぎ目で分かれた頂点を溶接する（Tripo のメッシュは継ぎ目で ~2000 の島に
    分かれて届き、そのまま Collapse で間引くと継ぎ目が裂ける）。取り込み側の溶接は法線・ウェイトが違う頂点は繋がない。
    FBX は Tripo の GLB のスキンが壊れているとき（骨とメッシュの軸ずれ・全頂点 Hips のダミーウェイト）の代替入力。"""
    if not os.path.isfile(path):
        raise SystemExit(f"input not found: {path}")
    fbx = path.lower().endswith(".fbx")
    if fbx:
        bpy.ops.import_scene.fbx(filepath=path, use_anim=False, ignore_leaf_bones=False,
                                 automatic_bone_orientation=False)
    else:
        bpy.ops.import_scene.gltf(filepath=path, import_pack_images=True, guess_original_bind_pose=True,
                                  merge_vertices=True)
    sanitize_materials(fbx)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    for o in bpy.data.objects:
        o.animation_data_clear()


def sanitize_materials(fbx):
    """取り込み器の癖を直す。
    - 画像のアルファが全画素 1 なのに Alpha へ繋がっている線を外す（FBX 取り込みは基本色画像のアルファを必ず繋ぐ。
      残すと opacity が PNG のアルファを読み、JPEG 化できず同じ画像が 2 枚入る）。
    - FBX: 金属度テクスチャが無いのに Metallic = 1（Tripo の FBX の ReflectionFactor = 1 をそのまま読む）なら 0 に戻す。"""
    import numpy as np
    opaque = {}
    for m in bpy.data.materials:
        if not m.node_tree:
            continue
        nt = m.node_tree
        for link in list(nt.links):
            img = getattr(link.from_node, "image", None)
            if link.from_socket.name != "Alpha" or img is None or link.to_socket.name != "Alpha":
                continue
            if img.name not in opaque:
                ok = img.size[0] > 0 and img.channels == 4
                if ok:
                    px = np.empty(len(img.pixels), dtype=np.float32)
                    img.pixels.foreach_get(px)
                    ok = float(px[3::4].min()) >= 0.999
                else:
                    ok = img.size[0] > 0
                opaque[img.name] = ok
            if opaque[img.name]:
                nt.links.remove(link)
                log(f"material {m.name}: opaque image {img.name} disconnected from Alpha")
        if fbx:
            for n in nt.nodes:
                if n.type == 'BSDF_PRINCIPLED':
                    met = n.inputs.get("Metallic")
                    if met is not None and not met.is_linked and met.default_value > 0.5:
                        met.default_value = 0.0
                        warn(f"material {m.name}: FBX constant Metallic without a texture reset to 0")


def select_only(objs, active=None):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


def unparent_keep(o):
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw


def apply_transforms(objs):
    for o in objs:
        if o.data is not None and o.data.users > 1:
            o.data = o.data.copy()
    select_only(objs)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def delete_except(keep):
    keep_names = {o.name for o in keep}
    for o in list(bpy.data.objects):
        if o.name not in keep_names:
            bpy.data.objects.remove(o, do_unlink=True)


def join_meshes(meshes):
    if len(meshes) == 1:
        return meshes[0]
    select_only(meshes, meshes[0])
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def boundary_edges(obj):
    """開いた辺（面を 1 つしか持たない辺）の数。間引きで継ぎ目が裂けていないかの目安。"""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    n = sum(1 for e in bm.edges if e.is_boundary)
    bm.free()
    return n


def decimate(obj, max_faces):
    """三角形数が max_faces を超えたら Collapse で間引く（UV・頂点グループは補間で保持）。"""
    faces = tri_count(obj)
    if max_faces <= 0 or faces <= max_faces:
        return False
    mod = obj.modifiers.new("Decimate", 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = max_faces / faces
    mod.use_collapse_triangulate = True
    select_only([obj])
    # アーマチュアより先に評価させる（スキン変形前のバインド形状を間引く）
    bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    log(f"decimated {faces} -> {tri_count(obj)} tris")
    return True


def world_verts(obj):
    mw = obj.matrix_world
    return [mw @ v.co for v in obj.data.vertices]


def bbox(points):
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi


def bake_usd_axes(objs):
    """Blender -> USD の軸変換をデータへ焼き込む（親なしのルートにだけ掛けて適用）。"""
    for o in objs:
        if o.parent is None:
            o.matrix_world = BLENDER_TO_USD @ o.matrix_world
    apply_transforms(objs)


def export_usdz(objs, out_path, skinned, texture_size):
    """objs だけを USDZ へ。テクスチャは usdz_downscale で縮小、upAxis/metersPerUnit は pxr で確定する。"""
    from pxr import Sdf, Usd, UsdGeom, UsdUtils

    emission = emission_strengths(objs)
    bake_usd_axes(objs)
    # 片面描画（doubleSided = 0）にする
    for o in objs:
        for m in getattr(o.data, "materials", []):
            if m:
                m.use_backface_culling = True
        # 書き出し側の縮小は 64px 未満を指定できないので、それより小さい指定は先に縮める
        for m in getattr(o.data, "materials", []):
            if not m or not m.node_tree or texture_size >= 64:
                continue
            for n in m.node_tree.nodes:
                img = getattr(n, "image", None)
                if img and max(img.size) > texture_size:
                    w, h = img.size
                    k = texture_size / max(w, h)
                    img.scale(max(1, round(w * k)), max(1, round(h * k)))
                    img.pack()
    select_only(objs)
    tmp = tempfile.mkdtemp(prefix="velstria_usd_")
    raw = os.path.join(tmp, os.path.splitext(os.path.basename(out_path))[0] + ".usdz")
    sizes = {256: '256', 512: '512', 1024: '1024', 2048: '2048', 4096: '4096'}
    down = dict(usdz_downscale_size=sizes[texture_size]) if texture_size in sizes else \
        dict(usdz_downscale_size='CUSTOM', usdz_downscale_custom_size=max(64, texture_size))
    bpy.ops.wm.usd_export(
        filepath=raw,
        selected_objects_only=True,
        export_animation=False,
        export_hair=False,
        export_uvmaps=True,
        rename_uvmaps=True,
        export_mesh_colors=False,
        export_normals=True,
        export_materials=True,
        export_subdivision='IGNORE',
        export_armatures=skinned,
        only_deform_bones=False,
        export_shapekeys=False,
        use_instancing=False,
        evaluation_mode='RENDER',
        generate_preview_surface=True,
        generate_materialx_network=False,
        convert_orientation=False,
        export_textures_mode='NEW',
        overwrite_textures=True,
        relative_paths=True,
        xform_op_mode='TRS',
        root_prim_path="/root",
        export_custom_properties=False,
        author_blender_name=False,
        convert_world_material=False,
        export_lights=False,
        export_cameras=False,
        export_curves=False,
        export_points=False,
        export_volumes=False,
        triangulate_meshes=True,
        merge_parent_xform=False,
        convert_scene_units='METERS',
        **down,
    )
    # 展開して upAxis=Y を付け直し、ARKit 互換 USDZ に再パッケージ
    ex = os.path.join(tmp, "x")
    with zipfile.ZipFile(raw) as z:
        names = z.namelist()
        z.extractall(ex)
    root_layer = next(n for n in names if n.endswith((".usdc", ".usda", ".usd")))
    stage = Usd.Stage.Open(os.path.join(ex, root_layer))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = stage.GetPrimAtPath("/root")
    if root:
        stage.SetDefaultPrim(root)
    if emission:
        left = bake_emission_strength(stage, emission)
        baked = {k: v for k, v in emission.items() if k not in left}
        if baked:
            # RealityKit の PhysicallyBasedMaterial からは inputs:scale が見えない（emissiveIntensity は 1 のまま）
            warn(f"emission strength {baked} written as UsdUVTexture inputs:scale; RealityKit may render it at 1x")
        for name in left:
            warn(f"material {name}: Emission Strength {emission[name]} could not be baked (rendered at 1x)")
    jpeg_opaque_png(stage, os.path.dirname(os.path.join(ex, root_layer)))
    stage.GetRootLayer().Save()
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    if os.path.exists(out_path):
        os.remove(out_path)
    if not UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(os.path.join(ex, root_layer)), out_path):
        raise SystemExit("usdz packaging failed")
    textures = []
    with zipfile.ZipFile(out_path) as z:
        for info in z.infolist():
            if info.filename.lower().endswith((".png", ".jpg", ".jpeg")):
                p = os.path.join(tmp, "probe_" + os.path.basename(info.filename))
                with open(p, "wb") as f:
                    f.write(z.read(info))
                img = bpy.data.images.load(p)
                textures.append({"name": info.filename, "size": list(img.size), "bytes": info.file_size})
                bpy.data.images.remove(img)
    shutil.rmtree(tmp, ignore_errors=True)
    return textures


def jpeg_opaque_png(stage, base_dir, quality=85):
    """アルファを読まない PNG テクスチャを JPEG に置き換える（USDZ を小さくする。Tripo の粗さ・金属マップは
    1024 px で 1.5 MB 前後の PNG のまま届く）。置き換えた PNG は参照されなくなるのでパッケージに入らない。"""
    from pxr import Sdf, UsdShade
    shaders = [UsdShade.Shader(p) for p in stage.Traverse() if p.IsA(UsdShade.Shader)]
    alpha_used = set()
    for sh in shaders:
        for inp in sh.GetInputs():
            for src in inp.GetConnectedSources()[0]:
                if src.sourceName == "a":
                    alpha_used.add(src.source.GetPath())
    for sh in shaders:
        if sh.GetIdAttr().Get() != "UsdUVTexture" or sh.GetPath() in alpha_used:
            continue
        inp = sh.GetInput("file")
        asset = inp.Get() if inp else None
        if not asset or not asset.path.lower().endswith(".png"):
            continue
        src = os.path.normpath(os.path.join(base_dir, asset.path))
        if not os.path.isfile(src):
            continue
        rel = os.path.splitext(asset.path)[0] + ".jpg"
        dst = os.path.normpath(os.path.join(base_dir, rel))
        if not os.path.isfile(dst):
            img = bpy.data.images.load(src)
            img.colorspace_settings.is_data = True   # 色変換せず画素値をそのまま写す
            px = [0.0] * len(img.pixels)
            img.pixels.foreach_get(px)
            img.pixels.foreach_set(px)               # dirty にしないと save() が PNG のバイト列をそのまま写す
            img.file_format = 'JPEG'
            img.save(filepath=dst, quality=quality)
            bpy.data.images.remove(img)
            log(f"jpeg {os.path.basename(src)} {os.path.getsize(src)} -> {os.path.getsize(dst)} bytes")
        if os.path.getsize(dst) >= os.path.getsize(src):
            continue   # 小さな PNG（単色など）は JPEG のほうが大きい
        inp.Set(Sdf.AssetPath(rel))


def emission_strengths(objs):
    """発光色がテクスチャで Emission Strength が 1 以外の素材（USD Preview Surface には強さの入力が無く、
    Blender の書き出しは定数色にしか強さを掛けない）。"""
    out = {}
    for o in objs:
        for m in getattr(o.data, "materials", []):
            if not m or not m.node_tree:
                continue
            for n in m.node_tree.nodes:
                if n.type != 'BSDF_PRINCIPLED':
                    continue
                inp = n.inputs.get("Emission Strength")
                if inp is None or inp.is_linked or abs(inp.default_value - 1.0) < 1e-4:
                    continue
                # 定数色は Blender の書き出しが strength を掛けた emissiveColor を書くので、テクスチャのときだけ
                col = n.inputs.get("Emission Color")
                if col is not None and col.is_linked and inp.default_value > 0:
                    out[m.name] = float(inp.default_value)
    return out


def bake_emission_strength(stage, strengths):
    """Emission Strength を発光テクスチャへ焼き込む。発光専用の UsdUVTexture を複製して inputs:scale に強さを入れる
    （ベースカラーと共用のテクスチャを変えないため）。焼けなかった素材名を返す。"""
    from pxr import Gf, Sdf, Tf, Usd, UsdShade
    by_usd_name = {Tf.MakeValidIdentifier(k): (k, v) for k, v in strengths.items()}
    left = set(strengths)
    for prim in stage.Traverse():
        if not prim.IsA(UsdShade.Material) or prim.GetName() not in by_usd_name:
            continue
        name, k = by_usd_name[prim.GetName()]
        for p in Usd.PrimRange(prim):
            if not p.IsA(UsdShade.Shader):
                continue
            sh = UsdShade.Shader(p)
            if sh.GetIdAttr().Get() != "UsdPreviewSurface":
                continue
            em = sh.GetInput("emissiveColor")
            if not em:
                continue
            srcs = em.GetConnectedSources()[0]
            if not srcs:
                continue
            src = srcs[0]
            tex = UsdShade.Shader(src.source.GetPrim())
            if tex.GetIdAttr().Get() != "UsdUVTexture":
                continue
            dup_path = tex.GetPath().GetParentPath().AppendChild(tex.GetPath().name + "_emissive")
            if not stage.GetPrimAtPath(dup_path):
                Sdf.CopySpec(stage.GetRootLayer(), tex.GetPath(), stage.GetRootLayer(), dup_path)
            dup = UsdShade.Shader(stage.GetPrimAtPath(dup_path))
            dup.CreateInput("scale", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(k, k, k, 1.0))
            em.ConnectToSource(dup.ConnectableAPI(), src.sourceName)
            left.discard(name)
    return sorted(left)


WARNINGS = []


def warn(msg):
    """レポートの warnings に積む（tools/tripo.mjs の取り込みが表示する）。"""
    log("WARNING: " + msg)
    WARNINGS.append(msg)


def write_report(report, path):
    report["warnings"] = list(WARNINGS)
    text = json.dumps(report, ensure_ascii=False)
    if path:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "w") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
    print(text, flush=True)


def canonical_bone(name):
    """'mixamorig:LeftToeBase' / 'mixamorig_LeftToeBase' / 'LeftToeBase' -> 'lefttoebase'。"""
    n = re.sub(r'^.*mixamorig\d*[:_]?', '', name, flags=re.I)
    return re.sub(r'[:_\s.]', '', n).lower()


# 実行時（App/Battle/Heroes/HeroSkeletonRig.swift の HeroJointRole.required）が欠けると手続きモデルへ戻す骨。
RUNTIME_REQUIRED = ("hips", "spine", "head", "leftarm", "leftforearm", "lefthand", "rightarm", "rightforearm",
                    "righthand", "leftupleg", "leftleg", "rightupleg", "rightleg")


def runtime_role(joint_path):
    """HeroJointRole.normalize と同じ規則: パスの末尾・小文字化・先頭の 'mixamorig' + 数字 + ':' / '_' を 1 回だけ外す。
    canonical_bone より厳しい（'Left_Arm' は 'left_arm' のままで leftarm に当たらない）。"""
    parts = [p for p in joint_path.split("/") if p]
    s = (parts[-1] if parts else joint_path).lower()
    if s.startswith("mixamorig"):
        s = s[len("mixamorig"):]
        while s and s[0].isnumeric():
            s = s[1:]
        if s and s[0] in ":_":
            s = s[1:]
    return s


# Meshy の自動リグ（tools/meshy.mjs）の骨名 → Mixamo 名。Meshy は背骨が腰側から Spine02 → Spine01 → Spine の順で、
# 肩と首の親の「Spine」は胸（Mixamo の Spine2）を指す。Mixamo の Spine（腰側）と同じ綴りなので、骨 1 本ごとの別名表
# （実行時の HeroJointRole.normalize）では区別できない → 骨格全体を見て Meshy 方言と判定したときだけ取り込み時に付け替える。
# キーは runtime_role の値。neck は大文字小文字違いだけ、head_end は Mixamo の HeadTop_End（verify_usdz の頭頂の検査に使う）。
MESHY_TO_MIXAMO = {"spine02": "Spine", "spine01": "Spine1", "spine": "Spine2", "neck": "Neck", "head_end": "HeadTop_End"}


def is_meshy_rig(bone_names):
    """Spine01 と Spine02 があり Spine1 / Spine2 が無い骨格（Meshy 方言）。"""
    roles = {runtime_role(n) for n in bone_names}
    return {"spine01", "spine02"} <= roles and not roles & {"spine1", "spine2"}


def rename_meshy_bones(arm):
    """Meshy 方言の骨を Mixamo 名へ付け替える（スキンの頂点グループは Blender が骨の改名に合わせて付け替える）。
    {旧名: 新名}。Meshy 方言でなければ何もしない。Spine → Spine2 と Spine02 → Spine が衝突しないよう一時名を経由する。"""
    if not is_meshy_rig([b.name for b in arm.data.bones]):
        return {}
    plan = {b.name: MESHY_TO_MIXAMO[runtime_role(b.name)] for b in arm.data.bones if runtime_role(b.name) in MESHY_TO_MIXAMO}
    plan = {k: v for k, v in plan.items() if k != v}
    for i, old in enumerate(plan):
        arm.data.bones[old].name = f"__meshy_tmp_{i}"
    for i, new in enumerate(plan.values()):
        arm.data.bones[f"__meshy_tmp_{i}"].name = new
    return plan


def usd_safe_name(name):
    """Blender の USD 書き出しが骨名に掛ける置換の近似（英数字と '_' 以外は '_'、数字始まりは '_' を前置）。"""
    s = re.sub(r"[^A-Za-z0-9_]", "_", name) or "_"
    return "_" + s if s[0].isdigit() else s


def missing_runtime_joints(joint_paths):
    """実行時の規則で見つからない必須の骨（RUNTIME_REQUIRED の順）。"""
    found = {runtime_role(p) for p in joint_paths}
    return [r for r in RUNTIME_REQUIRED if r not in found]


def usd_skeleton_joints(usdz):
    """書き出した USDZ の UsdSkel の joints（RealityKit がそのまま jointNames にする）。Skeleton ごとの配列。"""
    from pxr import Usd, UsdSkel
    st = Usd.Stage.Open(usdz)
    return [list(UsdSkel.Skeleton(p).GetJointsAttr().Get() or []) for p in st.Traverse() if p.IsA(UsdSkel.Skeleton)]
