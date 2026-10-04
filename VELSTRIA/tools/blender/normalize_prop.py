# 担当: hero-assets。Tripo の武器・副手 GLB を実行時用 USDZ（静的メッシュ）に正規化する。
# 使い方: Blender -b --factory-startup --python-exit-code 1 --python normalize_prop.py -- \
#   --in model.glb --out Prop_broadsword.usdz [--grip 0.1] [--length 1.0] [--texture-size 512]
#   [--max-faces 3000] [--axis auto|up|pca|vertical] [--front +x|-x|+z|-z] [--yaw DEG] [--side none|bow|gun]
#   [--report report.json]
# 出力座標（HeroGear.swift と同じ）: 握りが原点、+Y へ伸びる。最も薄い向きが ±X（刃の平面は ±X、刃筋は ±Z）。
#   Y 方向の長さ = --length、原点 = 下端から grip*length の高さの断面中心。
# 正面と符号: --front は元モデルの正面（概念画像で見る側）の glTF 軸（Tripo 既定の export_orientation は +x）。
#   薄い向きを X へ回したあと、正面が +X 側になるよう Y 軸回りの 180° を決める。このとき画像の右側は USD -Z、
#   左側は USD +Z に来る（銃の上面・弓の弦を +Z にしたいなら画像の左、刃先を前方 -Z にしたいなら画像の右に描かせる）。
#   --yaw は最後に USD Y 軸回りに回す角度（+90 で正面が -Z、-90 で +Z。面が ±Z の盾・竪琴・弩に使う）。
#   --side bow: 弦（両端の弓先）側を +Z に。両端 12% の断面と中央 20% の頂点の前後位置の差で判定し、逆なら 180° 回す。
#   --side gun: 上面（質量の多い側）が +Z かを面積重心で調べ、逆らしければ警告だけ出す（銃床の張り出しで外れやすい）。
# 長軸と向きのヒューリスティック:
#   1. 面積重み付き PCA の第 1 軸を長軸とする。
#   2. 長軸が鉛直から 30° 以内（Tripo へは「縦置き・先端が上」で生成依頼する前提）なら上端を +Y に残す。
#      8° 以内なら鉛直そのものを長軸とする（斧など頭が片寄った形で PCA が傾くのを無視する）。
#   3. それ以外は両端 15% の断面の「幅」（長軸に垂直な外接矩形の長辺）が大きい端を頭（+Y）とする。
#      面積でなく幅を使うのは、剣で柄（太い角柱）より刃先側（薄く幅広）を頭と判定させるため。
#   4. 長軸回りに 0.5° 刻みで回し、X 方向の幅が最小になる角度を採る。
#   --axis up は常に 2、pca は常に 3、vertical は元の上方向をそのまま長軸にして反転もしない（丸盾など PCA が
#   面内の向きで揺れる形）。

import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import norm_common as nc  # noqa: E402

# glTF 軸 -> Blender 軸（glTF 取り込みは (x, y, z) -> (x, -z, y)）
FRONT_AXES = {"+x": Vector((1, 0, 0)), "-x": Vector((-1, 0, 0)), "+z": Vector((0, -1, 0)), "-z": Vector((0, 1, 0))}
SIDE_BOW_MIN = 0.04
SIDE_GUN_MIN = 0.05
VERTICAL_DEG = 30.0
SNAP_VERTICAL_DEG = 8.0
END_SLICE = 0.15


def parse():
    p = argparse.ArgumentParser(prog="normalize_prop.py")
    p.add_argument("--in", dest="inp", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--grip", type=float, default=0.1)
    p.add_argument("--length", type=float, default=1.0)
    p.add_argument("--texture-size", type=int, default=512)
    p.add_argument("--max-faces", type=int, default=3000)
    p.add_argument("--axis", default="auto", choices=["auto", "up", "pca", "vertical"])
    p.add_argument("--front", default="+x", choices=sorted(FRONT_AXES))
    p.add_argument("--yaw", type=float, default=0.0)
    p.add_argument("--side", default="none", choices=["none", "bow", "gun"])
    p.add_argument("--report", default="")
    return p.parse_args(nc.script_args())


def principal_axis(obj):
    """三角形の面積重み付き重心で共分散を取り、最大固有ベクトル（べき乗法）を返す。"""
    me = obj.data
    me.calc_loop_triangles()
    pts, ws = [], []
    for t in me.loop_triangles:
        c = sum((me.vertices[i].co for i in t.vertices), Vector()) / 3.0
        pts.append(c)
        ws.append(max(t.area, 1e-12))
    wsum = sum(ws)
    mean = sum((p * w for p, w in zip(pts, ws)), Vector()) / wsum
    cov = Matrix(((0, 0, 0), (0, 0, 0), (0, 0, 0)))
    for p, w in zip(pts, ws):
        d = p - mean
        for i in range(3):
            for j in range(3):
                cov[i][j] += w * d[i] * d[j]
    v = Vector((0.3, 0.5, 0.8))
    for _ in range(200):
        v = (cov @ v).normalized()
    return v


def section_points(obj, z):
    """平面 z と交わる辺の交点と、平面上の頂点。"""
    me = obj.data
    out = []
    for e in me.edges:
        a = me.vertices[e.vertices[0]].co
        b = me.vertices[e.vertices[1]].co
        if (a.z - z) * (b.z - z) < 0:
            t = (z - a.z) / (b.z - a.z)
            out.append(a.lerp(b, t))
    out += [v.co.copy() for v in me.vertices if abs(v.co.z - z) < 1e-6]
    return out


def slice_width(obj, z0, z1):
    pts = [v.co for v in obj.data.vertices if z0 <= v.co.z <= z1]
    pts += section_points(obj, z0) + section_points(obj, z1)
    if not pts:
        return 0.0
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    return max(max(xs) - min(xs), max(ys) - min(ys))


def transform(obj, m):
    obj.matrix_world = m @ obj.matrix_world
    nc.apply_transforms([obj])


def thin_axis_angle(obj):
    pts = [(v.co.x, v.co.y) for v in obj.data.vertices]
    best = (float("inf"), 0.0)
    for k in range(360):
        a = math.radians(k * 0.5)
        c, s = math.cos(a), math.sin(a)
        xs = [x * c - y * s for x, y in pts]
        w = max(xs) - min(xs)
        if w < best[0] - 1e-9:
            best = (w, a)
    return best[1]


def side_check(obj, kind, grip):
    """弓: 弓先（両端）が握り（中央）より USD +Z（Blender -Y）側にあるか。銃: 面積重心が握りの断面中心より +Z 側か
    （外接箱の中心だとスコープ自体が箱を広げて基準がずれる）。bias は USD z の差 / 長さ（弓）または / Z 方向の幅（銃）。"""
    if kind == "none":
        return {"mode": "none"}
    verts = [v.co for v in obj.data.vertices]
    lo, hi = nc.bbox(verts)
    span = hi.z - lo.z
    if kind == "bow":
        ends = [-v.y for v in verts if v.z <= lo.z + 0.12 * span or v.z >= hi.z - 0.12 * span]
        mid = [-v.y for v in verts if abs(v.z - (lo.z + hi.z) * 0.5) <= 0.1 * span]
        if not ends or not mid:
            return {"mode": kind, "bias": None, "turned180": False}
        bias = (sum(ends) / len(ends) - sum(mid) / len(mid)) / span
        turned = bias < -SIDE_BOW_MIN
        if turned:
            transform(obj, Matrix.Rotation(math.pi, 4, 'Z'))
            nc.warn(f"bow tips were on -Z (bias {bias:.3f}): turned 180° so the string side is +Z")
        elif bias < SIDE_BOW_MIN:
            nc.warn(f"bow string side unclear (bias {bias:.3f}): check that the string is on +Z")
        return {"mode": kind, "bias": round(bias, 4), "turned180": turned}
    me = obj.data
    me.calc_loop_triangles()
    acc, wsum = 0.0, 0.0
    for t in me.loop_triangles:
        c = sum((me.vertices[i].co for i in t.vertices), Vector()) / 3.0
        acc += -c.y * t.area
        wsum += t.area
    depth = hi.y - lo.y
    sec = section_points(obj, lo.z + grip * span)
    if wsum <= 0 or depth <= 1e-6 or not sec:
        return {"mode": kind, "bias": None, "turned180": False}
    ref = -(min(p.y for p in sec) + max(p.y for p in sec)) * 0.5
    bias = (acc / wsum - ref) / depth
    if bias < -SIDE_GUN_MIN:
        nc.warn(f"more mass on -Z than +Z (bias {bias:.3f}): if the top/scope is on -Z, re-import with the yaw "
                f"turned by 180°")
    return {"mode": kind, "bias": round(bias, 4), "turned180": False}


def main(a):
    nc.reset_scene()
    nc.import_glb(a.inp)
    # glTF 取り込みが骨の表示用に作る Icosphere（ビューレイヤー外）は除く
    shapes = {pb.custom_shape.name for o in bpy.data.objects if o.type == 'ARMATURE'
              for pb in o.pose.bones if pb.custom_shape}
    meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.name not in shapes
              and o.name in bpy.context.view_layer.objects]
    if not meshes:
        raise SystemExit("no mesh in input")
    for m in meshes:
        nc.unparent_keep(m)
        for mod in list(m.modifiers):
            m.modifiers.remove(mod)
        m.vertex_groups.clear()
    nc.delete_except(meshes)
    nc.apply_transforms(meshes)
    obj = nc.join_meshes(meshes)
    obj.name = "Prop"
    obj.data.name = "Prop"
    if obj.data.shape_keys:
        nc.select_only([obj])
        bpy.ops.object.shape_key_remove(all=True, apply_mix=False)

    # 1-3. 長軸を Blender +Z（= USD +Y）へ。元の正面ベクトルも一緒に回す
    pca = principal_axis(obj)
    tilt = math.degrees(math.acos(min(1.0, abs(pca.z))))
    mode = a.axis
    if mode == "auto":
        mode = "up" if tilt <= VERTICAL_DEG else "pca"
    axis = pca if pca.z >= 0 else -pca
    if mode == "vertical" or (mode == "up" and tilt <= SNAP_VERTICAL_DEG):
        axis = Vector((0, 0, 1))
    r1 = axis.rotation_difference(Vector((0, 0, 1))).to_matrix()
    transform(obj, r1.to_4x4())
    front = r1 @ FRONT_AXES[a.front]

    # 4. 薄い向きを X へ。0〜180° の探索なので符号は不定 -> 正面が +X 側に来るよう 180° を決める
    r2 = Matrix.Rotation(thin_axis_angle(obj), 3, 'Z')
    transform(obj, r2.to_4x4())
    front = r2 @ front
    front_turned = front.x < -1e-3
    if front_turned:
        transform(obj, Matrix.Rotation(math.pi, 4, 'Z'))
        front = Vector((-front.x, -front.y, front.z))
    hfront = Vector((front.x, front.y, 0))
    front_alignment = front.x / hfront.length if hfront.length > 1e-6 else 0.0
    if front_alignment < 0.7:
        nc.warn(f"the thinnest axis is {math.degrees(math.acos(max(-1.0, min(1.0, front_alignment)))):.0f}° "
                f"away from the source front {a.front}: the ±Z side of this prop is a guess")

    lo, hi = nc.bbox([v.co for v in obj.data.vertices])
    span = hi.z - lo.z
    if span <= 1e-6:
        raise SystemExit("degenerate prop length")
    w_bottom = slice_width(obj, lo.z, lo.z + span * END_SLICE)
    w_top = slice_width(obj, hi.z - span * END_SLICE, hi.z)
    flipped = False
    if mode == "pca" and w_bottom > w_top:
        # X 軸回りの 180°: 正面（+X）はそのまま
        transform(obj, Matrix.Rotation(math.pi, 4, 'X'))
        w_bottom, w_top = w_top, w_bottom
        flipped = True

    # 5. 面が ±Z の副手（盾・竪琴・弩）は Y 軸（Blender Z）回りに回す。Blender +Y = USD -Z
    if a.yaw:
        transform(obj, Matrix.Rotation(math.radians(a.yaw), 4, 'Z'))

    # 6. 形からの符号確認
    side = side_check(obj, a.side, a.grip)

    # 長さ・握り位置
    lo, hi = nc.bbox([v.co for v in obj.data.vertices])
    s = a.length / (hi.z - lo.z)
    transform(obj, Matrix.Diagonal((s, s, s, 1.0)) @ Matrix.Translation(-lo))
    gz = a.grip * a.length
    sec = section_points(obj, gz)
    if sec:
        sx, sy = nc.bbox([Vector((p.x, p.y, 0)) for p in sec])
        c = (sx + sy) * 0.5
    else:
        lo, hi = nc.bbox([v.co for v in obj.data.vertices])
        c = (lo + hi) * 0.5
    transform(obj, Matrix.Translation((-c.x, -c.y, -gz)))

    nc.decimate(obj, a.max_faces)
    lo, hi = nc.bbox([v.co for v in obj.data.vertices])
    faces = nc.tri_count(obj)
    verts = len(obj.data.vertices)
    textures = nc.export_usdz([obj], a.out, skinned=False, texture_size=a.texture_size)
    # 報告は USD 座標（x, y, z）= Blender (x, z, -y)
    report = {
        "input": os.path.abspath(a.inp),
        "output": os.path.abspath(a.out),
        "faces": faces,
        "vertices": verts,
        "axisMode": mode,
        "pcaTiltDegrees": round(tilt, 3),
        "flipped": flipped,
        "front": a.front,
        "frontAlignment": round(front_alignment, 4),
        "frontTurned180": front_turned,
        "yawDegrees": a.yaw,
        "side": side,
        "endWidths": {"bottom": round(w_bottom * s, 5), "top": round(w_top * s, 5)},
        "boundsMin": [round(lo.x, 5), round(lo.z, 5), round(-hi.y, 5)],
        "boundsMax": [round(hi.x, 5), round(hi.z, 5), round(-lo.y, 5)],
        "scale": round(s, 6),
        "textures": textures,
        "materials": [m.name for m in obj.data.materials if m],
        "bytes": os.path.getsize(a.out),
    }
    nc.write_report(report, a.report)


if __name__ == "__main__":
    args = parse()
    try:
        main(args)
    except BaseException as e:
        # 失敗（入力が読めない・形が潰れている・想定外の例外）もレポートの errors に残す（tools/tripo.mjs が表示する）
        if args.report and not (isinstance(e, SystemExit) and e.code in (None, 0)):
            nc.write_report({"input": os.path.abspath(args.inp), "output": None,
                             "errors": [str(e) or type(e).__name__]}, args.report)
        raise
