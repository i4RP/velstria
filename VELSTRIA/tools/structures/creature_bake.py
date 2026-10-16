# 担当: battle-renderer（中立モンスターの動く生成モデル）。Blender 5.2 headless で実行する:
#   Blender -b --factory-startup --python tools/structures/creature_bake.py -- --id monster_red \
#       --work build/structures/monster_red --out App/Resources/Structures --faces 4500 --size '{"length": 3.8, "yaw": 140}'
# tools/structures/creature_rig.mjs が作った rig.glb / anim_<preset>.glb から
# App/Resources/Structures/Creature_<id>.usdz（スキン + 動作 1 本）と Creature_<id>.json（動作の区間）を作る。
#
# 1. 基準の GLB（人型は anim_idle、四足は anim_walk）の骨とメッシュを読み、他の anim_*.glb からは動作だけを取る
# 2. structures_bake と同じ yaw・size で骨ごと正面・寸法を合わせる（骨の移動のキーは拡縮率を掛ける）
# 3. 足りない動作（四足の待機・攻撃・被弾）は骨に手付けする（首・背骨・前脚を体の横軸回りに回す）
# 4. idle / walk / attack / hit を 1 本のタイムラインに並べて書き出す（実行時は区間を切り出して再生）
import argparse
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "blender"))
sys.path.insert(0, HERE)
import norm_common as nc  # noqa: E402
import structures_bake as sb  # noqa: E402

FPS = 30
# 実行時の動作名 → Tripo のプリセット名（先頭が見つかった物を使う）
CLIP_SOURCES = {
    "idle": ["idle"],
    "walk": ["walk"],
    "attack": ["chop", "slash"],
    "hit": ["hit_to_body_01", "hurt"],
}
ORDER = ["idle", "walk", "attack", "hit"]


def log(msg):
    print(f"[creature] {msg}", flush=True)


def parse():
    p = argparse.ArgumentParser(prog="creature_bake.py")
    p.add_argument("--id", required=True)
    p.add_argument("--work", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--faces", type=int, default=5000)
    p.add_argument("--size", default="{}")
    p.add_argument("--texture", type=int, default=1024)
    # 自前の骨で作る（4 = 四足、2 = 二足の小物。Tripo の動作 GLB は使わない）
    p.add_argument("--legs", type=int, default=0)
    return p.parse_args(nc.script_args())


def import_raw(path):
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path, import_pack_images=True, merge_vertices=True)
    objs = [o for o in bpy.data.objects if o not in before]
    acts = [a for a in bpy.data.actions if a not in acts_before]
    return objs, acts


def clip_files(work):
    found = {}
    for f in os.listdir(work):
        if f.startswith("anim_") and f.endswith(".glb"):
            found[f[5:-4]] = os.path.join(work, f)
    return found


def sample(arm, action, scene):
    """動作を整数フレームで標本化（骨ごとの loc / quat / scale）。"""
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = action
    if hasattr(ad, "action_slot") and getattr(action, "slots", None) and len(action.slots):
        ad.action_slot = action.slots[0]
    lo, hi = action.frame_range
    frames = []
    for f in range(int(math.ceil(lo)), int(math.floor(hi)) + 1):
        scene.frame_set(f)
        frames.append({pb.name: (pb.location.copy(), pb.rotation_quaternion.copy() if pb.rotation_mode == 'QUATERNION'
                                 else pb.rotation_euler.to_quaternion(), pb.scale.copy()) for pb in arm.pose.bones})
    ad.action = None
    return frames


def rest_pose(arm):
    return {pb.name: (Vector(), Quaternion(), Vector((1, 1, 1))) for pb in arm.pose.bones}


def procedural(arm, kind):
    """四足の待機・攻撃・被弾を手付けする。体の横軸（前 × 上）回りに首・背骨・前脚を回す。"""
    bones = arm.data.bones
    heads = [b for b in bones if "Head_" in b.name]
    spines = [b for b in bones if "Spine_" in b.name]
    root = bones[0]
    fwd = (heads[0].head_local - root.head_local) if heads else Vector((0, 1, 0))
    fwd.z = 0
    fwd = fwd.normalized() if fwd.length > 1e-6 else Vector((0, 1, 0))
    side = fwd.cross(Vector((0, 0, 1))).normalized()
    # 前脚 = 肢の付け根が頭に近い組（0_ / 1_）
    groups = {}
    for b in bones:
        if "_Limb_0" in b.name:
            g = b.name.split("::")[-1].split("_")[0]
            groups.setdefault(g, []).append(b)
    front = []
    if heads and groups:
        hp = heads[0].head_local

        def dist(g):
            return sum((b.head_local - hp).length for b in groups[g]) / len(groups[g])
        fg = min(groups, key=dist)
        front = groups[fg]

    def local_axis(b):
        return (b.matrix_local.to_3x3().inverted() @ side).normalized()

    def pose(rot):
        """rot: {bone: 角度（正 = 前を上へ / 下向きの脚は前へ）}"""
        p = rest_pose(arm)
        for b, ang in rot.items():
            if ang:
                p[b.name] = (Vector(), Quaternion(local_axis(b), ang), Vector((1, 1, 1)))
        return p

    def spread(bs, ang):
        return {b: ang / max(1, len(bs)) for b in bs}

    frames = []
    if kind == "idle":
        n = int(2.4 * FPS)
        for i in range(n):
            t = i / n * 2 * math.pi
            rot = {}
            rot.update(spread(spines, math.sin(t) * 0.05))
            rot.update(spread(heads, math.sin(t - 0.8) * 0.12))
            frames.append(pose(rot))
    elif kind == "attack":
        n = int(0.9 * FPS)
        for i in range(n):
            t = i / n
            # 0〜0.4 溜め（頭・前脚を上げる）→ 0.4〜0.55 振り下ろし → 戻り
            if t < 0.4:
                k = math.sin(t / 0.4 * math.pi / 2)
                head, spine, leg = 0.6 * k, 0.25 * k, 0.9 * k
            elif t < 0.55:
                k = (t - 0.4) / 0.15
                head, spine, leg = 0.6 - 1.4 * k, 0.25 - 0.45 * k, 0.9 - 1.4 * k
            else:
                k = 1 - (t - 0.55) / 0.45
                k = k * k
                head, spine, leg = -0.8 * k, -0.2 * k, -0.5 * k
            rot = {}
            rot.update(spread(spines, spine))
            rot.update(spread(heads, head))
            for b in front:
                rot[b] = leg
            frames.append(pose(rot))
    elif kind == "hit":
        n = int(0.4 * FPS)
        for i in range(n):
            k = math.sin(i / n * math.pi) * (1 - i / n * 0.3)
            rot = {}
            rot.update(spread(spines, -0.12 * k))
            rot.update(spread(heads, 0.3 * k))
            frames.append(pose(rot))
    return frames


# MARK: - 自前の骨（Tripo のリグが崩れる四足・リグ不可の物）

def autorig(mesh, legs):
    """正面 +Y・足元 0 に合わせたメッシュへ、背骨・首・尾・脚（legs 本）の骨を組み、距離でウェイトを付ける。"""
    vs = [v.co.copy() for v in mesh.data.vertices]
    lo, hi = nc.bbox(vs)
    H, L, W = hi.z - lo.z, hi.y - lo.y, hi.x - lo.x
    low = [v for v in vs if v.z < lo.z + 0.12 * H]
    my = sorted(v.y for v in low)[len(low) // 2] if low else 0.0
    feet = {}
    if legs == 4:
        for key, cond in (("FL", lambda v: v.x < 0 and v.y >= my), ("FR", lambda v: v.x >= 0 and v.y >= my),
                          ("BL", lambda v: v.x < 0 and v.y < my), ("BR", lambda v: v.x >= 0 and v.y < my)):
            pts = [v for v in low if cond(v)]
            if pts:
                feet[key] = sum(pts, Vector()) / len(pts)
            else:
                feet[key] = Vector((W * (0.25 if "R" in key else -0.25), L * (0.25 if key[0] == "F" else -0.25), 0))
        yf = (feet["FL"].y + feet["FR"].y) / 2
        yb = (feet["BL"].y + feet["BR"].y) / 2
    else:
        for key, cond in (("L", lambda v: v.x < 0), ("R", lambda v: v.x >= 0)):
            pts = [v for v in low if cond(v)]
            feet[key] = sum(pts, Vector()) / len(pts) if pts else Vector((W * (0.2 if key == "R" else -0.2), 0, 0))
        yf = yb = (feet["L"].y + feet["R"].y) / 2
    hip = 0.45 * H
    arm_data = bpy.data.armatures.new("rig")
    arm = bpy.data.objects.new("rig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    nc.select_only([arm])
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones

    def bone(name, h, t, parent=None):
        b = eb.new(name)
        b.head, b.tail = Vector(h), Vector(t)
        if parent:
            b.parent = eb[parent]
        return b

    cy = (yf + yb) / 2
    bone("root", (0, cy, 0), (0, cy, 0.15 * H))
    roles = {"root": "root", "legs": {}}
    if legs == 4:
        bone("spine", (0, yb, hip), (0, yf, hip), "root")
        front = [v for v in vs if v.y > hi.y - 0.18 * L]
        hp = sum(front, Vector()) / len(front)
        bone("head", (0, yf, hip), (0, hp.y, max(hp.z, hip)), "spine")
        roles.update(spine="spine", head="head")
        rear = [v for v in vs if v.y < lo.y + 0.15 * L]
        if rear and lo.y < yb - 0.12 * L:
            tp = sum(rear, Vector()) / len(rear)
            bone("tail", (0, yb, hip), (0, tp.y, tp.z), "spine")
            roles["tail"] = "tail"
        for k, f in feet.items():
            bone(f"leg_{k}", (f.x, f.y, hip * 0.9), (f.x, f.y, 0.0), "spine")
            roles["legs"][k] = f"leg_{k}"
    else:
        bone("spine", (0, cy, 0.3 * H), (0, cy, 0.95 * H), "root")
        roles.update(spine="spine")
        for k, f in feet.items():
            bone(f"leg_{k}", (f.x, f.y, 0.35 * H), (f.x, f.y, 0.0), "root")
            roles["legs"][k] = f"leg_{k}"
    eb["root"].use_deform = False
    bpy.ops.object.mode_set(mode='OBJECT')

    # ウェイト: 骨の線分までの距離の 4 乗の逆数（上位 2 本）。脚は腰より下の頂点だけ
    segs = [(b.name, b.head_local.copy(), b.tail_local.copy()) for b in arm_data.bones if b.use_deform]
    groups = {n: mesh.vertex_groups.new(name=n) for n, _, _ in segs}

    def dist(p, a, b):
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
        return (p - (a + ab * t)).length

    leg_top = hip * 1.05 if legs == 4 else 0.4 * H
    for i, p in enumerate(vs):
        ws = []
        for n, a_, b_ in segs:
            if n.startswith("leg_") and p.z > leg_top:
                continue
            d = dist(p, a_, b_)
            ws.append((1.0 / (d ** 4 + 1e-6 * H ** 4), n))
        ws.sort(reverse=True)
        ws = ws[:2]
        tot = sum(w for w, _ in ws)
        for w, n in ws:
            groups[n].add([i], w / tot, 'REPLACE')
    mod = mesh.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    mesh.parent = arm
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return arm, roles, H


def procedural_auto(arm, roles, kind, H):
    """自前の骨の手付け動作（横軸 = +X、上 = +Z。正の角度で頭が上がる・下向きの脚が前へ出る）。"""
    AXES = {"side": Vector((1, 0, 0)), "up": Vector((0, 0, 1)), "fwd": Vector((0, 1, 0))}
    bones = arm.data.bones

    def q(name, axis, ang):
        b = bones[name]
        ax = (b.matrix_local.to_3x3().inverted() @ AXES[axis]).normalized()
        return Quaternion(ax, ang)

    def frame(rot, bob=0.0):
        p = rest_pose(arm)
        for (name, axis), ang in rot.items():
            if name and name in bones and ang:
                p[name] = (Vector(), q(name, axis, ang), Vector((1, 1, 1)))
        # root は上向きの骨 → ローカル +Y が上
        p["root"] = (Vector((0, bob, 0)), Quaternion(), Vector((1, 1, 1)))
        return p

    sp, hd, tl, lg = roles.get("spine"), roles.get("head"), roles.get("tail"), roles["legs"]
    quad = len(lg) == 4
    out = []
    if kind == "idle":
        n = int(2.4 * FPS)
        for i in range(n):
            t = i / n * 2 * math.pi
            out.append(frame({(sp, "side"): 0.03 * math.sin(t), (hd, "side"): 0.1 * math.sin(t - 0.8),
                              (tl, "up"): 0.25 * math.sin(t * 2), (sp, "up"): 0 if quad else 0.08 * math.sin(t)},
                             bob=0.01 * H * math.sin(t)))
    elif kind == "walk":
        n = int((1.0 if quad else 0.6) * FPS)
        for i in range(n):
            t = i / n * 2 * math.pi
            rot = {(hd, "side"): 0.08 * math.sin(2 * t), (tl, "up"): 0.3 * math.sin(t)}
            if quad:
                for k, ph in (("FL", 0), ("BR", 0), ("FR", math.pi), ("BL", math.pi)):
                    rot[(lg[k], "side")] = 0.45 * math.sin(t + ph)
            else:
                rot[(lg["L"], "side")] = 0.6 * math.sin(t)
                rot[(lg["R"], "side")] = -0.6 * math.sin(t)
                rot[(sp, "fwd")] = 0.12 * math.sin(t)
            out.append(frame(rot, bob=0.03 * H * abs(math.sin(t))))
    elif kind == "attack":
        n = int(0.9 * FPS)
        for i in range(n):
            t = i / n
            if t < 0.4:
                k = math.sin(t / 0.4 * math.pi / 2)
                head, spine, leg = 0.5 * k, 0.15 * k, 0.6 * k
            elif t < 0.55:
                k = (t - 0.4) / 0.15
                head, spine, leg = 0.5 - 1.2 * k, 0.15 - 0.35 * k, 0.6 - 1.0 * k
            else:
                k = (1 - (t - 0.55) / 0.45) ** 2
                head, spine, leg = -0.7 * k, -0.2 * k, -0.4 * k
            rot = {(hd, "side"): head, (sp, "side"): spine if quad else -spine * 2}
            if quad:
                rot[(lg["FL"], "side")] = leg
                rot[(lg["FR"], "side")] = leg
            out.append(frame(rot, bob=0.05 * H * max(0.0, spine) / 0.15))
    elif kind == "hit":
        n = int(0.4 * FPS)
        for i in range(n):
            k = math.sin(i / n * math.pi) * (1 - i / n * 0.3)
            out.append(frame({(hd, "side"): 0.35 * k, (sp, "side"): -0.1 * k if quad else 0.25 * k}))
    return out


def debug_frames(scene, mesh, ranges, work):
    try:
        scene.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = scene.render.resolution_y = 320
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.color = (0.35, 0.35, 0.35)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    sun.data.energy = 4
    sun.rotation_euler = (0.6, 0.2, 0.5)
    scene.collection.objects.link(sun)
    cd = bpy.data.cameras.new("dbg")
    cd.type = 'ORTHO'
    cam = bpy.data.objects.new("dbg", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    lo, hi = nc.bbox(nc.world_verts(mesh))
    c = (lo + hi) * 0.5
    r = (hi - lo).length * 0.5
    cd.ortho_scale = r * 2.6
    for clip, (t0, t1) in ranges.items():
        scene.frame_set(int(round((t0 + (t1 - t0) * 0.3) * FPS)) + 1)
        for view, d in (("side", (1, 0, 0.3)), ("front", (0, 1, 0.3))):
            d = Vector(d).normalized()
            cam.location = c + d * r * 4
            cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
            scene.render.filepath = os.path.join(work, f"creature_{clip}_{view}.png")
            bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(sun)


def main(a):
    size = json.loads(a.size or "{}")
    nc.reset_scene()
    scene = bpy.context.scene
    scene.render.fps = FPS
    files = clip_files(a.work)
    if a.legs:
        return main_auto(a, size, scene)
    base = files.get("idle") or files.get("walk")
    if not base:
        raise SystemExit("no anim_*.glb")
    objs, acts = import_raw(base)
    arm = next(o for o in objs if o.type == 'ARMATURE')
    # 骨の表示用の Icosphere などを除き、スキンの付いたメッシュだけ
    meshes = [o for o in objs if o.type == 'MESH' and (o.parent is arm or any(m.type == 'ARMATURE' for m in o.modifiers))]
    actions = {}
    base_name = "idle" if files.get("idle") == base else "walk"
    if acts:
        actions[base_name] = acts[0]
    for name, path in files.items():
        if path == base:
            continue
        o2, a2 = import_raw(path)
        if a2:
            actions[name] = a2[0]
        for o in o2:
            bpy.data.objects.remove(o, do_unlink=True)
    for o in list(bpy.data.objects):
        if o not in meshes and o is not arm:
            bpy.data.objects.remove(o, do_unlink=True)
    for m in meshes:
        m.animation_data_clear()
    log(f"actions: {sorted(actions)} bones: {len(arm.data.bones)}")

    # メッシュを 1 つにまとめる（頂点グループ・アーマチュアは保つ）
    for m in meshes:
        if m.parent is not arm:
            mw = m.matrix_world.copy()
            m.parent = arm
            m.matrix_world = mw
    mesh = nc.join_meshes(meshes)
    mesh.name = f"Creature_{a.id}"

    # 正面・寸法（structures_bake.fit と同じ規則。骨ごと）
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    arm.animation_data_clear()
    scene.frame_set(0)
    yaw = float(size.get("yaw", 0.0))
    nc.select_only([arm, mesh])
    arm.matrix_world = Matrix.Rotation(math.radians(yaw), 4, 'Z') @ arm.matrix_world
    bpy.context.view_layer.update()
    nc.apply_transforms([arm, mesh])
    pts = nc.world_verts(mesh)
    lo, hi = nc.bbox(pts)
    ext = hi - lo
    if "height" in size:
        s = size["height"] / max(ext.z, 1e-6)
    else:
        s = size.get("length", size.get("diameter", 1.0)) / max(ext.x, ext.y, 1e-6)
    c = (lo + hi) * 0.5
    arm.matrix_world = Matrix.Translation((-c.x * s, -c.y * s, -lo.z * s)) @ Matrix.Diagonal((s, s, s, 1.0)) @ arm.matrix_world
    bpy.context.view_layer.update()
    nc.apply_transforms([arm, mesh])
    mesh.parent = arm

    # 間引き（アーマチュアより前に評価させる）
    raw_tris = nc.tri_count(mesh)
    if raw_tris > a.faces * 1.05:
        nc.decimate(mesh, a.faces)
    nc.select_only([mesh])
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    except Exception:  # noqa: BLE001
        bpy.ops.object.shade_smooth()

    # 材質（structures_bake と同じ: ベースカラー + 発光マスク。赤チームの差し替えは使わない）
    img = sb.base_image(mesh)
    if img is None:
        raise SystemExit("no base color image")
    img.colorspace_settings.is_data = False
    if max(img.size) > a.texture:
        img.scale(a.texture, a.texture)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    emit, _red, _red_emit, glow = sb.team_textures(px)
    bimg = sb.np_image(f"Creature_{a.id}_base", px[..., :3])
    eimg = sb.np_image(f"Creature_{a.id}_emit", emit)
    for im in (bimg, eimg):
        im.pack()
    sb.make_material(mesh, a.id, bimg, eimg)

    # 動作を標本化して 1 本に並べる
    clips = {}
    for name in ORDER:
        src = next((actions[k] for k in CLIP_SOURCES[name] if k in actions), None)
        if src is not None:
            clips[name] = sample(arm, src, scene)
            # Tripo の四足の歩行は根元の骨の回転で体ごと反り返る → 根元は回さない（上下動は残す）
            if arm.data.bones[0].name in clips[name][0] and len(actions) == 1:
                rn = arm.data.bones[0].name
                for f in clips[name]:
                    loc, _q, sc = f[rn]
                    f[rn] = (loc, Quaternion(), sc)
        elif name != "walk":
            clips[name] = procedural(arm, name)
    # Tripo の人型プリセットは長い（chop は 6.6 s で振りは 15〜55 % の区間、idle は 15 s）→ 使う区間だけ残す
    for name, (f0, f1, cap) in {"attack": (0.15, 0.55, 3.0), "idle": (0.0, 1.0, 4.0), "hit": (0.0, 1.0, 1.2)}.items():
        fr = clips.get(name)
        if fr and name in [k for k, v in CLIP_SOURCES.items() if any(x in actions for x in v)]:
            i0 = int(len(fr) * f0)
            i1 = min(int(len(fr) * f1), i0 + int(cap * FPS))
            clips[name] = fr[i0:max(i1, i0 + 2)]
    for name, fr in clips.items():
        for f in fr:
            for b, (loc, q, sc) in f.items():
                f[b] = (loc * s, q, sc)
    finish(a, scene, arm, mesh, clips, yaw, raw_tris, glow)


def finish(a, scene, arm, mesh, clips, yaw, raw_tris, glow):
    act = bpy.data.actions.new(f"Creature_{a.id}")
    ad = arm.animation_data_create()
    ad.action = act
    ranges = {}
    cursor = 1
    for name in ORDER:
        fr = clips.get(name)
        if not fr:
            continue
        ranges[name] = [(cursor - 1) / FPS, (cursor - 1 + len(fr) - 1) / FPS]
        for i, f in enumerate(fr):
            for pb in arm.pose.bones:
                loc, q, sc = f.get(pb.name, (Vector(), Quaternion(), Vector((1, 1, 1))))
                pb.location, pb.rotation_quaternion, pb.scale = loc, q, sc
                pb.keyframe_insert("location", frame=cursor + i)
                pb.keyframe_insert("rotation_quaternion", frame=cursor + i)
                pb.keyframe_insert("scale", frame=cursor + i)
        cursor += len(fr)
    scene.frame_start = 1
    scene.frame_end = cursor - 1
    log(f"clips {json.dumps(ranges)}")

    # 確認用: 各動作の中ほどの姿勢を横（+X）・正面（+Y）から描く（Blender 空間。work/creature_<clip>_<view>.png）
    debug_frames(scene, mesh, ranges, a.work)
    os.makedirs(a.out, exist_ok=True)
    out = os.path.join(a.out, f"Creature_{a.id}.usdz")
    scene.frame_set(1)
    textures = nc.export_usdz([arm, mesh], out, skinned=True, texture_size=a.texture, animated=True)
    lo, hi = nc.bbox(nc.world_verts(mesh))
    meta = {"id": a.id, "fps": FPS, "clips": ranges, "triangles": nc.tri_count(mesh), "rawTriangles": raw_tris,
            "bones": len(arm.data.bones), "size": [round(hi.x - lo.x, 3), round(hi.z - lo.z, 3), round(hi.y - lo.y, 3)],
            "yaw": yaw, "glowFraction": round(glow, 4)}
    with open(os.path.join(a.out, f"Creature_{a.id}.json"), "w") as f:
        json.dump({"fps": FPS, "clips": ranges}, f, indent=2)
        f.write("\n")
    meta["textures"] = textures
    meta["bytes"] = os.path.getsize(out)
    with open(os.path.join(a.work, "creature.json"), "w") as f:
        json.dump(meta, f, indent=2)
    log(json.dumps(meta))




def main_auto(a, size, scene):
    mesh = sb.load_model(os.path.join(a.work, "model.glb"), f"Creature_{a.id}")
    # load_model は場面を作り直す
    scene = bpy.context.scene
    scene.render.fps = FPS
    raw_tris = nc.tri_count(mesh)
    yaw = float(size.get("yaw", 0.0))
    sb.fit(mesh, size, yaw, "base")
    if raw_tris > a.faces * 1.05:
        nc.decimate(mesh, a.faces)
    nc.select_only([mesh])
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    except Exception:  # noqa: BLE001
        bpy.ops.object.shade_smooth()
    # 材質（structures_bake と同じ: ベースカラー + 発光マスク。赤チームの差し替えは使わない）
    img = sb.base_image(mesh)
    if img is None:
        raise SystemExit("no base color image")
    img.colorspace_settings.is_data = False
    if max(img.size) > a.texture:
        img.scale(a.texture, a.texture)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    emit, _red, _red_emit, glow = sb.team_textures(px)
    bimg = sb.np_image(f"Creature_{a.id}_base", px[..., :3])
    eimg = sb.np_image(f"Creature_{a.id}_emit", emit)
    for im in (bimg, eimg):
        im.pack()
    sb.make_material(mesh, a.id, bimg, eimg)

    arm, roles, H = autorig(mesh, a.legs)
    log(f"autorig {json.dumps(roles)}")
    clips = {name: procedural_auto(arm, roles, name, H) for name in ORDER}
    finish(a, scene, arm, mesh, clips, yaw, raw_tris, glow)


if __name__ == "__main__":
    main(parse())
