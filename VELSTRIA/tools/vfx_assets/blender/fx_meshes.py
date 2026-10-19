# 担当: battle-renderer（スキル演出の素材）。演出用の UV 付きメッシュを Blender で組み、.fxm に書き出す。
# 使い方: blender -b --factory-startup --python-exit-code 1 -P fx_meshes.py -- --out <dir> [--only name ...] [--report r.json]
# 出力: <dir>/fxm_<name>.bin（形式は fx_common.write_fxm。App/Resources 以下はバンドル直下へ平らに入るので接頭辞を付ける）。実行時は FXShape の模型の形（FXMeshes.swift の FXModelFile）が読む。
# どれも単位の大きさ（半径・高さ 1）で作り、実行時に FXMesh.size で伸ばす。前 = 実行時の -Z（Blender の +Y）。
# UV の約束（実行時のシェーダーは v を裏返して画像の上 = v 1 にそろえる）:
#   crescent  三日月の帯（前を中心に ±100°・外径 1）。u = 弧に沿う（0 = 右端 → 1 = 左端 = 振り終わり。頭が太い）、v = 内縁 0 → 外縁 1
#   ringLip   衝撃の輪（内径 0.55 → 外径 1、外縁が 0.1 持ち上がる）。u = 円周（4 周で繰り返す）、v = 内縁 0 → 外縁 1
#   twister   竜巻（3 本の螺旋の帯。下の半径 0.25 → 上 1、高さ 1、1.4 回転）。u = 帯に沿う（下 0 → 上 1）、v = 帯の幅
#   pillar2   光の柱（入れ子の 2 枚の円柱。内: 半径 0.42・高さ 1、外: 半径 1・高さ 0.72、上へ細る）。u = 円周 ×2、v = 根元 0 → 先 1
#   bladeRing 渦の刃の輪（地面に寝かせた 16 枚の勾玉形の刃が半径 0.55〜1 の輪に並ぶ）。u = 刃に沿う（尾 0 → 頭 1）、v = 刃の幅
#   burstDome 爆ぜる炎の半球（半径 1。上と外へ炎の舌が尖る）。u = 経度 ×2、v = 赤道 0 → 頂 1
#   starCross 四芒星の盤（地面の厚み 0.05 の 4 本の腕・長さ 1、腕の間に短い 4 本）。上面の UV = 平面の投影（中心 0.5）
#   shardRing 割れて浮く岩板の輪（地面の 10 枚の角張った板が半径 0.35〜1 に並ぶ）。上面の UV = 平面の投影

import argparse
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fx_common as fc  # noqa: E402


def grid_faces(nu, nv, base=0):
    """(nu + 1) × (nv + 1) の格子の四角形の面（頂点の添字は u が速く回る）。"""
    faces = []
    w = nu + 1
    for j in range(nv):
        for i in range(nu):
            a = base + j * w + i
            faces.append((a, a + 1, a + w + 1, a + w))
    return faces


def grid_uvs(faces, uv_of):
    out = []
    for f in faces:
        for vi in f:
            out.append(uv_of[vi])
    return out


def ribbon(fn, nu, nv):
    """fn(u, v) → (x, y, z) の帯。頂点・面・UV（面の角ごと）。"""
    verts, uv_of = [], []
    for j in range(nv + 1):
        v = j / nv
        for i in range(nu + 1):
            u = i / nu
            verts.append(fn(u, v))
            uv_of.append((u, v))
    faces = grid_faces(nu, nv)
    return verts, faces, grid_uvs(faces, uv_of)


def concat(parts):
    verts, faces, uvs = [], [], []
    for pv, pf, pu in parts:
        base = len(verts)
        verts += pv
        faces += [tuple(base + k for k in f) for f in pf]
        uvs += pu
    return verts, faces, uvs


# --- 形 ---------------------------------------------------------------------------------------------

def crescent():
    # 前（+Y）を中心に ±100°。右端（u 0）から左端（u 1）へ振る。幅は振り終わり寄り（u ≈ 0.65）が最も太く両端で尖る
    span = math.radians(200)

    def fn(u, v):
        a = -span / 2 + span * u  # 0 = 前、+ = 左（Blender の -X 側）
        width = 0.46 * math.sin(math.pi * u) ** 0.65 * (0.62 + 0.38 * u)
        r = 1.0 - width * (1 - v)
        # 帯の中ほどを少し持ち上げて、地面すれすれの板が斜めのカメラで潰れて見えないように
        z = 0.05 * math.sin(math.pi * v) * math.sin(math.pi * u)
        return (-math.sin(a) * r, math.cos(a) * r, z)

    return ribbon(fn, 48, 4)


def ring_lip():
    def fn(u, v):
        a = 2 * math.pi * u
        r = 0.55 + 0.45 * v
        z = 0.1 * v ** 2
        return (math.cos(a) * r, math.sin(a) * r, z)

    verts, faces, uvs = ribbon(fn, 64, 3)
    uvs = [(u * 4, v) for (u, v) in uvs]
    return verts, faces, uvs


def twister():
    parts = []
    for k in range(3):
        base = 2 * math.pi * k / 3

        def fn(u, v, base=base):
            turns = 1.4
            h = u
            r = 0.25 + 0.75 * u ** 0.8
            a = base + 2 * math.pi * turns * u + v * 0.55
            z = h + (v - 0.5) * 0.22
            return (math.cos(a) * r, math.sin(a) * r, max(0.0, z))

        parts.append(ribbon(fn, 56, 2))
    return concat(parts)


def pillar2():
    parts = []
    for (r0, h, taper) in [(0.42, 1.0, 0.55), (1.0, 0.72, 0.75)]:
        def fn(u, v, r0=r0, h=h, taper=taper):
            a = 2 * math.pi * u
            r = r0 * (1 - (1 - taper) * v ** 1.5)
            return (math.cos(a) * r, math.sin(a) * r, h * v)

        pv, pf, pu = ribbon(fn, 32, 4)
        pu = [(u * 2, v) for (u, v) in pu]
        parts.append((pv, pf, pu))
    return concat(parts)


def blade_ring():
    # 勾玉形の刃: 尾（u 0）は細く外寄り、頭（u 1）は太く内へ巻く。輪の接線に沿って反時計回りに並べる
    rng = random.Random(29)
    parts = []
    n = 16
    for k in range(n):
        a0 = 2 * math.pi * k / n + rng.uniform(-0.12, 0.12)
        rad = rng.uniform(0.62, 1.0)
        length = rng.uniform(0.42, 0.6)  # 弧の長さ（ラジアン）
        width = rng.uniform(0.1, 0.15)

        def fn(u, v, a0=a0, rad=rad, length=length, width=width):
            a = a0 + length * u
            r = rad - 0.14 * u ** 1.5  # 頭ほど内へ巻く
            w = width * (0.25 + 0.75 * math.sin(math.pi * min(1.0, u * 1.15)) ** 0.8) * (0.4 + 0.6 * u)
            rr = r + (v - 0.5) * w * 2
            return (math.cos(a) * rr, math.sin(a) * rr, 0.0)

        parts.append(ribbon(fn, 12, 1))
    return concat(parts)


def burst_dome():
    # 半球を経度 × 緯度の格子で作り、上と外へ炎の舌（ノイズで尖らせる）を伸ばす
    nu, nv = 48, 14
    rng_off = Vector((3.1, 7.7, 1.3))

    def fn(u, v):
        lon = 2 * math.pi * u
        lat = (math.pi / 2) * v
        d = Vector((math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)))
        n = noise.noise(d * 2.4 + rng_off)
        spikes = max(0.0, noise.noise(d * 5.5 + rng_off * 2)) ** 1.5
        k = 1.0 + 0.12 * n + 0.55 * spikes * (0.3 + 0.7 * v)
        p = d * k
        # 継ぎ目（u = 0 と 1）を同じ位置にする
        return (p.x, p.y, p.z)

    verts, faces, uvs = ribbon(fn, nu, nv)
    # u = 0 と u = 1 の列をそろえる（ノイズは同じ点なので同じ値だが、浮動小数の差を消す）
    w = nu + 1
    for j in range(nv + 1):
        verts[j * w + nu] = verts[j * w]
    uvs = [(u * 2, v) for (u, v) in uvs]
    return verts, faces, uvs


def extruded_polygons(polys, thickness, uv_scale=0.5):
    """地面の多角形（xy の点の並び）を thickness だけ押し出す。上面は平面の投影の UV（中心 0.5）、側面は v を 0〜0.08 に。"""
    verts, faces, uvs = [], [], []
    for poly in polys:
        n = len(poly)
        base = len(verts)
        for (x, y) in poly:
            verts.append((x, y, thickness))
        for (x, y) in poly:
            verts.append((x, y, 0.0))
        top = tuple(base + i for i in range(n))
        faces.append(top)
        for (x, y) in poly:
            uvs.append((0.5 + x * uv_scale, 0.5 + y * uv_scale))
        for i in range(n):
            a, b = base + i, base + (i + 1) % n
            faces.append((a + n, b + n, b, a))
            x0, y0 = poly[i]
            x1, y1 = poly[(i + 1) % n]
            u0 = 0.5 + x0 * uv_scale
            u1 = 0.5 + x1 * uv_scale
            uvs += [(u0, 0.0), (u1, 0.0), (u1, 0.08), (u0, 0.08)]
    return verts, faces, uvs


def star_cross():
    rng = random.Random(17)
    polys = []
    for k in range(8):
        a = math.pi / 4 + k * math.pi / 4
        long = k % 2 == 0
        L = 1.0 if long else 0.5
        W = 0.2 if long else 0.11
        d = (math.cos(a), math.sin(a))
        s = (-d[1], d[0])
        # 菱形の腕（付け根は中心の少し先、最も太いのは長さの 0.28、先は尖る）。縁に小さな刻み
        base = 0.08
        pts = []
        prof = [(base, 0.0), (L * 0.28, W), (L * 0.55, W * 0.62), (L * 0.78, W * 0.3), (L, 0.0)]
        right = [(r, -w * rng.uniform(0.85, 1.1)) for (r, w) in prof[1:-1]]
        left = [(r, w * rng.uniform(0.85, 1.1)) for (r, w) in reversed(prof[1:-1])]
        for (r, w) in [prof[0]] + right + [prof[-1]] + left:
            pts.append((d[0] * r + s[0] * w, d[1] * r + s[1] * w))
        polys.append(pts)
    # 中心の八角形
    polys.append([(math.cos(math.pi / 8 + i * math.pi / 4) * 0.12, math.sin(math.pi / 8 + i * math.pi / 4) * 0.12)
                  for i in range(8)])
    return extruded_polygons(polys, 0.05, uv_scale=0.5)


def shard_ring():
    rng = random.Random(41)
    polys = []
    for k in range(10):
        a = 2 * math.pi * k / 10 + rng.uniform(-0.2, 0.2)
        r = rng.uniform(0.35, 0.95)
        size = rng.uniform(0.09, 0.16)
        cx, cy = math.cos(a) * r, math.sin(a) * r
        m = rng.randint(4, 6)
        pts = []
        for i in range(m):
            b = 2 * math.pi * i / m + rng.uniform(-0.3, 0.3)
            rr = size * rng.uniform(0.6, 1.1)
            pts.append((cx + math.cos(b) * rr, cy + math.sin(b) * rr))
        polys.append(pts)
    return extruded_polygons(polys, 0.06, uv_scale=0.5)


SHAPES = {
    "crescent": (crescent, False),
    "ringLip": (ring_lip, True),
    "twister": (twister, True),
    "pillar2": (pillar2, True),
    "bladeRing": (blade_ring, False),
    "burstDome": (burst_dome, True),
    "starCross": (star_cross, False),
    "shardRing": (shard_ring, False),
}


def build(name):
    fn, smooth = SHAPES[name]
    verts, faces, uvs = fn()
    obj = fc.mesh_object(name, verts, faces, uvs)
    me = obj.data
    for p in me.polygons:
        p.use_smooth = smooth
    if not smooth and hasattr(me, "set_sharp_from_angle"):
        me.set_sharp_from_angle(angle=math.radians(30))
    positions, normals, uv, indices = fc.mesh_arrays(obj)
    return positions, normals, uv, indices


def main():
    ap = argparse.ArgumentParser(prog="fx_meshes.py")
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--report", default="")
    a = ap.parse_args(fc.script_args())
    names = a.only or sorted(SHAPES)
    report = {}
    for name in names:
        fc.reset_scene()
        positions, normals, uvs, indices = build(name)
        info = fc.write_fxm(os.path.join(a.out, "fxm_" + name + ".bin"), positions, normals, uvs, indices)
        report[name] = info
        print("fxm %-10s %5d verts %5d tris %6d bytes" % (name, info["vertices"], info["triangles"], info["bytes"]))
    if a.report:
        with open(a.report, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, sort_keys=True)


main()
