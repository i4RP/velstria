# 担当: hero-assets。Tripo 風の合成リグ（Mixamo 骨名・T ポーズ・glTF +X 前向き）と合成剣を作り、
# normalize_hero.py / normalize_prop.py に通して検証用 USDZ を作る。
# 使い方: Blender -b --factory-startup --python-exit-code 1 --python make_test_rig.py [-- --update-fixture] [-- --variants [名前...]]
# 出力: build/tripo/test/{rigged.glb, sword_*.glb, SkinnedTestHero.usdz, Prop_test*.usdz, *.json}
#       --update-fixture のときだけ AppTests/Fixtures/SkinnedTestHero.usdz（テクスチャ 64px）を書き換える。
#       （SkinnedTestHero_MissingJoint.usdz は別途手で作ったもの。骨名・構造を変えるときは両方を作り直す）
# わざと崩した条件: 身長 2.3・足元 0.3・腰の水平位置ずれ・scale 0.01 のルート（骨とメッシュは cm 値）・カメラ/ライト/空の混入。
# --variants: Tripo / Meshy で起きうる崩れ（骨名の接頭辞・Meshy の骨名・A ポーズ・前向き・骨とメッシュの食い違い・ダミーのスキン・発光の強さ・
#   左右の入れ替わり・必須の骨の欠け・実行時に当たらない骨名・Prop の正面/符号/盾の向き/長軸）を合成して normalize_*.py と
#   verify_usdz.swift に通し、期待どおりか PASS/FAIL の表を出す。BAD_* は正規化か検査で弾かれるのが期待。
#   出力は build/tripo/test/variants/（GLB は tools/tripo.mjs の取り込みの試験入力にも使える）。1 つでも期待と違えば終了コード 1。
# verify_usdz.swift は swiftc で build/tripo/verify_usdz（TRIPO_BUILD_DIR があればその下）へ 1 度だけコンパイルして使う。

import json
import math
import os
import re
import shutil
import subprocess
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(APP, "build", "tripo", "test")
FIXTURE = os.path.join(APP, "AppTests", "Fixtures", "SkinnedTestHero.usdz")

# キャラクター座標（右 s, 前 f, 上 u; 身長 1.7 m の人型）-> Blender 空間。
# glTF +X 前向き = Blender +X、右手側は glTF +Z = Blender -Y。
FWD = Vector((1, 0, 0))
RIGHT = Vector((0, -1, 0))
UP = Vector((0, 0, 1))
K = 2.3 / 1.7                     # 身長 2.3 に拡大
OFFSET = Vector((0.15, -0.2, 0.3))  # 腰の水平ずれ・足元 0.3
CM = 100.0                         # ルート scale 0.01 の下で cm 値


def P(s, f, u):
    w = (RIGHT * s + FWD * f + UP * u) * K + OFFSET
    return w * CM


PREFIX = "mixamorig:"
# 変種の設定（build_hero が読む）。prefix, fwd, root_bone, apose, no_toes, two_mats, emission, arm_scale,
# dummy_skin, skel_xform（骨だけに掛ける Blender 空間の行列）, dense（細分化してスムーズ）,
# mirror（Left/Right の名前を入れ替える = 鏡像のリグ）, one_toe（右のつま先の骨を除く）,
# drop_bones（骨を除き、子と部位は親へ付け替える）, rename（骨名（接頭辞の後）に掛ける関数）
CFG = {}
# 名前: (親, head(s,f,u), tail)
BONES = {}


def bone(name, parent, head, tail):
    BONES[name] = (parent, head, tail)


def build_bone_table():
    bone("Hips", None, (0, 0, 0.95), (0, 0, 1.05))
    bone("Spine", "Hips", (0, 0, 1.05), (0, 0, 1.17))
    bone("Spine1", "Spine", (0, 0, 1.17), (0, 0, 1.30))
    bone("Spine2", "Spine1", (0, 0, 1.30), (0, 0, 1.45))
    bone("Neck", "Spine2", (0, 0, 1.45), (0, 0, 1.53))
    bone("Head", "Neck", (0, 0, 1.53), (0, 0, 1.70))
    bone("HeadTop_End", "Head", (0, 0, 1.70), (0, 0, 1.76))
    for side, sg in (("Left", -1), ("Right", 1)):
        bone(side + "Shoulder", "Spine2", (sg * 0.04, 0, 1.40), (sg * 0.17, 0, 1.40))
        bone(side + "Arm", side + "Shoulder", (sg * 0.17, 0, 1.40), (sg * 0.45, 0, 1.40))
        bone(side + "ForeArm", side + "Arm", (sg * 0.45, 0, 1.40), (sg * 0.70, 0, 1.40))
        bone(side + "Hand", side + "ForeArm", (sg * 0.70, 0, 1.40), (sg * 0.80, 0, 1.40))
        bone(side + "HandIndex1", side + "Hand", (sg * 0.80, 0, 1.40), (sg * 0.86, 0, 1.40))
        bone(side + "UpLeg", "Hips", (sg * 0.09, 0, 0.92), (sg * 0.09, 0, 0.50))
        bone(side + "Leg", side + "UpLeg", (sg * 0.09, 0, 0.50), (sg * 0.09, 0, 0.08))
        bone(side + "Foot", side + "Leg", (sg * 0.09, 0, 0.08), (sg * 0.09, 0.12, 0.02))
        bone(side + "ToeBase", side + "Foot", (sg * 0.09, 0.12, 0.02), (sg * 0.09, 0.20, 0.02))
        bone(side + "Toe_End", side + "ToeBase", (sg * 0.09, 0.20, 0.02), (sg * 0.09, 0.24, 0.02))


# 部位: (骨, a, b, 幅(横), 厚み, 頭側リングを親骨と 0.5 ずつ混ぜるか, UV セル)
PARTS = []


def part(b, a, c, w, d, blend=False):
    PARTS.append((b, a, c, w, d, blend))


def build_parts():
    part("Hips", (0, 0, 0.88), (0, 0, 1.05), 0.32, 0.20)
    part("Spine", (0, 0, 1.05), (0, 0, 1.17), 0.30, 0.18)
    part("Spine1", (0, 0, 1.17), (0, 0, 1.30), 0.32, 0.19)
    part("Spine2", (0, 0, 1.30), (0, 0, 1.45), 0.36, 0.22)
    part("Neck", (0, 0, 1.45), (0, 0, 1.53), 0.10, 0.10)
    part("Head", (0, 0, 1.53), (0, 0, 1.70), 0.20, 0.22)
    part("Head", (0, 0.11, 1.58), (0, 0.15, 1.58), 0.04, 0.04)  # 鼻（顔の前面）
    for side, sg in (("Left", -1), ("Right", 1)):
        part(side + "Shoulder", (sg * 0.04, 0, 1.40), (sg * 0.17, 0, 1.40), 0.10, 0.10)
        part(side + "Arm", (sg * 0.17, 0, 1.40), (sg * 0.45, 0, 1.40), 0.09, 0.09, True)
        part(side + "ForeArm", (sg * 0.45, 0, 1.40), (sg * 0.70, 0, 1.40), 0.08, 0.08, True)
        part(side + "Hand", (sg * 0.70, 0, 1.40), (sg * 0.80, 0, 1.40), 0.09, 0.04, True)
        part(side + "HandIndex1", (sg * 0.80, 0, 1.40), (sg * 0.86, 0, 1.40), 0.03, 0.03)
        part(side + "UpLeg", (sg * 0.09, 0, 0.92), (sg * 0.09, 0, 0.50), 0.14, 0.14, True)
        part(side + "Leg", (sg * 0.09, 0, 0.50), (sg * 0.09, 0, 0.10), 0.11, 0.11, True)
        part(side + "Foot", (sg * 0.09, -0.05, 0.05), (sg * 0.09, 0.12, 0.05), 0.10, 0.10)
        part(side + "ToeBase", (sg * 0.09, 0.12, 0.03), (sg * 0.09, 0.20, 0.03), 0.09, 0.06)


def make_image(name, size, fn):
    img = bpy.data.images.new(name, size, size, alpha=False)
    px = []
    for y in range(size):
        for x in range(size):
            px.extend(fn(x, y, size))
    img.pixels = px
    img.file_format = 'PNG'
    img.pack()
    return img


def make_material():
    mat = bpy.data.materials.new("TestHeroMat")
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]

    def base(x, y, n):
        c = (x // 8 + y // 8) % 2
        return (0.2 + 0.6 * x / n, 0.3 + 0.4 * c, 0.9 - 0.6 * y / n, 1.0)

    def flat_normal(x, y, n):
        return (0.5, 0.5, 1.0, 1.0)

    def orm(x, y, n):
        return (1.0, 0.6, 0.2 if x < n // 2 else 0.8, 1.0)  # G=粗さ, B=金属

    tb = nt.nodes.new("ShaderNodeTexImage")
    tb.image = make_image("TestHero_BaseColor", 64, base)
    nt.links.new(tb.outputs["Color"], bsdf.inputs["Base Color"])

    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = make_image("TestHero_Normal", 16, flat_normal)
    tn.image.colorspace_settings.name = "Non-Color"
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])

    to = nt.nodes.new("ShaderNodeTexImage")
    to.image = make_image("TestHero_ORM", 16, orm)
    to.image.colorspace_settings.name = "Non-Color"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(to.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return mat


def add_box(bm, uv, dvert, groups, a, b, w, d, bone_name, blend_parent, cell):
    """a->b の箱（3 リング: 頭・中・尾）。頭リングは blend_parent と 0.5 ずつ。"""
    axis = (b - a)
    length = axis.length
    ax = axis.normalized()
    ref = UP if abs(ax.dot(UP)) < 0.9 else FWD
    side = ax.cross(ref).normalized()
    up2 = side.cross(ax).normalized()
    rings = []
    for t in (0.0, 0.5, 1.0):
        c = a + ax * (length * t)
        ring = []
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            v = bm.verts.new(c + side * (sx * w * 0.5 * K * CM) + up2 * (sy * d * 0.5 * K * CM))
            ring.append((v, t))
        rings.append(ring)
    bm.verts.ensure_lookup_table()
    faces = []
    for r0, r1 in ((rings[0], rings[1]), (rings[1], rings[2])):
        for i in range(4):
            j = (i + 1) % 4
            faces.append(bm.faces.new((r0[i][0], r0[j][0], r1[j][0], r1[i][0])))
    faces.append(bm.faces.new([v for v, _ in reversed(rings[0])]))
    faces.append(bm.faces.new([v for v, _ in rings[2]]))
    cu, cv = (cell % 8) / 8.0, (cell // 8) / 8.0
    corners = ((0, 0), (1, 0), (1, 1), (0, 1))
    for f in faces:
        for li, loop in enumerate(f.loops):
            ox, oy = corners[li % 4]
            loop[uv].uv = (cu + 0.02 + ox * 0.10, cv + 0.02 + oy * 0.10)
    gi = groups[bone_name]
    for ring in rings:
        for v, t in ring:
            if blend_parent and t == 0.0:
                v[dvert][gi] = 0.5
                v[dvert][groups[blend_parent]] = 0.5
            else:
                v[dvert][gi] = 1.0


def rot_arm(p, sg, deg):
    """肩（sg*0.17, *, 1.40）を支点に腕側の点を deg 度下げる（A ポーズ）。"""
    s, f, u = p
    if not deg or sg * (s - sg * 0.17) < -1e-9:
        return p
    a = math.radians(deg)
    ps, pu = sg * 0.17, 1.40
    r = abs(s - ps)
    return (ps + sg * r * math.cos(a), f, pu - r * math.sin(a) + (u - pu))


def apply_variant_tables():
    global PREFIX, FWD, RIGHT
    PREFIX = CFG.get("prefix", "mixamorig:")
    FWD = Vector(CFG.get("fwd", (1, 0, 0)))
    RIGHT = FWD.cross(UP)
    deg = CFG.get("apose", 0.0)
    for k, (par, h, t) in list(BONES.items()):
        if deg and any(x in k for x in ("Arm", "Hand")) and "Shoulder" not in k:
            sg = -1 if k.startswith("Left") else 1
            BONES[k] = (par, rot_arm(h, sg, deg), rot_arm(t, sg, deg))
    if deg:
        for i, (b, a, c, w, d, blend) in enumerate(PARTS):
            if any(x in b for x in ("Arm", "Hand")) and "Shoulder" not in b:
                sg = -1 if b.startswith("Left") else 1
                PARTS[i] = (b, rot_arm(a, sg, deg), rot_arm(c, sg, deg), w, d, blend)
    if CFG.get("no_toes"):
        for side in ("Left", "Right"):
            BONES.pop(side + "ToeBase")
            BONES.pop(side + "Toe_End")
        PARTS[:] = [p for p in PARTS if "Toe" not in p[0]]
    if CFG.get("root_bone"):
        items = list(BONES.items())
        BONES.clear()
        BONES["Root"] = (None, (0, 0, 0), (0, 0, 0.1))
        for k, (par, h, t) in items:
            BONES[k] = ("Root" if k == "Hips" else par, h, t)
    for name in CFG.get("drop_bones", ()):
        par = BONES.pop(name)[0]
        for k, (p, h, t) in list(BONES.items()):
            if p == name:
                BONES[k] = (par, h, t)
        PARTS[:] = [(par if b == name else b, *rest) for b, *rest in PARTS]
    if CFG.get("one_toe"):
        for k in ("RightToeBase", "RightToe_End"):
            BONES.pop(k, None)
        PARTS[:] = [p for p in PARTS if p[0] != "RightToeBase"]
    if CFG.get("mirror"):
        # 位置はそのまま名前だけ左右を入れ替える（体の右側に Left* の骨）
        def swap(n):
            return n.replace("Left", "\0").replace("Right", "Left").replace("\0", "Right") if n else n
        items = list(BONES.items())
        BONES.clear()
        for k, (par, h, t) in items:
            BONES[swap(k)] = (swap(par), h, t)
        PARTS[:] = [(swap(b), *rest) for b, *rest in PARTS]


def build_hero():
    BONES.clear()
    PARTS.clear()
    build_bone_table()
    build_parts()
    apply_variant_tables()
    skel = CFG.get("skel_xform") or Matrix.Identity(4)
    rename = CFG.get("rename") or (lambda n: n)
    root = bpy.data.objects.new("Scene_Root", None)
    bpy.context.collection.objects.link(root)
    root.scale = (0.01, 0.01, 0.01)

    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.collection.objects.link(arm)
    arm.parent = root
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    ebs = {}
    for name, (parent, h, t) in BONES.items():
        eb = arm_data.edit_bones.new(PREFIX + rename(name))
        eb.head = skel @ P(*h)
        eb.tail = skel @ P(*t)
        if parent:
            eb.parent = ebs[parent]
            eb.use_connect = (Vector(eb.head) - Vector(ebs[parent].tail)).length < 1e-4
        eb.use_deform = not name.endswith("_End")
        ebs[name] = eb
    bpy.ops.object.mode_set(mode='OBJECT')

    me = bpy.data.meshes.new("Body")
    body = bpy.data.objects.new("Body", me)
    bpy.context.collection.objects.link(body)
    body.parent = arm
    groups = {}
    for name in BONES:
        groups[name] = body.vertex_groups.new(name=PREFIX + rename(name)).index
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    dvert = bm.verts.layers.deform.verify()
    for i, (b, a, c, w, d, blend) in enumerate(PARTS):
        parent = BONES[b][0] if blend else None
        add_box(bm, uv, dvert, groups, P(*a), P(*c), w, d, b, parent, i)
    if CFG.get("dummy_skin"):
        for v in bm.verts:
            v[dvert].clear()
            v[dvert][groups["Hips"]] = 1.0
    if CFG.get("dense"):
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3, use_grid_fill=True)
        for f in bm.faces:
            f.smooth = True
    bm.to_mesh(me)
    bm.free()
    me.materials.append(make_material())
    mod = body.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    if CFG.get("emission"):
        nt = me.materials[0].node_tree
        tb = next(n for n in nt.nodes if n.type == 'TEX_IMAGE' and n.image.name.startswith("TestHero_BaseColor"))
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (2, 2, 1)
        mp.inputs["Location"].default_value = (0.25, 0.1, 0)
        nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], tb.inputs["Vector"])
        bsdf = nt.nodes["Principled BSDF"]
        nt.links.new(tb.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = CFG["emission"]
    if CFG.get("two_mats"):
        m2 = bpy.data.materials.new("Cloak")
        m2.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.1, 0.1, 1)
        me.materials.append(m2)
        for poly in me.polygons:
            zc = sum(me.vertices[i].co.z for i in poly.vertices) / len(poly.vertices)
            if zc > (1.45 * K + OFFSET.z) * CM:
                poly.material_index = 1
        bpy.ops.object.select_all(action='DESELECT')
        bpy.context.view_layer.objects.active = body
        body.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.separate(type='MATERIAL')
        bpy.ops.object.mode_set(mode='OBJECT')
    if CFG.get("arm_scale"):
        arm.scale = CFG["arm_scale"]

    # 混入物
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.location = (5, -5, 3)
    bpy.context.collection.objects.link(cam)
    light = bpy.data.objects.new("Light", bpy.data.lights.new("Light", 'SUN'))
    bpy.context.collection.objects.link(light)
    junk = bpy.data.objects.new("Junk_Empty", None)
    junk.location = (2, 2, 0)
    bpy.context.collection.objects.link(junk)
    return arm, body


def build_sword(pose):
    """剣ローカル（握り原点・+Y・刃の平面が ±X）で作り、pose（ワールド行列）へ置く。"""
    me = bpy.data.meshes.new("Sword")
    obj = bpy.data.objects.new("Sword", me)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()

    def box(cx, cy, cz, sx, sy, sz):
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r["verts"]:
            v.co = Vector((cx + v.co.x * sx, cy + v.co.y * sy, cz + v.co.z * sz))

    box(0, -0.02, 0, 0.05, 0.04, 0.05)     # 柄頭
    box(0, 0.10, 0, 0.035, 0.20, 0.035)    # 柄
    box(0, 0.22, 0, 0.04, 0.04, 0.22)      # 鍔
    box(0, 0.58, 0, 0.012, 0.68, 0.08)     # 刃
    tip = [bm.verts.new(c) for c in ((-0.006, 0.92, -0.04), (0.006, 0.92, -0.04),
                                       (0.006, 0.92, 0.04), (-0.006, 0.92, 0.04))]
    apex = bm.verts.new((0, 1.0, 0))
    for i in range(4):
        bm.faces.new((tip[i], tip[(i + 1) % 4], apex))
    bm.to_mesh(me)
    bm.free()
    uvl = me.uv_layers.new(name="UVMap")
    for i, l in enumerate(uvl.data):
        l.uv = ((i % 7) / 7.0, (i % 5) / 5.0)
    mat = bpy.data.materials.new("SwordMat")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = make_image("Sword_BaseColor", 32, lambda x, y, n: (0.7, 0.7, 0.75 + 0.2 * (y / n), 1.0))
    mat.node_tree.links.new(tex.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    me.materials.append(mat)
    obj.matrix_world = pose
    return obj


# 剣の姿勢（Blender 空間）。lying: 長軸が水平寄りで先端がやや下（断面幅ヒューリスティックで反転させる経路）。
# tilted: 鉛直から約 20° 傾いて先端が上（上端を残す経路）。どちらも刃の平面を長軸回りに 40° ひねる。
SWORD_POSES = {
    "lying": Matrix.Translation((0.4, -0.3, 0.8))
    @ Euler((math.radians(-15), math.radians(25), math.radians(35)), 'XYZ').to_matrix().to_4x4()
    @ Matrix.Rotation(math.radians(40), 4, 'Y') @ Matrix.Diagonal((1.7, 1.7, 1.7, 1.0)),
    "tilted": Matrix.Translation((-0.2, 0.1, 0.05))
    @ Euler((math.radians(70), math.radians(0), math.radians(-120)), 'XYZ').to_matrix().to_4x4()
    @ Matrix.Rotation(math.radians(40), 4, 'Y') @ Matrix.Diagonal((0.6, 0.6, 0.6, 1.0)),
}


def export_glb(path, objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_yup=True, export_skins=True, export_animations=False,
                              export_cameras=True, export_lights=True)


def run_blender(script, args, check=True):
    cmd = [bpy.app.binary_path, "-b", "--factory-startup", "--python-exit-code", "1",
           "--python", os.path.join(HERE, script), "--"] + args
    print("$", " ".join(cmd), flush=True)
    r = subprocess.run(cmd, capture_output=True, text=True)
    sys.stdout.write("\n".join(l for l in r.stdout.splitlines() if l.startswith(("[normalize]", "{"))) + "\n")
    if r.returncode != 0 and check:
        sys.stdout.write(r.stdout[-4000:] + r.stderr[-4000:])
        raise SystemExit(f"{script} failed ({r.returncode})")
    return r.returncode, r.stdout + r.stderr


VERIFY_SRC = os.path.join(HERE, "verify_usdz.swift")
VERIFY_BIN = os.path.join(os.environ.get("TRIPO_BUILD_DIR") or os.path.join(APP, "build", "tripo"), "verify_usdz")


def verify_command():
    """verify_usdz.swift を swiftc で 1 度だけコンパイルして使う（バイナリがソースより新しければ再利用。tools/tripo.mjs と
    同じ置き場所）。コンパイルできなければ swift でスクリプトとして毎回実行する（1 回数秒遅い）。"""
    if not (os.path.exists(VERIFY_BIN) and os.path.getmtime(VERIFY_BIN) >= os.path.getmtime(VERIFY_SRC)):
        os.makedirs(os.path.dirname(VERIFY_BIN), exist_ok=True)
        tmp = f"{VERIFY_BIN}.{os.getpid()}.tmp"
        r = subprocess.run([os.environ.get("SWIFTC", "swiftc"), "-O", VERIFY_SRC, "-o", tmp], capture_output=True, text=True)
        if r.returncode != 0:
            print("swiftc failed; running verify_usdz.swift as a script:\n" + r.stderr[-2000:], flush=True)
            return ["swift", VERIFY_SRC]
        os.replace(tmp, VERIFY_BIN)
    return [VERIFY_BIN]


def run_verify(path, args=()):
    r = subprocess.run([*verify_command(), path, *args], capture_output=True, text=True)
    fails = [l[6:].split("  ")[0] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    return r.returncode, fails


# MARK: - 変種（--variants）

VAR_DIR = os.path.join(OUT_DIR, "variants")


def hips_pivot(deg, axis):
    h = P(0, 0, 0.95)
    return Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-h)


# Mixamo 名 → Meshy 自動リグの骨名（実物の H002 で確かめた。norm_common.MESHY_TO_MIXAMO の逆）
MESHY_NAMES = {"Spine": "Spine02", "Spine1": "Spine01", "Spine2": "Spine", "Neck": "neck", "HeadTop_End": "head_end"}


def meshy_spine_order(joints):
    """付け替え後の joints に Meshy 名が残らず、背骨が Spine → Spine1 → Spine2 の順（親が先）に並ぶか。"""
    leaves = [j.split(":")[-1] for j in joints]
    if any(n in leaves for n in ("Spine01", "Spine02", "neck", "head_end")):
        return False
    return all(n in leaves for n in ("Spine", "Spine1", "Spine2", "Neck")) and \
        leaves.index("Spine") < leaves.index("Spine1") < leaves.index("Spine2") < leaves.index("Neck")


meshy_report = {"jointRenames": lambda v: v == {"Spine02": "Spine", "Spine01": "Spine1", "Spine": "Spine2", "neck": "Neck",
                                                 "head_end": "HeadTop_End"},
                "joints": meshy_spine_order}


# 名前: (CFG, normalize の追加引数, 期待)
# 期待: exit（終了コード）, verify_fail（許す verify の FAIL 名。None なら verify しない）, error（stderr に含む語）,
#       report（report のキー -> 判定関数）
def hero_variants():
    ok = dict(exit=0, verify_fail=set())
    facing = lambda src, reliable: {"forwardSource": lambda v: v == src, "rightSideAtPlusX": bool,  # noqa: E731
                                    "facing": lambda v: v["reliable"] is reliable}
    return {
        "base": ({}, [], ok),
        "noprefix": ({"prefix": ""}, [], ok),
        "mixamorig1": ({"prefix": "mixamorig1:"}, [], ok),
        "rootbone": ({"root_bone": True}, [], ok),
        "apose45": ({"apose": 45}, [], dict(ok, report={"armDownDegrees": lambda v: abs(v["L"] - 45) < 2 and abs(v["R"] - 45) < 2})),
        "apose61": ({"apose": 61}, [], dict(ok, report={"armDownDegrees": lambda v: abs(v["L"] - 61) < 2 and abs(v["R"] - 61) < 2})),
        "twomesh": ({"two_mats": True}, [], ok),
        "emission4": ({"emission": 4.0}, [], dict(ok, emissive_scale=4.0)),
        "nonuniform": ({"arm_scale": (1.0, 1.4, 0.8)}, [], ok),
        "facePlusZ": ({"fwd": (0, -1, 0)}, [], ok),
        "faceMinusZ": ({"fwd": (0, 1, 0)}, [], ok),
        "notoes": ({"no_toes": True}, [], dict(ok, report=facing("arms", False))),
        "notoes_facePlusZ": ({"no_toes": True, "fwd": (0, -1, 0)}, [], dict(ok, report=facing("arms", False))),
        # 片方のつま先だけ: 確かではないが腕・脚と一致するのでつま先を使う
        "one_toe": ({"one_toe": True}, [], dict(ok, report=facing("toes", False))),
        # 実物の Tripo Studio リグに近い形（A ポーズ約 60°・glTF +Z 向き）
        "tripo_apose60_facePlusZ": ({"apose": 60, "fwd": (0, -1, 0)}, [], dict(ok, report=facing("toes", True))),
        "dense_decimated": ({"dense": True}, ["--max-faces", "2000"],
                            dict(ok, report={"boundaryEdges": lambda v: v["after"] <= max(64, 2 * v["beforeDecimate"]),
                                             "faces": lambda v: v <= 2100})),
        "fbx": ({}, ["@fbx"], ok),
        # Meshy の自動リグ（接頭辞なし・背骨が腰側から Spine02/Spine01/Spine・neck・head_end、glTF +Z 向き）:
        # normalize_hero.py が Mixamo 名へ付け替え、背骨の順が Spine → Spine1 → Spine2 になる
        "meshy_facePlusZ": ({"prefix": "", "fwd": (0, -1, 0), "rename": lambda n: MESHY_NAMES.get(n, n)}, [],
                            dict(ok, report=meshy_report)),
        "meshy_fbx": ({"prefix": "", "fwd": (0, -1, 0), "rename": lambda n: MESHY_NAMES.get(n, n)}, ["@fbx"],
                      dict(ok, report=meshy_report)),
        # 失敗させたい入力（Tripo GLB で実際に見た崩れ）
        "BAD_dummy_skin": ({"dummy_skin": True}, [], dict(exit=1, error="dummy bind")),
        "BAD_skeleton_rotX": ({"skel_xform": Matrix.Rotation(math.radians(-90), 4, 'X') @ Matrix.Diagonal((0.2, 0.2, 0.2, 1))},
                              [], dict(exit=1, error="outside the mesh bounds")),
        "BAD_skeleton_yaw90": ({"skel_xform": "yaw90"}, [], dict(exit=1, error="outside the mesh bounds")),
        # 左右の名前が入れ替わったリグ: つま先で -Z を向けると Right* が -X に来る
        "BAD_mirrored": ({"mirror": True}, [], dict(exit=1, error="mirrored rig", report={"errors": bool})),
        "BAD_mirrored_facePlusZ_apose": ({"mirror": True, "fwd": (0, -1, 0), "apose": 60}, [],
                                         dict(exit=1, error="mirrored rig")),
        # つま先が片方だけ（確かでない）で、腕・脚の左右（鏡像）と 180° 食い違う
        "BAD_mirrored_one_toe": ({"mirror": True, "one_toe": True}, [], dict(exit=1, error="facing is ambiguous")),
        # 実行時の必須の骨が無い（手は腕に直接付く）
        "BAD_missing_forearm": ({"drop_bones": ["LeftForeArm"]}, [],
                                dict(exit=1, error="missing required joint", report={"errors": bool})),
        # canonical_bone では当たるが実行時の規則（'_' を外さない）では当たらない骨名: Left_Fore_Arm など
        "BAD_underscored_names": ({"rename": lambda n: re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", n)}, [],
                                  dict(exit=1, error="missing required joint")),
    }


def emissive_scale(usdz):
    from pxr import Usd, UsdShade
    st = Usd.Stage.Open(usdz)
    for p in st.Traverse():
        if p.IsA(UsdShade.Shader) and p.GetName().endswith("_emissive"):
            v = UsdShade.Shader(p).GetInput("scale")
            return tuple(v.Get()) if v else None
    return None


def run_hero_variant(name, cfg, extra, exp):
    global CFG
    CFG = dict(cfg)
    if CFG.get("skel_xform") == "yaw90":
        CFG["skel_xform"] = hips_pivot(90, 'Z')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_hero()
    src = os.path.join(VAR_DIR, name + ".glb")
    if "@fbx" in extra:
        extra = [x for x in extra if x != "@fbx"]
        src = os.path.join(VAR_DIR, name + ".fbx")
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.export_scene.fbx(filepath=src, use_selection=False, add_leaf_bones=True, bake_anim=False,
                                 path_mode='COPY', embed_textures=True)
    else:
        export_glb(src, list(bpy.data.objects))
    CFG = {}
    out = os.path.join(VAR_DIR, name + ".usdz")
    rep = os.path.join(VAR_DIR, name + ".json")
    for f in (out, rep):
        if os.path.exists(f):
            os.remove(f)
    code, log = run_blender("normalize_hero.py", ["--in", src, "--out", out, "--texture-size", "64",
                                                  "--report", rep] + extra, check=False)
    problems = []
    if code != exp["exit"]:
        problems.append(f"exit {code} (expected {exp['exit']})")
    if exp.get("error") and exp["error"] not in log:
        problems.append(f"no '{exp['error']}' in the log")
    vres = "-"
    if code == 0 and exp.get("verify_fail") is not None:
        vcode, fails = run_verify(out, ["--expect", "hero"])
        extra_fails = [f for f in fails if f not in exp["verify_fail"]]
        vres = "PASS" if not fails else "FAIL(" + ", ".join(fails) + ")"
        if extra_fails:
            problems.append("verify: " + ", ".join(extra_fails))
    report = json.load(open(rep)) if os.path.exists(rep) else {}
    for k, fn in (exp.get("report") or {}).items():
        if k not in report or not fn(report[k]):
            problems.append(f"report {k}={report.get(k)}")
    if exp.get("emissive_scale") and code == 0:
        sc = emissive_scale(out)
        if not sc or abs(sc[0] - exp["emissive_scale"]) > 1e-4:
            problems.append(f"emissive scale {sc}")
    note = ""
    if code == 0 and os.path.exists(out) is False:
        problems.append("exit 0 but no output")
    if code != 0 and os.path.exists(out):
        problems.append("exit 1 but the output was left behind")
    if code != 0 and not report.get("errors"):
        problems.append("no errors in the report")
    if code == 0:
        note = f"armDown={report.get('armDownDegrees')} fwd={report.get('forwardSource')} " \
               f"top={list(report.get('weightCoverage', {}).get('top', {}).items())[:1]} warn={len(report.get('warnings', []))}"
    else:
        errs = [l for l in log.splitlines() if "ERROR:" in l]
        note = (errs[0].split("ERROR: ")[1][:90] if errs else log.strip().splitlines()[-1][:90])
    return problems, vres, note


# Prop の元モデル（Tripo の向き: Blender で正面 +X・上 +Z・画像の右 +Y）。部品 = (中心, 大きさ, 素材名)。
# 素材名 Marker_* の部品の重心を出力で調べ、期待する USD 軸の符号にあるかを見る。
def prop_parts(kind):
    B = []

    def box(c, sz, mat="Body"):
        B.append((Vector(c), Vector(sz), mat))

    if kind in ("sword", "katana"):
        box((0, 0, 0.05), (0.035, 0.035, 0.2))        # 柄
        box((0, 0, 0.17), (0.04, 0.22, 0.04))         # 鍔
        box((0, 0, 0.55), (0.012, 0.08, 0.7))         # 刃
        box((0.012, 0, 0.25), (0.012, 0.02, 0.03), "Marker_front")
        if kind == "katana":
            box((0, 0.045, 0.55), (0.006, 0.01, 0.6), "Marker_edge")   # 画像の右 = 刃先
    elif kind in ("rifle_left", "rifle_right"):
        sy = -1 if kind == "rifle_left" else 1
        box((0, 0, 0.1), (0.04, 0.12, 0.3))           # 銃床
        box((0, 0, 0.55), (0.035, 0.035, 0.6))        # 銃身
        box((0, sy * 0.07, 0.45), (0.03, 0.06, 0.3), "Marker_top")  # スコープ（上面）
    elif kind in ("bow_left", "bow_right"):
        sy = -1 if kind == "bow_left" else 1
        box((0, 0, 0), (0.03, 0.05, 0.15))             # 握り
        for i in range(1, 6):
            t = i / 5.0
            for sz in (-1, 1):
                box((0, sy * 0.25 * t * t, sz * 0.5 * t), (0.025, 0.03, 0.12))
        box((0, sy * 0.26, 0), (0.006, 0.006, 1.0), "Marker_string")
    elif kind == "tower_shield":
        box((0, 0, 0), (0.06, 0.54, 0.6))
        for y in (-0.15, 0.15):
            box((0, y, 0.36), (0.06, 0.1, 0.12))
        box((0.04, 0, 0.1), (0.02, 0.08, 0.08), "Marker_face")
    elif kind == "round_shield":
        for i in range(24):
            a = i / 24 * 2 * math.pi
            box((0, 0.27 * math.cos(a), 0.27 * math.sin(a)), (0.07, 0.09, 0.09))
        box((0, 0, 0), (0.05, 0.4, 0.4))
        box((0.05, 0, 0), (0.05, 0.1, 0.1), "Marker_face")
        box((0, 0, 0.37), (0.03, 0.04, 0.1), "Marker_top")
        box((0, 0.2, -0.3), (0.03, 0.04, 0.06))       # 非対称の飾り（PCA を傾ける）
    elif kind == "crossbow":
        box((0, 0, 0), (0.06, 0.08, 0.6))              # 銃床（上から見る）
        box((0, 0, 0.25), (0.04, 0.6, 0.05))           # 弓（画像の左右 = ±Y）
        box((0.05, 0, 0.05), (0.05, 0.04, 0.2), "Marker_top")      # 弾倉（上面 = 画像の正面）
    elif kind == "grimoire":
        box((0, 0, 0), (0.075, 0.22, 0.28))
        box((0.04, 0, 0), (0.01, 0.08, 0.08), "Marker_cover")
    elif kind == "plate_rod":
        # 縦長の板を水平の長い棒が貫く: 面積重みの PCA は板の縦を長軸に選び、棒（外接箱の最長）が Z に残る
        box((0, 0, 0), (0.02, 0.5, 0.6))
        box((0, 0, 0), (1.0, 0.03, 0.03))
    return B


def build_prop(kind, src_rot):
    mats = {}
    objs = []
    for c, sz, mname in prop_parts(kind):
        if mname not in mats:
            m = bpy.data.materials.new(mname)
            m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = \
                (0.9, 0.2, 0.1, 1) if mname.startswith("Marker") else (0.6, 0.6, 0.65, 1)
            mats[mname] = m
        me = bpy.data.meshes.new(mname)
        bm = bmesh.new()
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r["verts"]:
            v.co = Vector((c.x + v.co.x * sz.x, c.y + v.co.y * sz.y, c.z + v.co.z * sz.z))
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mats[mname])
        o = bpy.data.objects.new(mname, me)
        bpy.context.collection.objects.link(o)
        o.matrix_world = src_rot
        objs.append(o)
    return objs


def marker_centroids(usdz):
    """USD 空間での Marker_* 部分の重心と全体の外接箱。"""
    from pxr import Usd, UsdGeom, UsdShade
    st = Usd.Stage.Open(usdz)
    out, allp = {}, []
    for p in st.Traverse():
        if not p.IsA(UsdGeom.Mesh):
            continue
        mesh = UsdGeom.Mesh(p)
        xf = UsdGeom.Xformable(p).ComputeLocalToWorldTransform(Usd.TimeCode.Default())
        pts = [xf.Transform(q) for q in mesh.GetPointsAttr().Get()]
        allp += pts
        counts = mesh.GetFaceVertexCountsAttr().Get()
        idx = mesh.GetFaceVertexIndicesAttr().Get()
        starts, o = [], 0
        for c in counts:
            starts.append(o)
            o += c
        for sub in UsdGeom.Subset.GetAllGeomSubsets(mesh):
            mp = UsdShade.MaterialBindingAPI(sub.GetPrim()).GetDirectBinding().GetMaterialPath()
            name = mp.name if mp else ""
            if not name.startswith("Marker"):
                continue
            vs = {idx[starts[f] + k] for f in sub.GetIndicesAttr().Get() for k in range(counts[f])}
            q = [pts[i] for i in vs]
            out[name] = tuple(sum(v[i] for v in q) / len(q) for i in range(3))
    lo = tuple(min(v[i] for v in allp) for i in range(3))
    hi = tuple(max(v[i] for v in allp) for i in range(3))
    return out, lo, hi


GLTF_FRONT_ROT = {  # 元モデル（正面 +X）を回して、正面が glTF の各軸を向く入力を作る
    "+x": Matrix.Identity(4),
    "-x": Matrix.Rotation(math.pi, 4, 'Z'),
    "+z": Matrix.Rotation(-math.pi / 2, 4, 'Z'),   # Blender -Y = glTF +Z
    "-z": Matrix.Rotation(math.pi / 2, 4, 'Z'),
}


# 名前: (形, 元の正面, 元の追加回転, normalize_prop の引数, verify の引数, {Marker: (USD 軸, 符号)}, 期待する警告の語 or None
#        （"*" は警告を調べない）[, 期待する verify の FAIL 名の集合（既定は空 = すべて PASS）])
def prop_variants():
    tilt = Matrix.Rotation(math.radians(12), 4, 'Y')
    LY = ["--long-axis", "y"]
    return {
        "sword_front+x": ("sword", "+x", None, [], LY, {"Marker_front": (0, 1)}, None),
        "sword_front-x": ("sword", "-x", None, [], LY, {"Marker_front": (0, 1)}, None),
        "sword_front+z": ("sword", "+z", None, [], LY, {"Marker_front": (0, 1)}, None),
        "sword_front-z": ("sword", "-z", None, [], LY, {"Marker_front": (0, 1)}, None),
        "sword_tilt12": ("sword", "+x", tilt, [], LY, {"Marker_front": (0, 1)}, None),
        "katana_edge_right": ("katana", "+x", None, ["--grip", "0.12"], ["--grip", "0.12"] + LY,
                              {"Marker_front": (0, 1), "Marker_edge": (2, -1)}, None),
        "rifle_scope_left": ("rifle_left", "-x", None, ["--grip", "0.29", "--side", "gun"], ["--grip", "0.29"] + LY,
                             {"Marker_top": (2, 1)}, None),
        "rifle_scope_right_warns": ("rifle_right", "+x", None, ["--grip", "0.29", "--side", "gun"], ["--grip", "0.29"] + LY,
                                    {"Marker_top": (2, -1)}, "more mass on -Z"),
        "bow_string_left": ("bow_left", "+x", None, ["--grip", "0.5", "--side", "bow"], ["--grip", "0.5"] + LY,
                            {"Marker_string": (2, 1)}, None),
        "bow_string_right_fixed": ("bow_right", "+z", None, ["--grip", "0.5", "--side", "bow"], ["--grip", "0.5"] + LY,
                                   {"Marker_string": (2, 1)}, "turned 180"),
        "tower_shield_yaw90": ("tower_shield", "+x", None, ["--grip", "0.5", "--yaw=90"],
                               ["--grip", "0.5", "--thin-axis", "z"], {"Marker_face": (2, -1)}, None),
        "round_shield_vertical": ("round_shield", "-x", None, ["--grip", "0.5", "--axis", "vertical", "--yaw=90"],
                                  ["--grip", "0.5", "--thin-axis", "z"], {"Marker_face": (2, -1), "Marker_top": (1, 1)}, None),
        "crossbow_yaw-90": ("crossbow", "+x", None, ["--grip", "0.35", "--yaw=-90"],
                            ["--grip", "0.35", "--thin-axis", "z"], {"Marker_top": (2, 1)}, None),
        "grimoire_yaw180": ("grimoire", "+z", None, ["--grip", "0.5", "--yaw=180"], ["--grip", "0.5"] + LY,
                            {"Marker_cover": (0, -1)}, None),
        # 正規化の長軸（PCA）が外接箱の最長と食い違う形: 取り込みの関門（--long-axis y）で弾く
        "BAD_plate_rod_longZ": ("plate_rod", "+x", None, ["--grip", "0.5"], ["--grip", "0.5"] + LY, {}, "*",
                                {"longest axis is Y"}),
    }


def run_prop_variant(name, spec):
    kind, front, extra_rot, nargs, vargs, markers, warn_word, *rest = spec
    expect_fail = set(rest[0]) if rest else set()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rot = GLTF_FRONT_ROT[front] @ (extra_rot or Matrix.Identity(4))
    src = os.path.join(VAR_DIR, f"prop_{name}.glb")
    export_glb(src, build_prop(kind, rot))
    out = os.path.join(VAR_DIR, f"Prop_{name}.usdz")
    rep = os.path.join(VAR_DIR, f"Prop_{name}.json")
    code, log = run_blender("normalize_prop.py", ["--in", src, "--out", out, f"--front={front}",
                                                  "--report", rep] + nargs, check=False)
    problems = []
    if code != 0:
        return [f"exit {code}"], "-", log.strip().splitlines()[-1][:90]
    vcode, fails = run_verify(out, ["--expect", "prop"] + vargs)
    if set(fails) != expect_fail or (vcode == 0) != (not expect_fail):
        problems.append(f"verify exit {vcode}: FAIL {sorted(fails)} (expected {sorted(expect_fail)})")
    cents, lo, hi = marker_centroids(out)
    mid = [(lo[i] + hi[i]) * 0.5 for i in range(3)]
    parts = []
    for m, (ax, sg) in markers.items():
        c = cents.get(m)
        ref = 0.0 if ax == 1 else mid[ax]
        if c is None or (c[ax] - ref) * sg <= 0:
            problems.append(f"{m} {'xyz'[ax]}={None if c is None else round(c[ax], 3)} (expected {'+' if sg > 0 else '-'})")
        else:
            parts.append(f"{m[7:]} {'xyz'[ax]}={c[ax]:+.3f}")
    report = json.load(open(rep))
    warns = report.get("warnings", [])
    if warn_word and warn_word != "*" and not any(warn_word in w for w in warns):
        problems.append(f"no warning '{warn_word}'")
    if not warn_word and warns:
        problems.append("unexpected warnings: " + "; ".join(warns))
    note = " ".join(parts) + f" ext=({hi[0] - lo[0]:.2f},{hi[1] - lo[1]:.2f},{hi[2] - lo[2]:.2f})" \
        + f" side={report.get('side', {}).get('bias')}"
    return problems, "PASS" if not fails else "FAIL(" + ", ".join(fails) + ")", note


def run_variants(only):
    os.makedirs(VAR_DIR, exist_ok=True)
    rows = []
    for name, (cfg, extra, exp) in hero_variants().items():
        if only and name not in only:
            continue
        problems, vres, note = run_hero_variant(name, cfg, extra, exp)
        rows.append(("hero", name, "PASS" if not problems else "FAIL", vres, "; ".join(problems) or note))
    for name, spec in prop_variants().items():
        if only and name not in only:
            continue
        problems, vres, note = run_prop_variant(name, spec)
        rows.append(("prop", name, "PASS" if not problems else "FAIL", vres, "; ".join(problems) or note))
    print("\nVARIANTS")
    print("| kind | variant | expected | verify_usdz | note |")
    print("|---|---|---|---|---|")
    for r in rows:
        print("| " + " | ".join(r) + " |")
    bad = [r for r in rows if r[2] != "PASS"]
    print(f"VARIANTS {'PASS' if not bad else 'FAIL'} ({len(rows) - len(bad)}/{len(rows)})", flush=True)
    if bad:
        raise SystemExit(1)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT_DIR, exist_ok=True)
    if "--variants" in args:
        run_variants([x for x in args if not x.startswith("--")])
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_hero()
    rigged = os.path.join(OUT_DIR, "rigged.glb")
    export_glb(rigged, list(bpy.data.objects))

    swords = {}
    for key, pose in SWORD_POSES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        swords[key] = os.path.join(OUT_DIR, f"sword_{key}.glb")
        export_glb(swords[key], [build_sword(pose)])

    hero_out = os.path.join(OUT_DIR, "SkinnedTestHero.usdz")
    run_blender("normalize_hero.py", ["--in", rigged, "--out", hero_out, "--texture-size", "64",
                                      "--report", os.path.join(OUT_DIR, "hero_report.json")])
    if "--update-fixture" in args:
        os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
        shutil.copyfile(hero_out, FIXTURE)
        print(f"fixture updated: {FIXTURE}", flush=True)
    for key, path in swords.items():
        name = "Prop_test" if key == "lying" else f"Prop_test_{key}"
        run_blender("normalize_prop.py", ["--in", path, "--out", os.path.join(OUT_DIR, name + ".usdz"),
                                          "--report", os.path.join(OUT_DIR, name + "_report.json")])


if __name__ == "__main__":
    main()
