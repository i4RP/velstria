# 担当: hero-motion。モーションクリップ（docs/HERO_MOTION.md）をヒーローのスキンメッシュに実行時と同じ計算で載せ、
# 等間隔のフレームを並べた 1 枚の PNG（コンタクトシート）にする（Blender 5.2 headless）。クリップの目視確認用。
# 使い方（VELSTRIA/ で）:
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
#     --python tools/blender/preview_clip.py -- --clips App/Resources/Heroes/HeroMotionClips.json \
#     --clip run_basic[,walk_basic|all|@rest] --hero H001[,H002|App/Resources/Heroes/Hero_H001.usdz] [--frames 8] \
#     [--out build/heroref/preview/{hero}_{clip}.png] [--view 34|front|side] [--tile 320x400] [--cols 4]
#     [--check-rest] [--report build/heroref/preview/report.json]
#   --hero は ID（App/Resources/Heroes/Hero_<ID>.usdz）か USDZ のパス。--clip all は JSON の全クリップ。
#   --out の {hero} {clip} を置き換える（複数のシートを作るときは必須。既定は build/heroref/preview/{hero}_{clip}.png）。
#   @rest は表示するヒーロー自身のレストから作ったクリップ（extract_clips.py の rest と同じ計算）。
#   --check-rest: 解いた姿勢の四肢の向きがヒーロー自身のレストと一致する（0.05° 以内）ことを確かめる（レストのクリップ用。
#   元リグ = このヒーローの rest クリップ、または @rest）。外れたら終了コード 1。
#   1 プロセスで複数のヒーロー × クリップを撮れる（Blender の起動が 1 回で済む。24 体 × 1 クリップ × 8 フレームで約 20 秒）。
#   レンダラは Workbench（テクスチャ色・スタジオ照明・影）、地面は 20 cm 角の市松、各コマの左上にヒーロー・クリップ・フレーム。
#
# 実行時と同じにすること:
#   - ヒーロー空間 = USD の座標（Y 上・正面 -Z）。Blender の USD 取り込みは Y 上のまま置く（Z 上に変える版でも腰 → 頭の向きで判別）。
#   - 区間回転を表示するリグの C'・レストで解く（clip_math.Rig.solve = HeroSkeletonPoser.solve。骨の役割は Swift の
#     HeroJointRole.normalize と同じ規則で、Meshy の骨名の読み替えはしない = 実行時もしない）。
#   - 腰: root × 表示するリグの脚の長さ、水平成分はさらに rootXZ 倍。
# シートごとの検査（レポートと標準出力の JSON）:
#   solveDegrees  上腕・前腕・腿・脛の向き（次の関節へ）と Q·(0,-1,0) の差（C' の「ほぼ平行なら単位」で最大 0.81°）
#   poseError     Blender に書いたポーズを読み戻した骨の位置（mm）・回転（度）と解いた値の差（書き込みの式の確認。
#                 0.5 mm / 0.05° を超えたら失敗 = 終了コード 1）
#   groundMin/Max 各フレームのメッシュの最下点の高さ（m）の最小・最大（足が地面 y = 0 に着いているかの目安）

import argparse
import json
import math
import os
import shutil
import sys
import tempfile
import time

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clip_math as cm  # noqa: E402
import norm_common as nc  # noqa: E402

HEROES_DIR = "App/Resources/Heroes"
REST_TOL_DEG = 0.05
POSE_TOL_MM = 0.5
POSE_TOL_DEG = 0.05
BG = (0.86, 0.87, 0.89)
GROUND = ((0.93, 0.92, 0.88), (0.80, 0.79, 0.75))   # 地面の市松（20 cm 角。足の滑り・接地の目安）
GROUND_SIZE = 1.6
VIEWS = {
    # カメラの向き（ヒーロー空間、注視点 → カメラ）
    "34": Vector((0.70, 0.22, -0.70)),     # 右手側の斜め前（正面 -Z・右手 +X）
    "front": Vector((0.0, 0.12, -1.0)),
    "side": Vector((1.0, 0.06, 0.0)),      # 右手側の真横（正面が画面の右）
    "top": Vector((0.0, 1.0, 0.55)),       # 後ろ上から見下ろす（正面 = 画面の上）
    "fronttop": Vector((0.0, 0.9, -1.0)),  # 前上から見下ろす（正面へ打つ = 手前へ）
    "overhead": Vector((0.0, 1.0, 0.03)),  # 真上（正面 = 画面の上、右手 = 画面の右）
}


def log(msg):
    print(f"[preview] {msg}", flush=True)


def parse():
    p = argparse.ArgumentParser(prog="preview_clip.py")
    p.add_argument("--clips", default=os.path.join(HEROES_DIR, "HeroMotionClips.json"))
    p.add_argument("--clip", required=True)
    p.add_argument("--hero", required=True)
    p.add_argument("--frames", type=int, default=8)
    p.add_argument("--weapon", default="", help="R / L / R,L: 手の区間に武器の代わりの棒を付ける（握りの親指側 = 区間回転で (0,0,-1)。右は赤 0.9 m、左は青 0.6 m）")
    p.add_argument("--at", default="", help="描くフレームを指定（出力フレームか start / end / impact / impact±N のカンマ区切り。--frames より優先）")
    p.add_argument("--out", default="build/heroref/preview/{hero}_{clip}.png")
    p.add_argument("--view", default="34", choices=sorted(VIEWS))
    p.add_argument("--tile", default="320x400")
    p.add_argument("--cols", type=int, default=0)
    p.add_argument("--check-rest", action="store_true")
    p.add_argument("--report", default="")
    return p.parse_args(nc.script_args())


def hero_path(h):
    if h.lower().endswith((".usdz", ".usd", ".usdc", ".usda")):
        return h
    return os.path.join(HEROES_DIR, f"Hero_{h}.usdz")


def hero_id(path):
    b = os.path.splitext(os.path.basename(path))[0]
    return b[5:] if b.startswith("Hero_") else b


# MARK: - ヒーローの取り込み

def load_hero(path):
    """シーンを空にして USDZ を取り込む。(Rig, メッシュの配列, ヒーロー空間の高さ, 警告)。"""
    if not os.path.isfile(path):
        raise SystemExit(f"hero not found: {path}")
    nc.reset_scene()
    bpy.ops.wm.usd_import(filepath=path)
    arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
    if not arms:
        raise SystemExit(f"{path}: no skeleton")
    arm = max(arms, key=lambda a: len(a.data.bones))
    meshes = [o for o in bpy.data.objects if o.type == 'MESH'
              and any(m.type == 'ARMATURE' and m.object == arm for m in o.modifiers)]
    if not meshes:
        raise SystemExit(f"{path}: no skinned mesh")
    A = arm.matrix_world
    pos = {}
    for b in arm.data.bones:
        pos.setdefault(cm.runtime_role(b.name), A @ b.head_local)
    if "hips" not in pos or "head" not in pos:
        raise SystemExit(f"{path}: hips/head joints not found")
    up = cm.up_axis(pos["head"], pos["hips"])
    # ヒーロー空間 = USD の座標。取り込みが Y 上のままなら単位、Z 上へ回していれば norm_common.BLENDER_TO_USD
    if up == Vector((0, 1, 0)):
        M = Matrix.Identity(3)
    elif up == Vector((0, 0, 1)):
        M = nc.BLENDER_TO_USD.to_3x3()
    else:
        raise SystemExit(f"{path}: unexpected up axis {tuple(up)} after import")
    warnings = []
    fwd, info, errs = cm.detect_facing(pos, up)
    off = cm.angle_deg(M @ fwd, Vector((0, 0, -1)))
    if errs or off > 1.0:
        warnings.append(f"facing from the bones is {off:.1f}° off -Z ({info.get('source')}; {'; '.join(errs)}); "
                        f"the runtime uses the USD axes as they are")
    rig = cm.Rig(arm, M)
    missing = [s for s in rig.missing_segments() if s not in ("footR", "footL")]
    if missing:
        raise SystemExit(f"{path}: joints for segments {missing} not found")
    if not rig.leg_length or rig.leg_length <= 1e-6:
        raise SystemExit(f"{path}: cannot measure the leg length")
    for o in bpy.data.objects:
        if o.type == 'MESH' and o not in meshes:
            o.hide_render = True
    height = max(lowest_highest(meshes, M)[1], 0.5)
    return rig, meshes, height, warnings


def lowest_highest(meshes, M):
    """評価後のメッシュのヒーロー空間の最低・最高の高さ。"""
    dg = bpy.context.evaluated_depsgraph_get()
    lo, hi = math.inf, -math.inf
    row = np.array(M[1], dtype=np.float64)   # ヒーロー空間の y を取り出す行
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        n = len(me.vertices)
        if n:
            co = np.empty(n * 3, dtype=np.float32)
            me.vertices.foreach_get("co", co)
            co = co.reshape(n, 3).astype(np.float64)
            mw = np.array(ev.matrix_world, dtype=np.float64)
            w = co @ mw[:3, :3].T + mw[:3, 3]
            y = w @ row
            lo, hi = min(lo, float(y.min())), max(hi, float(y.max()))
        ev.to_mesh_clear()
    return lo, hi


# MARK: - 撮影の準備

def hero_to_world(rig, m4):
    """ヒーロー空間の 4x4 → ワールド。"""
    return rig.Minv.to_4x4() @ m4


def setup_scene(rig, height, view, tile):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.render.resolution_x, sc.render.resolution_y = tile
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    sh = sc.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'TEXTURE'
    sh.show_shadows = True
    sh.shadow_intensity = 0.35
    sh.show_cavity = False
    sc.display.light_direction = (0.35, -0.45, 0.85)
    sc.display_settings.display_device = 'sRGB'
    sc.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new("bg")
    world.color = BG
    sc.world = world

    # 地面（ヒーロー空間の y = 0）。Workbench の TEXTURE 表示は画像の無い素材を暗い灰色で描くので、市松の画像を貼る
    bpy.ops.mesh.primitive_plane_add(size=GROUND_SIZE)
    ground = bpy.context.active_object
    ground.name = "Ground"
    ground.matrix_world = hero_to_world(rig, Matrix.Rotation(-math.pi / 2, 4, 'X'))
    cells = round(GROUND_SIZE / 0.2)
    ij = np.add.outer(np.arange(cells), np.arange(cells)) % 2
    px = np.empty((cells, cells, 4), dtype=np.float32)
    px[..., :3] = np.where(ij[..., None] == 0, GROUND[0], GROUND[1])
    px[..., 3] = 1.0
    img = bpy.data.images.new("GroundChecker", cells, cells, alpha=False)
    img.colorspace_settings.name = 'Non-Color'
    img.pixels.foreach_set(px.ravel())
    mat = bpy.data.materials.new("GroundMat")
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = 'Closest'
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mat.node_tree.nodes.active = tex
    ground.data.materials.append(mat)

    # 正射影カメラ（注視点は体の中ほど）
    d = VIEWS[view].normalized()
    up = Vector((0, 1, 0))
    x = up.cross(d).normalized()
    y = d.cross(x).normalized()
    target = Vector((0, height * 0.48, 0))
    loc = target + d * 6.0
    m = Matrix((
        (x.x, y.x, d.x, loc.x),
        (x.y, y.y, d.y, loc.y),
        (x.z, y.z, d.z, loc.z),
        (0, 0, 0, 1)))
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.sensor_fit = 'VERTICAL'
    cam_data.ortho_scale = height * 1.28
    cam_data.clip_start = 0.1
    cam_data.clip_end = 20.0
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    cam.matrix_world = hero_to_world(rig, m)
    sc.camera = cam

    # ラベル（カメラの子、左上）
    txt = bpy.data.curves.new("Label", 'FONT')
    txt.size = cam_data.ortho_scale * 0.045
    label = bpy.data.objects.new("Label", txt)
    sc.collection.objects.link(label)
    label.parent = cam
    aspect = tile[0] / tile[1]
    half_h = cam_data.ortho_scale / 2
    half_w = half_h * aspect
    label.location = (-half_w + txt.size * 0.4, half_h - txt.size * 1.3, -1.0)
    lmat = bpy.data.materials.new("LabelMat")
    lmat.diffuse_color = (0.1, 0.1, 0.12, 1.0)
    txt.materials.append(lmat)
    return label


# MARK: - クリップ

def load_clips(path):
    with open(path) as f:
        data = json.load(f)
    segs = data.get("segments")
    if segs != cm.SEGMENTS:
        raise SystemExit(f"{path}: segments {segs} differ from {cm.SEGMENTS}")
    return {c["name"]: c for c in data.get("clips", [])}


def rest_clip(rig):
    """表示するヒーロー自身のレストのクリップ（extract_clips.py の rest と同じ: ΔR = 単位 → Q = C⁻¹、丸め 4 桁）。"""
    qs, root = rig.extract([Quaternion()] * len(rig.names), [p.copy() for p in rig.P0])
    rot = []
    for q in qs:
        q = q.normalized()
        if q.w < 0:
            q = cm.neg(q)
        rot += [round(q.x, 4), round(q.y, 4), round(q.z, 4), round(q.w, 4)]
    return {"name": "rest_self", "source": "self:rest", "frames": 1, "loop": False, "rootXZ": 0.0, "events": {},
            "rot": rot, "root": [0.0, 0.0, 0.0]}


def sample_frames(clip, count):
    n = clip["frames"]
    if n <= 1:
        return [0.0]
    if clip.get("loop"):
        return [i * n / count for i in range(count)]
    if count <= 1:
        return [0.0]
    return [i * (n - 1) / (count - 1) for i in range(count)]


STICKS = {"R": ("righthand", "handR", 0.9, (0.85, 0.1, 0.1, 1.0)), "L": ("lefthand", "handL", 0.6, (0.1, 0.3, 0.9, 1.0))}


def make_sticks(sides):
    """武器の代わりの棒（向きの確認用。実行時の weaponGrip の既定 = 区間回転で正面 -Z へ伸びる向き）。"""
    out = []
    for side in [x for x in sides.split(",") if x]:
        role, seg, length, color = STICKS[side]
        bpy.ops.mesh.primitive_cylinder_add(radius=0.018, depth=length, vertices=8)
        ob = bpy.context.active_object
        ob.name = f"stick{side}"
        mat = bpy.data.materials.new(f"stick{side}")
        mat.diffuse_color = color
        ob.data.materials.append(mat)
        out.append((ob, role, seg, length))
    return out


def place_sticks(rig, sticks, qs, P):
    for ob, role, seg, length in sticks:
        j = rig.index.get(role)
        if j is None:
            continue
        d = (qs[cm.SEG_INDEX[seg]] @ Vector((0.0, 0.0, -1.0))).normalized()
        rot = Vector((0.0, 0.0, 1.0)).rotation_difference(d)
        m = Matrix.LocRotScale(P[j] + d * (length / 2), rot, Vector((1, 1, 1)))
        ob.matrix_world = hero_to_world(rig, m)


def frames_at(clip, spec):
    """--at の指定を出力フレームの列にする（impact はクリップの events.impact）。"""
    n = clip["frames"]
    imp = clip.get("events", {}).get("impact")
    out = []
    for tok in [t.strip() for t in spec.split(",") if t.strip()]:
        if tok == "start":
            f = 0.0
        elif tok == "end":
            f = float(n - 1)
        elif tok.startswith("impact"):
            if imp is None:
                continue
            f = float(imp) + (float(tok[6:]) if len(tok) > 6 else 0.0)
        else:
            f = float(tok)
        out.append(min(max(f, 0.0), float(n - 1)))
    return out or [0.0]


def render_sheet(rig, meshes, clip, frames, out, label, tile, cols, check_rest, hero, sticks=()):
    """1 枚のシートを書く。検査の dict を返す。"""
    sc = bpy.context.scene
    L = rig.leg_length
    kxz = float(clip.get("rootXZ", 0.0))
    rest_dirs = rig.limb_dirs([Quaternion()] * len(rig.names), rig.P0)
    tmp = tempfile.mkdtemp(prefix="velstria_preview_")
    stats = {"solveDegrees": 0.0, "poseErrorMm": 0.0, "poseErrorDegrees": 0.0, "groundMin": math.inf,
             "groundMax": -math.inf, "groundPerFrame": [], "restDegrees": None}
    files = []
    rest_err = 0.0
    for i, f in enumerate(frames):
        qs, root = cm.interp_clip(clip, f)
        offset = Vector((root.x * kxz, root.y, root.z * kxz)) * L
        dR, P = rig.solve(qs, offset)
        rig.apply_pose(dR, P)
        place_sticks(rig, sticks, qs, P)
        bpy.context.view_layer.update()
        # 書いたポーズの読み戻し
        dg = bpy.context.evaluated_depsgraph_get()
        ev = rig.arm.evaluated_get(dg)
        dR2, P2 = rig.sample(ev.pose.bones, ev.matrix_world)
        for j in range(len(rig.names)):
            stats["poseErrorMm"] = max(stats["poseErrorMm"], (P2[j] - P[j]).length * 1000.0)
            stats["poseErrorDegrees"] = max(stats["poseErrorDegrees"], cm.quat_angle_deg(dR2[j], dR[j]))
        # 解いた四肢の向き = Q·下
        dirs = rig.limb_dirs(dR, P)
        for seg in ("armR", "foreArmR", "armL", "foreArmL", "thighR", "shinR", "thighL", "shinL"):
            if seg in dirs:
                stats["solveDegrees"] = max(stats["solveDegrees"],
                                            cm.angle_deg(dirs[seg], qs[cm.SEG_INDEX[seg]] @ cm.DOWN))
        if check_rest:
            for k, v in dirs.items():
                rest_err = max(rest_err, cm.angle_deg(v, rest_dirs[k]))
        lo, _ = lowest_highest(meshes, rig.M)
        stats["groundMin"] = min(stats["groundMin"], lo)
        stats["groundMax"] = max(stats["groundMax"], lo)
        stats["groundPerFrame"].append(round(lo, 4) + 0.0)
        label.data.body = f"{hero} {clip['name']}  f{f:.1f}/{clip['frames']}"
        p = os.path.join(tmp, f"f{i:03d}.png")
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        files.append(p)
    if check_rest:
        stats["restDegrees"] = rest_err
    tile_images(files, out, tile, cols)
    shutil.rmtree(tmp, ignore_errors=True)
    for k in ("solveDegrees", "poseErrorMm", "poseErrorDegrees", "groundMin", "groundMax"):
        stats[k] = round(stats[k], 4) + 0.0   # -0.0 を 0.0 に
    if stats["restDegrees"] is not None:
        stats["restDegrees"] = round(stats["restDegrees"], 4)
    return stats


def tile_images(files, out, tile, cols):
    """レンダリングした PNG を cols 列に並べる（Blender の画像 API + numpy。行の間に 2px の区切り）。"""
    w, h = tile
    n = len(files)
    cols = max(1, min(cols, n))
    rows = (n + cols - 1) // cols
    gap = 2
    W = cols * w + (cols - 1) * gap
    H = rows * h + (rows - 1) * gap
    canvas = np.full((H, W, 4), 0.35, dtype=np.float32)
    canvas[..., 3] = 1.0
    for i, p in enumerate(files):
        img = bpy.data.images.load(p)
        px = np.empty(len(img.pixels), dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(img.size[1], img.size[0], img.channels)
        if img.channels == 3:
            px = np.concatenate([px, np.ones(px.shape[:2] + (1,), dtype=np.float32)], axis=2)
        r, c = divmod(i, cols)
        y0 = H - (r + 1) * h - r * gap     # Blender の画素は下の行から
        x0 = c * (w + gap)
        canvas[y0:y0 + h, x0:x0 + w, :] = px[:h, :w, :4]
        bpy.data.images.remove(img)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    sheet = bpy.data.images.new("sheet", W, H, alpha=False)
    sheet.pixels.foreach_set(canvas.ravel())
    sheet.filepath_raw = os.path.abspath(out)
    sheet.file_format = 'PNG'
    sheet.save()
    bpy.data.images.remove(sheet)


def main(a):
    t0 = time.time()
    tile = tuple(int(v) for v in a.tile.lower().split("x"))
    if len(tile) != 2 or min(tile) < 32:
        raise SystemExit("--tile must be WxH")
    clips = load_clips(a.clips) if a.clip != "@rest" else {}
    names = list(clips) if a.clip == "all" else [s for s in a.clip.split(",") if s]
    unknown = [n for n in names if n != "@rest" and n not in clips]
    if unknown:
        raise SystemExit(f"clips not found in {a.clips}: {unknown} (have {list(clips)})")
    heroes = [hero_path(h) for h in a.hero.split(",") if h]
    if len(heroes) * len(names) > 1 and "{" not in a.out:
        raise SystemExit("--out needs {hero} / {clip} placeholders for more than one sheet")
    cols = a.cols or min(4, max(1, a.frames))
    results, failed = [], []
    for hp in heroes:
        hid = hero_id(hp)
        rig, meshes, height, warnings = load_hero(hp)
        for w in warnings:
            log(f"WARNING {hid}: {w}")
        label = setup_scene(rig, height, a.view, tile)
        sticks = make_sticks(a.weapon) if a.weapon else []
        for name in names:
            clip = rest_clip(rig) if name == "@rest" else clips[name]
            frames = frames_at(clip, a.at) if a.at else sample_frames(clip, a.frames)
            out = a.out.format(hero=hid, clip=clip["name"])
            t1 = time.time()
            stats = render_sheet(rig, meshes, clip, frames, out, label, tile, cols, a.check_rest, hid, sticks)
            ok = stats["poseErrorMm"] <= POSE_TOL_MM and stats["poseErrorDegrees"] <= POSE_TOL_DEG
            if a.check_rest and stats["restDegrees"] > REST_TOL_DEG:
                ok = False
            res = {"hero": hid, "clip": clip["name"], "out": os.path.abspath(out), "frames": [round(f, 2) for f in frames],
                   "legLength": round(rig.leg_length, 4), "height": round(height, 4), "ok": ok,
                   "seconds": round(time.time() - t1, 2), "warnings": warnings, **stats}
            results.append(res)
            log(f"{hid} {clip['name']}: {out} solve {stats['solveDegrees']}° pose {stats['poseErrorMm']}mm/"
                f"{stats['poseErrorDegrees']}° ground {stats['groundMin']}..{stats['groundMax']}"
                + (f" rest {stats['restDegrees']}°" if a.check_rest else "") + f" ({res['seconds']}s)"
                + ("" if ok else "  FAILED"))
            if not ok:
                failed.append(f"{hid}/{clip['name']}")
    summary = {"results": results, "failed": failed, "seconds": round(time.time() - t0, 2)}
    if a.report:
        os.makedirs(os.path.dirname(os.path.abspath(a.report)), exist_ok=True)
        with open(a.report, "w") as f:
            json.dump(summary, f, ensure_ascii=False, indent=2)
    print(json.dumps({"failed": failed, "sheets": [r["out"] for r in results]}, ensure_ascii=False), flush=True)
    if failed:
        raise SystemExit(f"preview checks failed: {failed}")


if __name__ == "__main__":
    main(parse())
