# 担当: battle-renderer（塔・Star Core の部品分けモデル）。Blender 5.2 headless で実行する:
#   Blender -b --factory-startup --python tools/structures/tower_parts.py -- --id tower_outer \
#       --glb build/structures/tower_outer/model.glb --out App/Resources/Structures --work build/structures/tower_outer \
#       --faces 5200 --budget 6000 --size '{"height": 5.4, "yaw": -90}' --parts '{"cuts": [...], "rules": [...]}'
# tools/structures/structures.mjs parts から呼ぶ（structures.json に parts がある物は bake もこちら）。
#
# 1. structures_bake.py と同じく GLB を 1 つのメッシュにし、yaw・寸法で正規化する（原点 = 足跡の中心、最も低い点が 0）
# 2. 部品の境目の水平面（parts.cuts の z。radius があれば重心が中心からその距離までの面だけ切る = 台座の角柱・控え壁は
#    切らない）で切り、切り口の辺で上下を切り離す
# 3. つながった塊ごとに parts.rules（重心の高さ・重心の中心からの距離・発光の割合・上端の高さ。上から順に最初に合う物）で
#    部品を決める。部品名は TowerTimeline.swift の part_plinth / part_lower / part_upper / part_crown / part_crystal
# 4. 部品ごとに切り口の穴を平らな面で塞ぐ（折れた石が中まで詰まって見える）。蓋の UV はテクスチャの石の色の所を指す
# 5. 材質は 1 つ（ベースカラー + 発光。赤チームは色相を付け替えた別テクスチャ）を全部品で共有して USDZ へ。
#    部品は /root/<部品名> の Mesh（原点は全部品で共通 = 塔の足元の中心。部品の原点は動かさない）
# 6. 確認用: work に組んだ姿・分解図（部品を縦に離す。斜め上と斜め下から）・ゲームの角度・赤チームの画像と、
#    --json（部品ごとの範囲・三角形数。USD 空間 = Y 上・+Z がゲームのカメラ側）を書く
import argparse
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import structures_bake as sb  # noqa: E402
import norm_common as nc  # noqa: E402  (structures_bake が tools/blender を path に足す)

PARTS = ["part_plinth", "part_lower", "part_upper", "part_crown", "part_crystal"]
# 分解図で縦に離す順（下から）
EXPLODE_ORDER = PARTS
# 赤チームの色の既定。光る所（結晶・紋様）は紅寄りの赤、光らない所（布・七宝）は深い紅（#7a1f2a 付近）。
# save_jpeg（save_render）の表示変換で赤は橙側へ約 8° ずれるので、光る所は 346° で書いて jpg で 354° 前後
# （以前の 9° は jpg で 12° になり、ゲーム内の発光で橙に見えた）。赤のテクスチャだけ作り直す時は red_textures.py
TEAM_DEFAULT = {"hue": [165.0, 300.0], "minSat": 0.14, "redHue": 353.0, "redGlowHue": 346.0}
EPS = 1e-4


def log(msg):
    print(f"[parts] {msg}", flush=True)


def parse():
    p = argparse.ArgumentParser(prog="tower_parts.py")
    p.add_argument("--id", required=True)
    p.add_argument("--glb", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--work", required=True)
    p.add_argument("--faces", type=int, default=5000)
    p.add_argument("--budget", type=int, default=6000)
    p.add_argument("--size", default="{}")
    p.add_argument("--parts", required=True)
    p.add_argument("--texture", type=int, default=1024)
    p.add_argument("--json", default="")
    return p.parse_args(nc.script_args())


# MARK: - テクスチャ

def team_textures(px, team):
    """px: (h, w, 4) の 0〜1。(発光, 赤のベース, 赤の発光, 発光の重み (h, w)) を返す。
    発光の判定は structures_bake.team_textures と同じ。赤は光る所と光らない所で色相を分ける。"""
    t = dict(TEAM_DEFAULT, **(team or {}))
    rgb = px[..., :3]
    h, s, v = sb.rgb_to_hsv(rgb)
    in_team = (h >= t["hue"][0]) & (h <= t["hue"][1])
    glow = in_team * np.maximum(sb.smoothstep(0.5, 0.75, v) * sb.smoothstep(0.3, 0.55, s),
                                sb.smoothstep(0.8, 0.95, v) * sb.smoothstep(0.08, 0.2, s))
    emit = rgb * glow[..., None]
    h2 = t["redHue"] + (t["redGlowHue"] - t["redHue"]) * glow
    red = sb.hsv_to_rgb(np.where(in_team, h2, h), s, v)
    # 彩度の低い所（灰緑の石）は元の色のまま
    w = (in_team * sb.smoothstep(t["minSat"] * 0.5, t["minSat"] * 1.5, s))[..., None]
    red = rgb * (1 - w) + red * w
    red_emit = red * glow[..., None]
    return emit, red, red_emit, glow


def stone_window(px, glow, size=48, dark=False):
    """蓋に使う石の色の四角（UV の中心と半幅）。彩度が低く中くらいの明るさで光らない画素だけの size 四方のうち、
    平均の色が石全体の中央値に最も近い所。dark は竪穴の口（暗い所）。"""
    rgb = px[..., :3]
    _, s, v = sb.rgb_to_hsv(rgb)
    ok = (v < 0.14) & (glow < 0.01) if dark else (s < 0.3) & (v > 0.22) & (v < 0.8) & (glow < 0.01)
    hgt, wid = ok.shape
    med = np.median(rgb[ok], axis=0) if ok.any() else np.array([0.4, 0.42, 0.38])
    while size >= 8:
        ii = np.pad(ok.astype(np.int64).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
        k = size
        cnt = ii[k:, k:] - ii[:-k, k:] - ii[k:, :-k] + ii[:-k, :-k]
        ys, xs = np.nonzero(cnt == k * k)
        if len(ys):
            best, bd = None, 1e9
            step = max(1, len(ys) // 4000)
            for y, x in zip(ys[::step], xs[::step]):
                mean = rgb[y:y + k, x:x + k].reshape(-1, 3).mean(0)
                # 竪穴の口は最も暗い所、石は中央値に最も近い所
                d = float(mean.sum()) if dark else float(np.abs(mean - med).sum())
                if d < bd:
                    best, bd = (y, x), d
            y, x = best
            return {"u": (x + k / 2) / wid, "v": (y + k / 2) / hgt, "half": k / 2 / max(wid, hgt), "px": k,
                    "rgb": [round(float(c), 3) for c in rgb[y:y + k, x:x + k].reshape(-1, 3).mean(0)]}
        size //= 2
    raise SystemExit("no stone-coloured window in the texture")


def face_glow(bm, glow):
    """面ごとの発光の重み（UV の重心の画素）。"""
    hgt, wid = glow.shape
    uv = bm.loops.layers.uv.active
    out = np.zeros(len(bm.faces), dtype=np.float32)
    bm.faces.ensure_lookup_table()
    for f in bm.faces:
        u = v = 0.0
        for lp in f.loops:
            u += lp[uv].uv.x
            v += lp[uv].uv.y
        n = len(f.loops)
        x = min(wid - 1, max(0, int((u / n % 1.0) * wid)))
        y = min(hgt - 1, max(0, int((v / n % 1.0) * hgt)))
        out[f.index] = glow[y, x]
    return out


# MARK: - 切断・部品分け

def crossing(f, z):
    zs = [v.co.z for v in f.verts]
    return min(zs) < z - EPS and max(zs) > z + EPS


def cut(bm, z, radius):
    """高さ z の水平面で切る（まだ切り離さない）。切った面の数を返す。"""
    faces = [f for f in bm.faces if crossing(f, z) and (radius is None or f.calc_center_median().xy.length < radius)]
    if not faces:
        return 0
    verts = {v for f in faces for v in f.verts}
    edges = {e for f in faces for e in f.edges}
    bmesh.ops.bisect_plane(bm, geom=list(verts) + list(edges) + faces, dist=EPS * 0.1,
                           plane_co=(0.0, 0.0, z), plane_no=(0.0, 0.0, 1.0))
    return len(faces)


def seam_edges(bm, zs):
    """切り口の辺（両端が切断面の上にあり、面の上と下に面を持つ辺）。"""
    out = set()
    for e in bm.edges:
        for z in zs:
            if all(abs(v.co.z - z) < EPS for v in e.verts):
                sides = {1 if f.calc_center_median().z > z else -1 for f in e.link_faces}
                if sides == {1, -1}:
                    out.add(e)
                break
    return out


def components(bm, seams):
    """つながった塊（切り口の辺は越えない）。"""
    bm.faces.ensure_lookup_table()
    comp = np.full(len(bm.faces), -1, dtype=np.int64)
    n = 0
    for f in bm.faces:
        if comp[f.index] >= 0:
            continue
        stack = [f]
        comp[f.index] = n
        while stack:
            g = stack.pop()
            for e in g.edges:
                if e in seams:
                    continue
                for h in e.link_faces:
                    if comp[h.index] < 0:
                        comp[h.index] = n
                        stack.append(h)
        n += 1
    return comp, n


def classify(stats, rules):
    """塊の統計 → 部品名（rules の上から最初に合う物）。"""
    for r in rules:
        if "minZ" in r and stats["cz"] < r["minZ"]:
            continue
        if "maxZ" in r and stats["cz"] >= r["maxZ"]:
            continue
        if "maxRadius" in r and stats["radius"] >= r["maxRadius"]:
            continue
        if "minRadius" in r and stats["radius"] < r["minRadius"]:
            continue
        if "minGlow" in r and stats["glow"] < r["minGlow"]:
            continue
        if "maxGlow" in r and stats["glow"] >= r["maxGlow"]:
            continue
        if "minTop" in r and stats["top"] < r["minTop"]:
            continue
        if "maxTop" in r and stats["top"] >= r["maxTop"]:
            continue
        return r["part"]
    return "part_plinth"


def edge_groups(edges):
    """辺の集まり → 頂点でつながる組（[辺], 閉じているか, 端点）。"""
    left = set(edges)
    out = []
    while left:
        e0 = left.pop()
        group = [e0]
        stack = list(e0.verts)
        seen = set(e0.verts)
        while stack:
            v = stack.pop()
            for e in v.link_edges:
                if e in left:
                    left.discard(e)
                    group.append(e)
                    for w in e.verts:
                        if w not in seen:
                            seen.add(w)
                            stack.append(w)
        deg = {}
        for e in group:
            for v in e.verts:
                deg[v] = deg.get(v, 0) + 1
        ends = [v for v, d in deg.items() if d % 2 == 1]
        out.append((group, not ends, ends))
    return out


def closable(group, a, b):
    """1 本の開いた鎖を端どうしの直線で閉じてよいか（U 字・L 字の断面 = 裏の面が無い殻。
    ほぼ直線 = 片面の布は閉じない）。鎖の囲む面積（XY）で判断する。"""
    nxt = {}
    for e in group:
        v0, v1 = e.verts
        nxt.setdefault(v0, []).append(v1)
        nxt.setdefault(v1, []).append(v0)
    order, prev, cur = [a], None, a
    while cur is not b and len(order) <= len(group) + 1:
        step = [w for w in nxt.get(cur, []) if w is not prev]
        if not step:
            return False
        prev, cur = cur, step[0]
        order.append(cur)
    area = 0.5 * abs(sum(p.co.x * q.co.y - q.co.x * p.co.y for p, q in zip(order, order[1:] + order[:1])))
    length = sum(e.calc_length() for e in group)
    return (a.co - b.co).length < 0.8 * length and area > 0.02 * length * length


def bridge_open_chains(bm, groups, max_gap=0.25):
    """開いた鎖（殻の継ぎ目の隙間で途切れた断面）の端を近い順に辺でつなぐ。足した辺を返す。"""
    ends = []
    for gi, (group, closed, e2) in enumerate(groups):
        if not closed and len(e2) == 2:
            ends += [(gi, v) for v in e2]
    pairs = sorted(((a[1].co - b[1].co).length, i, j) for i, a in enumerate(ends) for j, b in enumerate(ends) if i < j)
    used = set()
    added = []
    for d, i, j in pairs:
        if d > max_gap or i in used or j in used:
            continue
        (gi, vi), (gj, vj) = ends[i], ends[j]
        if gi == gj and not closable(groups[gi][0], vi, vj):
            continue
        if bm.edges.get((vi, vj)) is None:
            added.append(bm.edges.new((vi, vj)))
        used |= {i, j}
    return added


def fill_caps(bm, cuts, wins, k):
    """切り口（cuts の高さの上の開いた辺の輪）を平らな面で塞ぐ。(蓋の三角形数, 塞げなかった開いた鎖の数)。
    shaft の切り口の下側（台座の上面）は暗い所を指す（支柱がせり上がる竪穴の口に見える）。"""
    uv = bm.loops.layers.uv.active
    made = 0
    skipped = 0
    hull = set()
    for c in cuts:
        z = c["z"]
        edges = [e for e in bm.edges if e.is_boundary and all(abs(v.co.z - z) < EPS * 2 for v in e.verts)]
        groups = edge_groups(edges)
        # 殻の継ぎ目の隙間で途切れた断面は、端どうしを近い順につないで輪にする
        if any(not closed for _, closed, _ in groups):
            added = bridge_open_chains(bm, groups)
            if added:
                groups = edge_groups(edges + added)
        for group, closed, ends in groups:
            if not closed:
                skipped += 1
                length = sum(e.calc_length() for e in group)
                lo, hi = nc.bbox([v.co for e in group for v in e.verts])
                log(f"open cut chain z={z}: {len(group)} edges {length:.2f} m ends {len(ends)} "
                    f"x {lo.x:.2f}..{hi.x:.2f} y {lo.y:.2f}..{hi.y:.2f}")
                continue
            ref = next((e for e in group if e.link_faces), None)
            below = ref.link_faces[0].calc_center_median().z < z if ref else True
            res = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=group,
                                          normal=(0.0, 0.0, 1.0))
            faces = [g for g in res["geom"] if isinstance(g, bmesh.types.BMFace)]
            for f in faces:
                f.normal_update()
            win = wins["dark"] if below and c.get("shaft") else wins["stone"]
            want = 1.0 if below else -1.0
            flip = [f for f in faces if f.normal.z * want < 0]
            if flip:
                bmesh.ops.reverse_faces(bm, faces=flip)
            for f in faces:
                f.smooth = False
                for lp in f.loops:
                    lp[uv].uv = (win["u"] + lp.vert.co.x * k, win["v"] + lp.vert.co.y * k)
            made += len(faces)
        if c.get("hull"):
            faces = hull_cap(bm, z, wins["stone"], k)
            hull |= set(faces)
            made += len(faces)
    return made, skipped, hull


def convex_hull_2d(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and ((out[-1][0] - out[-2][0]) * (p[1] - out[-2][1])
                                     - (out[-1][1] - out[-2][1]) * (p[0] - out[-2][0])) <= 0:
                out.pop()
            out.append(p)
        return out
    lower, upper = half(pts), half(reversed(pts))
    return lower[:-1] + upper[:-1]


def hull_cap(bm, z, win, k):
    """切り口全体の凸包の蓋（中が空洞の塔 = 壁と角柱の輪でも、折れた所が詰まった石の塊に見える）。
    個々の切り口の蓋と同じ面・同じ UV で重なるので見た目は変わらない。足した面を返す。"""
    uv = bm.loops.layers.uv.active
    pts = [(round(v.co.x, 5), round(v.co.y, 5)) for v in bm.verts if abs(v.co.z - z) < EPS * 2 and v.link_faces]
    hull = convex_hull_2d(pts)
    if len(hull) < 3:
        return []
    below = sum(v.co.z for v in bm.verts) / max(1, len(bm.verts)) < z
    verts = [bm.verts.new((x, y, z)) for x, y in hull]
    face = bm.faces.new(verts)
    face.normal_update()
    if face.normal.z * (1.0 if below else -1.0) < 0:
        face.normal_flip()
    res = bmesh.ops.triangulate(bm, faces=[face])
    faces = res["faces"]
    for f in faces:
        f.smooth = False
        for lp in f.loops:
            lp[uv].uv = (win["u"] + lp.vert.co.x * k, win["v"] + lp.vert.co.y * k)
    return faces


def boundary_count(bm):
    return sum(1 for e in bm.edges if e.is_boundary)


# MARK: - 確認用の画像

def render_views(objs, path, views, explode=0.0, size=640, light='STUDIO'):
    """workbench（テクスチャ・片面描画 = 穴や裏返った面は抜けて見える）で views [(tag, az, el)] を描く。"""
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = light
    scene.display.shading.color_type = 'TEXTURE'
    scene.display.shading.show_backface_culling = True
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.image_settings.file_format = 'PNG'
    if scene.world is None:
        scene.world = bpy.data.worlds.new("w")
    saved = {o.name: o.location.copy() for o in objs}
    if explode:
        order = [n for n in EXPLODE_ORDER if any(o.name == n for o in objs)]
        for o in objs:
            o.location.z += explode * order.index(o.name)
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    lo, hi = nc.bbox(pts)
    c = (lo + hi) * 0.5
    r = max((hi - lo).length * 0.5, 0.1)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = r * 2.1
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    files = []
    for tag, az, el in views:
        a, e = math.radians(az), math.radians(el)
        d = Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
        cam.location = c + d * r * 4
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = path.replace(".png", f"_{tag}.png")
        bpy.ops.render.render(write_still=True)
        files.append(scene.render.filepath)
    bpy.data.objects.remove(cam)
    for o in objs:
        o.location = saved[o.name]
    bpy.context.view_layer.update()
    return files


# MARK: - main

def usd_bounds(lo, hi):
    """Blender（Z 上）の範囲 → USD（Y 上、Blender +Y = USD -Z）の [min, max]。"""
    return ([round(lo.x, 3), round(lo.z, 3), round(-hi.y, 3)], [round(hi.x, 3), round(hi.z, 3), round(-lo.y, 3)])


def main(a):
    size = json.loads(a.size or "{}")
    spec = json.loads(a.parts)
    cuts = sorted(spec.get("cuts", []), key=lambda c: c["z"])
    rules = spec.get("rules", [])
    obj = sb.load_model(a.glb, f"Struct_{a.id}")
    raw_tris = nc.tri_count(obj)
    yaw = float(size.get("yaw", 0.0))
    scale = sb.fit(obj, size, yaw, "base")
    # 切る前の間引き（切り口の分割と蓋で三角形が増えるので、予算より少なめにする）
    faces = int(spec.get("faces", a.faces))
    if raw_tris > faces * 1.05:
        nc.decimate(obj, faces)

    # テクスチャ（ベース・発光・赤）と蓋に使う石の色の場所
    img = sb.base_image(obj)
    if img is None:
        raise SystemExit("no base color image")
    img.colorspace_settings.is_data = False
    if max(img.size) > a.texture:
        img.scale(a.texture, a.texture)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    emit, red, red_emit, glow = team_textures(px, spec.get("team"))
    win = stone_window(px, glow)
    wins = {"stone": win, "dark": stone_window(px, glow, dark=True) if any(c.get("shaft") for c in cuts) else win}
    base = sb.np_image(f"Struct_{a.id}_base", px[..., :3])
    emit_img = sb.np_image(f"Struct_{a.id}_emit", emit)
    for im in (base, emit_img):
        im.pack()
    os.makedirs(a.out, exist_ok=True)
    os.makedirs(a.work, exist_ok=True)
    sb.save_jpeg(red, os.path.join(a.out, f"Struct_{a.id}_red.jpg"))
    sb.save_jpeg(red_emit, os.path.join(a.out, f"Struct_{a.id}_red_emit.jpg"))
    sb.save_jpeg(px[..., :3], os.path.join(a.work, "tex_blue.jpg"))
    sb.save_jpeg(emit, os.path.join(a.work, "tex_emit.jpg"))
    sb.save_jpeg(red, os.path.join(a.work, "tex_red.jpg"))
    red_img = sb.np_image(f"Struct_{a.id}_red_preview", red)

    # 切断
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    open_before = boundary_count(bm)
    cut_faces = {}
    for c in cuts:
        cut_faces[str(c["z"])] = cut(bm, c["z"], c.get("radius"))
    bm.faces.ensure_lookup_table()
    seams = seam_edges(bm, [c["z"] for c in cuts])
    fglow = face_glow(bm, glow)
    comp, n = components(bm, seams)
    areas = np.array([f.calc_area() for f in bm.faces])
    centers = np.array([tuple(f.calc_center_median()) for f in bm.faces])
    part_of = {}
    junk = []
    comp_report = []
    for i in range(n):
        idx = np.nonzero(comp == i)[0]
        area = float(areas[idx].sum())
        vz = [v.co.z for j in idx for v in bm.faces[int(j)].verts]
        if area < 1e-4 or len(idx) < 3:
            junk.append(i)
            continue
        wgt = areas[idx] / max(area, 1e-12)
        cxyz = (centers[idx] * wgt[:, None]).sum(0)
        st = {"cz": float(cxyz[2]), "radius": float(math.hypot(cxyz[0], cxyz[1])), "top": max(vz),
              "bottom": min(vz), "glow": float((fglow[idx] * wgt).sum())}
        part_of[i] = classify(st, rules)
        comp_report.append(dict(part=part_of[i], faces=int(len(idx)), area=round(area, 3),
                                **{k: round(v, 3) for k, v in st.items()}))
    layer = bm.faces.layers.int.new("part")
    drop = []
    for f in bm.faces:
        ci = int(comp[f.index])
        if ci in part_of:
            f[layer] = PARTS.index(part_of[ci])
        else:
            drop.append(f)
    # 切り口の辺のうち、上下が別の部品になる所だけ切り離す（同じ部品の塊どうしはつないだまま）
    split = [e for e in seams if len({f[layer] for f in e.link_faces}) > 1]
    if split:
        bmesh.ops.split_edges(bm, edges=split)
    if drop:
        bmesh.ops.delete(bm, geom=drop, context='FACES')
    bm.to_mesh(obj.data)
    bm.free()
    log(f"cut faces {cut_faces} seams {len(seams)} split {len(split)} components {n} junk {len(junk)}")

    # 部品ごとの物体と切り口の蓋。蓋の UV は全部品で同じ縮尺（中心からの最大距離 → 石の四角の 0.9）
    zs = [c["z"] for c in cuts]
    on_plane = [v.co for v in obj.data.vertices if any(abs(v.co.z - z) < EPS * 2 for z in zs)]
    reach = max([max(abs(p.x), abs(p.y)) for p in on_plane] + [0.5])
    k = win["half"] * 0.9 / reach
    mat = None
    parts = []
    report = {}
    for pi, name in enumerate(PARTS):
        pbm = bmesh.new()
        pbm.from_mesh(obj.data)
        pl = pbm.faces.layers.int.get("part")
        bmesh.ops.delete(pbm, geom=[f for f in pbm.faces if f[pl] != pi], context='FACES')
        if not pbm.faces:
            pbm.free()
            log(f"{name}: empty")
            continue
        open_before_caps = boundary_count(pbm)
        caps, skipped, hull = fill_caps(pbm, cuts, wins, k)
        # 蓋をした後も切り口に残る開いた辺（片面の布・開いた殻の断面。凸包の蓋の外周は除く。長さの合計 m）
        open_cut = sum(e.calc_length() for e in pbm.edges
                       if e.is_boundary and not all(f in hull for f in e.link_faces)
                       and any(all(abs(v.co.z - z) < EPS * 2 for v in e.verts) for z in zs))
        bmesh.ops.triangulate(pbm, faces=pbm.faces[:])
        loose = [v for v in pbm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(pbm, geom=loose, context='VERTS')
        open_after = boundary_count(pbm)
        me = bpy.data.meshes.new(name)
        pbm.to_mesh(me)
        pbm.free()
        if "part" in me.attributes:
            me.attributes.remove(me.attributes["part"])
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        nc.select_only([o])
        try:
            bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
        except Exception:  # noqa: BLE001
            bpy.ops.object.shade_smooth()
        if mat is None:
            mat = sb.make_material(o, a.id, base, emit_img)
        else:
            o.data.materials.append(mat)
        lo, hi = nc.bbox([v.co for v in me.vertices])
        umin, umax = usd_bounds(lo, hi)
        report[name] = {"min": umin, "max": umax,
                        "center": [round((p + q) * 0.5, 3) for p, q in zip(umin, umax)],
                        "triangles": nc.tri_count(o), "vertices": len(me.vertices), "capTriangles": caps,
                        "openEdgesBeforeCaps": open_before_caps, "openEdges": open_after, "openCutChains": skipped,
                        "openCutLength": round(open_cut, 3)}
        parts.append(o)
        log(f"{name}: {report[name]}")
    bpy.data.objects.remove(obj, do_unlink=True)
    total = sum(r["triangles"] for r in report.values())

    # 確認用の画像（組んだ姿・ゲームの角度・分解図・赤チーム）
    prev = os.path.join(a.work, "parts.png")
    images = render_views(parts, prev, [("front", -60.0, 25.0), ("game", -90.0, 56.0), ("top", -90.0, 89.0)])
    images += render_views(parts, os.path.join(a.work, "parts_exploded.png"),
                           [("above", -60.0, 30.0), ("side", 0.0, 8.0)], explode=1.0)
    images += render_views(parts, os.path.join(a.work, "parts_exploded.png"), [("below", -60.0, -25.0)],
                           explode=1.0, light='FLAT')
    tex_node = next(n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image == base)
    tex_node.image = red_img
    images += render_views(parts, os.path.join(a.work, "parts_red.png"), [("game", -90.0, 56.0)])
    tex_node.image = base

    # 予算は切り口・蓋を足した後の合計（超えたら parts.faces で切る前の間引きを強める）
    if total > a.budget:
        raise SystemExit(f"{a.id}: {total} triangles > budget {a.budget}")
    lo, hi = nc.bbox([v.co for o in parts for v in o.data.vertices])
    umin, umax = usd_bounds(lo, hi)
    out = os.path.join(a.out, f"Struct_{a.id}.usdz")
    textures = nc.export_usdz(parts, out, skinned=False, texture_size=a.texture, merge_xform=True)

    # 書き出した USDZ を読み直して部品の名前・面数を確かめる
    from pxr import Usd, UsdGeom
    stage = Usd.Stage.Open(out)
    prims = []
    for p in stage.Traverse():
        if p.IsA(UsdGeom.Mesh):
            counts = UsdGeom.Mesh(p).GetFaceVertexCountsAttr().Get() or []
            prims.append({"path": str(p.GetPath()), "triangles": int(sum(c - 2 for c in counts))})
    names = sorted(p["path"].rsplit("/", 1)[-1] for p in prims)
    if names != sorted(report):
        raise SystemExit(f"{a.id}: USD mesh prims {names} != parts {sorted(report)}")

    summary = {"id": a.id, "file": os.path.basename(out),
               "axes": "USD / RealityKit: +Y up, ground y = 0 at the footprint centre, +Z faces the game camera (south)",
               "rawTriangles": raw_tris, "triangles": total, "budget": a.budget, "scale": round(scale, 5), "yaw": yaw,
               "size": [round(umax[i] - umin[i], 3) for i in range(3)], "min": umin, "max": umax,
               "cuts": cuts, "parts": report, "usdPrims": prims, "openEdgesInput": open_before,
               "capUV": wins, "components": sorted(comp_report, key=lambda r: (PARTS.index(r["part"]), -r["faces"])),
               "junkComponents": len(junk), "textures": textures, "bytes": os.path.getsize(out),
               "previews": [os.path.relpath(p, a.work) for p in images]}
    path = a.json or os.path.join(a.work, "parts.json")
    with open(path, "w") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)
    log(json.dumps({k: summary[k] for k in ("id", "triangles", "budget", "size", "bytes")}))


if __name__ == "__main__":
    main(parse())
