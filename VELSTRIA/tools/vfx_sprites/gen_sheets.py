#!/usr/bin/env python3
"""RealityKit パーティクル用のフリップブック（4×4 コマのスプライトシート）を手続き的に生成する。

各シートは 512×512 の RGBA PNG。128×128 のコマが 4×4 に並ぶ（左上から行優先: 0 1 2 3 / 4 5 6 7 / ...）。
RGB は全面 255（白）で、形はすべてアルファに持つ（色はエンジン側の tint で付ける）。
各コマの外周 2 px は必ず完全に透明（隣のコマへにじまない）。乱数の種は固定で、何度回しても同じバイト列になる。

usage:
  python gen_sheets.py                       # 全シートを ../../App/Resources/FX/Sheets へ
  python gen_sheets.py --only fire_burst     # 1 枚だけ（manifest は既存の PNG から作り直す）
  python gen_sheets.py --preview "$TEMP/vfx_sprites_preview"   # 確認用の合成画像も書く（リポジトリの外へ）
"""
import argparse
import hashlib
import json
import math
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, "..", "..", "App", "Resources", "FX", "Sheets"))

GRID = 4
FRAMES = GRID * GRID
CELL = 128
SHEET = CELL * GRID
BORDER = 2  # コマの外周で完全に透明にする幅（px）
PX = 2.0 / CELL  # 正規化座標（コマの中心が 0、端が ±1）での 1 px


# --- 数学の小道具 -------------------------------------------------------------------------------

def sstep(e0, e1, x):
    """smoothstep。e0 > e1 なら逆向き（1 → 0）。"""
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def ease_out(t, p=2.0):
    return 1.0 - (1.0 - np.clip(t, 0.0, 1.0)) ** p


def grid(ss):
    """1 コマ分の座標。X は右へ +、Y は上へ +、範囲は [-1, 1]（画素の中心）。ss は超解像の倍率。"""
    n = CELL * ss
    c = ((np.arange(n) + 0.5) / n * 2.0 - 1.0).astype(np.float64)
    X, Yimg = np.meshgrid(c, c)
    return X, -Yimg


def down(a, ss):
    """超解像の画像を面積平均で 128×128 に縮める。"""
    if ss == 1:
        return a
    n = a.shape[0] // ss
    return a.reshape(n, ss, n, ss).mean(axis=(1, 3))


def blur(a, sigma_px):
    """最終解像度の px 単位でぼかす（a は 128×128）。"""
    if sigma_px <= 0:
        return a
    return ndimage.gaussian_filter(a, sigma_px, mode="constant")


def to_px(p, ss):
    """正規化座標 → 超解像キャンバスの画素座標（x 右・y 下）。"""
    n = CELL * ss
    return (p[..., 0] + 1.0) * 0.5 * n - 0.5, (1.0 - p[..., 1]) * 0.5 * n - 0.5


def rot(theta):
    c, s = math.cos(theta), math.sin(theta)
    return np.array([[c, -s], [s, c]])


# --- ノイズ ---------------------------------------------------------------------------------------

class Perlin3:
    """3D グラディエントノイズ（Perlin）。各軸に整数の周期（格子の折り返し）を持たせられる。

    ループするシートは時間軸に周期を持たせ、t = 0 → 1 で 1 周期進める（円周上で時間を取るのと同じく継ぎ目が出ない）。
    出力はおおむね [-0.6, 0.6]（標準偏差 0.21）。
    """

    def __init__(self, seed):
        rng = np.random.default_rng(seed)
        p = rng.permutation(256).astype(np.int64)
        self.perm = np.concatenate([p, p])
        g = rng.normal(size=(256, 3))
        g /= np.linalg.norm(g, axis=1, keepdims=True)
        self.gx, self.gy, self.gz = g[:, 0].copy(), g[:, 1].copy(), g[:, 2].copy()

    def __call__(self, x, y, z=0.0, period=(0, 0, 0)):
        x, y, z = np.broadcast_arrays(np.asarray(x, np.float64), np.asarray(y, np.float64),
                                      np.asarray(z, np.float64))
        xf, yf, zf = np.floor(x), np.floor(y), np.floor(z)
        fx, fy, fz = x - xf, y - yf, z - zf
        xi, yi, zi = xf.astype(np.int64), yf.astype(np.int64), zf.astype(np.int64)
        u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
        v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
        w = fz * fz * fz * (fz * (fz * 6 - 15) + 10)

        def wrap(i, p):
            return ((i % p) if p else i) & 255

        X0, X1 = wrap(xi, period[0]), wrap(xi + 1, period[0])
        Y0, Y1 = wrap(yi, period[1]), wrap(yi + 1, period[1])
        Z0, Z1 = wrap(zi, period[2]), wrap(zi + 1, period[2])
        P = self.perm
        A, B = P[X0], P[X1]
        AA, AB, BA, BB = P[A + Y0], P[A + Y1], P[B + Y0], P[B + Y1]
        gx, gy, gz = self.gx, self.gy, self.gz

        def c(h, dx, dy, dz):
            return gx[h] * dx + gy[h] * dy + gz[h] * dz

        fx1, fy1, fz1 = fx - 1, fy - 1, fz - 1
        n000 = c(P[AA + Z0], fx, fy, fz)
        n100 = c(P[BA + Z0], fx1, fy, fz)
        n010 = c(P[AB + Z0], fx, fy1, fz)
        n110 = c(P[BB + Z0], fx1, fy1, fz)
        n001 = c(P[AA + Z1], fx, fy, fz1)
        n101 = c(P[BA + Z1], fx1, fy, fz1)
        n011 = c(P[AB + Z1], fx, fy1, fz1)
        n111 = c(P[BB + Z1], fx1, fy1, fz1)
        a = n000 + u * (n100 - n000)
        b = n010 + u * (n110 - n010)
        cc = n001 + u * (n101 - n001)
        d = n011 + u * (n111 - n011)
        e = a + v * (b - a)
        f = cc + v * (d - cc)
        return e + w * (f - e)


def fbm(nz, x, y, z=0.0, octaves=4, gain=0.5, period=(0, 0, 0)):
    """フラクタルノイズ。おおむね [-1, 1]（標準偏差 0.25 前後）。周期は 1 オクターブごとに 2 倍。"""
    s = 0.0
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        k = 2 ** o
        per = tuple(p * k for p in period)
        s = s + amp * nz(x * k + o * 17.13, y * k - o * 9.71, z * k + o * 3.37, per)
        tot += amp
        amp *= gain
    return s / tot * 2.0


def billow(nz, x, y, z=0.0, octaves=4, period=(0, 0, 0)):
    """|ノイズ| を重ねたもの（丸いこぶ・谷が細い）。おおむね [0, 1]。"""
    s = 0.0
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        k = 2 ** o
        per = tuple(p * k for p in period)
        s = s + amp * np.abs(nz(x * k + o * 7.31, y * k + o * 3.17, z * k - o * 5.53, per))
        tot += amp
        amp *= 0.5
    return np.clip(s / tot / 0.36, 0.0, 1.0)


def n01(v):
    """fbm の値をおおむね [0, 1] へ。"""
    return np.clip(0.5 + 0.5 * v, 0.0, 1.0)


def loop_fbm(nz, x, y, t, fy, speed, pz, octaves=4):
    """ループ用の fbm。模様は上へ 1 ループで speed（正規化座標）流れ、時間方向に pz 格子進む。

    縦と時間の格子に周期を持たせるので t = 0 と t = 1 が同じ絵になる（fy * speed は整数にする）。
    """
    s = fy * speed
    si = int(round(s))
    assert abs(s - si) < 1e-9, "fy * speed must be an integer"
    return fbm(nz, x, y * fy - si * t, pz * t, octaves, period=(0, si, pz))


def dissolve(a, field, keep, soft=0.05):
    """field の低いところから溶かす。a の総量（アルファの和）で keep の割合が残るしきい値を分位点で決める。

    ノイズの値の分布に左右されず、コマごとの消え方が一定の速さになる。
    """
    if keep >= 0.999:
        return a
    if keep <= 0.001:
        return np.zeros_like(a)
    w = a.ravel()
    sel = w > 1e-3
    if not sel.any():
        return a
    fs, ws = field.ravel()[sel], w[sel]
    order = np.argsort(fs, kind="stable")
    cum = np.cumsum(ws[order])
    cum /= cum[-1]
    e = fs[order][min(int(np.searchsorted(cum, 1.0 - keep)), len(fs) - 1)]
    return a * sstep(e - soft, e + soft, field)


def keep_curve(t, t0, t1=1.04, p=1.0):
    """t0 までは 1、t1 で 0 になる残り率。"""
    return 1.0 - float(sstep(t0, t1, t)) ** p


# --- 描画の小道具 -----------------------------------------------------------------------------------

def stroke(canvas, pts, radii, values, ss):
    """太さ・明るさが変わる折れ線を、画素の被覆率で滑らかに描く（max 合成）。

    pts: (M, 2) 正規化座標、radii: (M,) 最終解像度の px での半径、values: (M,) 0..1。
    """
    n = canvas.shape[0]
    pts = np.asarray(pts, np.float64)
    radii = np.broadcast_to(np.asarray(radii, np.float64), (len(pts),)) * ss
    values = np.broadcast_to(np.asarray(values, np.float64), (len(pts),))
    px, py = to_px(pts, ss)
    for j in range(len(pts) - 1):
        ax, ay, bx, by = px[j], py[j], px[j + 1], py[j + 1]
        ra, rb = radii[j], radii[j + 1]
        va, vb = values[j], values[j + 1]
        if max(va, vb) <= 0.0 or max(ra, rb) <= 0.0:
            continue
        m = max(ra, rb) + 2.0
        x0 = int(max(0, math.floor(min(ax, bx) - m)))
        x1 = int(min(n, math.ceil(max(ax, bx) + m) + 1))
        y0 = int(max(0, math.floor(min(ay, by) - m)))
        y1 = int(min(n, math.ceil(max(ay, by) + m) + 1))
        if x0 >= x1 or y0 >= y1:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1, dtype=np.float64), np.arange(y0, y1, dtype=np.float64))
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        if L2 < 1e-12:
            t = np.zeros_like(gx)
        else:
            t = np.clip(((gx - ax) * dx + (gy - ay) * dy) / L2, 0.0, 1.0)
        d = np.hypot(gx - (ax + t * dx), gy - (ay + t * dy))
        r = ra + (rb - ra) * t
        cov = np.clip(r - d + 0.5, 0.0, 1.0)
        val = (va + (vb - va) * t) * cov
        sub = canvas[y0:y1, x0:x1]
        np.maximum(sub, val, out=sub)


def fill_poly(canvas, poly, ss, a0, a1=None, g0=None, g1=None):
    """多角形を塗る（over 合成）。g0 → g1 の向きに a0 → a1 の直線グラデーション。"""
    n = canvas.shape[0]
    poly = np.asarray(poly, np.float64)
    px, py = to_px(poly, ss)
    x0 = int(max(0, math.floor(px.min()) - 1))
    x1 = int(min(n, math.ceil(px.max()) + 2))
    y0 = int(max(0, math.floor(py.min()) - 1))
    y1 = int(min(n, math.ceil(py.max()) + 2))
    if x0 >= x1 or y0 >= y1:
        return
    mask = np.zeros((y1 - y0, x1 - x0), np.uint8)
    sh = 4
    pts = np.stack([(px - x0) * (1 << sh), (py - y0) * (1 << sh)], axis=1).round().astype(np.int32)
    cv2.fillPoly(mask, [pts], 255, lineType=cv2.LINE_AA, shift=sh)
    m = mask.astype(np.float64) / 255.0
    if a1 is None or g0 is None:
        val = np.full_like(m, a0)
    else:
        q0 = np.array(to_px(np.asarray(g0, np.float64), ss)) - np.array([x0, y0])
        q1 = np.array(to_px(np.asarray(g1, np.float64), ss)) - np.array([x0, y0])
        gx, gy = np.meshgrid(np.arange(x1 - x0, dtype=np.float64), np.arange(y1 - y0, dtype=np.float64))
        dq = q1 - q0
        tt = np.clip(((gx - q0[0]) * dq[0] + (gy - q0[1]) * dq[1]) / max(1e-9, dq @ dq), 0.0, 1.0)
        val = a0 + (a1 - a0) * tt
    sub = canvas[y0:y1, x0:x1]
    sub[...] = sub * (1.0 - m) + val * m


def jagged(p0, p1, depth, rough, rng, decay=0.58):
    """中点変位で折れ線を作る（2^depth + 1 点）。rough は線分の長さに対する横ずれの比。"""
    pts = np.array([p0, p1], np.float64)
    amp = rough
    for _ in range(depth):
        new = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            d = b - a
            nrm = np.array([-d[1], d[0]])
            mid = (a + b) * 0.5 + nrm * rng.normal(0.0, amp) + d * rng.normal(0.0, amp * 0.25)
            new += [mid, b]
        pts = np.array(new)
        amp *= decay
    return pts


def clip_half(poly, p, nrm):
    """多角形を半平面 (x - p)·nrm >= 0 で切る（Sutherland–Hodgman）。"""
    out = []
    m = len(poly)
    for k in range(m):
        a, b = poly[k], poly[(k + 1) % m]
        da, db = (a - p) @ nrm, (b - p) @ nrm
        if da >= 0:
            out.append(a)
        if (da >= 0) != (db >= 0):
            out.append(a + (b - a) * (da / (da - db)))
    return np.array(out) if len(out) >= 3 else None


# --- 1. smoke_puff ---------------------------------------------------------------------------------

def fx_smoke_puff():
    """土煙・煙の一吹き。大小のこぶ（メタボール）をドメインワープした fbm で崩し、約 1.6 倍に広がって縁から内側へ溶ける。"""
    ss = 2
    X, Y = grid(ss)
    nA, nB, nC, nD, nE = (Perlin3(s) for s in (1101, 1102, 1103, 1104, 1106))
    rng = np.random.default_rng(1105)
    lobes = [(0.0, 0.0, 0.50, 2.0)]
    for k in range(6):
        phi = 2 * math.pi * (k + rng.uniform(0.3, 0.7)) / 6
        dist = rng.uniform(0.34, 0.46)
        lobes.append((dist * math.cos(phi), dist * math.sin(phi), rng.uniform(0.33, 0.41), 2.0))
    for k in range(16):
        phi = 2 * math.pi * (k + rng.uniform(0.2, 0.8)) / 16
        dist = rng.uniform(0.58, 0.74)
        lobes.append((dist * math.cos(phi), dist * math.sin(phi), rng.uniform(0.13, 0.21), 2.4))
    out = []
    for i in range(FRAMES):
        t = i / (FRAMES - 1)
        R = 0.48 * (1.0 + 0.60 * ease_out(t, 2.4))  # 0.48 → 0.77（1.6 倍）
        cy = 0.05 * ease_out(t, 1.5)
        px, py = X / R, (Y - cy) / R
        z = 0.7 * t
        wx = fbm(nA, px * 1.6 + 3.1, py * 1.6 - 1.7, z, 4)
        wy = fbm(nA, px * 1.6 - 5.3, py * 1.6 + 2.9, z + 5.0, 4)
        qx, qy = px + 0.11 * wx, py + 0.11 * wy
        spread = 1.0 + 0.16 * ease_out(t, 1.8)
        union = np.zeros_like(X)
        top = np.zeros_like(X)
        for cx, cyy, rho, kk in lobes:
            d = np.hypot(qx - cx * spread, qy - cyy * spread) / (rho * (1.0 + 0.12 * t))
            g = np.exp(-kk * d * d)
            union = 1.0 - (1.0 - union) * (1.0 - g)
            top = np.maximum(top, g)
        fine = billow(nB, qx * 4.0, qy * 4.0, z, 4)
        edge = sstep(0.18, 0.66, union + 0.26 * (fine - 0.5))
        soft = n01(fbm(nC, qx * 2.6 + 9.0, qy * 2.6, z * 0.8, 4))
        shade = 0.40 + 0.60 * top ** 0.6 * (0.55 + 0.45 * soft)
        a = edge * shade
        # 縁から内側へ（ノイズの谷から）やわらかく溶ける
        er = n01(fbm(nD, qx * 2.6, qy * 2.6, z * 1.5, 4))
        er2 = n01(fbm(nE, qx * 6.0, qy * 6.0, z * 2.0, 3))
        field = 0.45 * er + 0.15 * er2 + 0.40 * union
        a = dissolve(a, field, keep_curve(t, 0.22, 1.04, 1.15), soft=0.08)
        a = 0.80 * (1.0 - 0.3 * t) * np.clip(a * 1.2, 0.0, 1.0)
        out.append(down(a, ss))
    return out


# --- 2. fire_burst ---------------------------------------------------------------------------------

def fx_fire_burst():
    """炎の爆発。最初の 2〜3 コマは白い芯、そこから炎の舌が外・上へ伸び、千切れて上へ流れる炎になって消える。"""
    ss = 2
    X, Y = grid(ss)
    nA, nB, nC, nD, nE, nF = (Perlin3(s) for s in (2101, 2102, 2103, 2104, 2105, 2106))
    out = []
    for i in range(FRAMES):
        t = i / (FRAMES - 1)
        R = 0.38 + 0.36 * ease_out(t, 2.6)  # 0.38 → 0.74
        rise = 0.14 * t ** 1.3
        x, y = X, Y - rise
        yy = np.where(y > 0, y / (1.0 + 0.7 * t), y * 1.15)
        z = 1.5 * t
        adv = 1.4 * t
        wx = fbm(nA, x * 2.4 + 1.3, (y - adv) * 2.4, z, 4)
        wy = fbm(nA, x * 2.4 - 4.1, (y - adv) * 2.4 + 3.3, z + 4.0, 4)
        k = 0.09 + 0.13 * t
        qx, qy = x + k * wx, yy + k * wy
        r = np.hypot(qx, qy)
        th = np.arctan2(qy, qx)
        # 炎の舌: 角度のノイズ（円周上でサンプル）で縁を外へ。上向きほど長い
        tong = n01(fbm(nB, np.cos(th) * 3.4 + 5.0, np.sin(th) * 3.4 - 2.0, 1.2 * t, 3) * 1.3)
        up = np.clip(np.sin(th), 0.0, 1.0)
        redge = R * (0.60 + 0.70 * tong ** 2 * (0.45 + 0.85 * up))
        d = r / redge
        turb = fbm(nC, qx * 4.5, (qy - 1.8 * t) * 4.5, z * 1.3, 4)
        body = sstep(1.0, 0.45, d + 0.24 * turb)
        # 上へなめる細い炎（縦に伸ばしたノイズ）
        lick_n = n01(fbm(nE, x * 6.0, (y - 2.2 * t) * 2.0, z, 3))
        lick_env = sstep(1.55, 0.80, d) * sstep(-0.1, 0.45, qy / R) * sstep(0.0, 0.12, t)
        licks = sstep(0.56, 0.80, lick_n) * lick_env
        dens = np.maximum(body, licks * 0.8)
        # 中のこぶ・すす（アルファの濃淡）と白い芯
        crease = billow(nD, qx * 3.2, (qy - 0.8 * t) * 3.2, z, 4)
        tex = 0.42 + 0.58 * crease
        heat = 1.0 - sstep(0.05, 0.42, t)
        core = sstep(0.78, 0.30, d + 0.20 * turb) * heat
        a = np.clip(np.maximum(dens * tex * 0.86, core), 0.0, 1.0)
        # 中心が燃え尽きて抜ける
        a = a * (1.0 - 0.6 * sstep(0.3, 0.9, t) * np.exp(-((r / (0.5 * R)) ** 2)))
        # 千切れて上へ流れる炎に（下・内側・谷から先に消える）
        det = n01(fbm(nF, qx * 5.5, (qy - 2.4 * t) * 5.5, z, 4))
        field = 0.60 * det + 0.25 * np.clip(qy / R * 0.5 + 0.5, 0, 1) + 0.15 * (1.0 - np.clip(d, 0, 1))
        a = dissolve(a, field, keep_curve(t, 0.30, 1.04, 1.1), soft=0.05)
        a = a * (1.0 - 0.25 * sstep(0.5, 1.0, t))
        out.append(down(a, ss))
    return out


# --- 3. flame_loop ---------------------------------------------------------------------------------

def fx_flame_loop():
    """上へ揺らめく 1 本の炎（根元が広く先が細い）。ノイズの縦と時間に周期を持たせ、16 コマで継ぎ目なくループ。"""
    ss = 2
    X, Y = grid(ss)
    nA, nB, nC, nD = Perlin3(3101), Perlin3(3102), Perlin3(3103), Perlin3(3104)
    V = 2.0  # 模様が 1 ループで上へ流れる距離（正規化座標）
    base_y, height = -0.88, 1.68
    out = []
    for i in range(FRAMES):
        t = i / FRAMES
        h = (Y - base_y) / height  # 0 = 根元、1 = 先
        hc = np.clip(h, 0.0, 1.3)
        sway = loop_fbm(nA, X * 1.0, Y, t, 1.0, V, 1, 3)
        turb = loop_fbm(nB, X * 3.0, Y, t, 3.0, V, 2, 4)
        xd = X + (0.03 + 0.22 * hc ** 1.5) * sway * 1.5 + 0.04 * turb * hc
        W0 = 0.37 * (1.0 + 0.06 * math.sin(2 * math.pi * t) + 0.04 * math.sin(4 * math.pi * t + 1.0))
        hb = 0.22
        lower = np.sqrt(np.clip(1.0 - ((h - hb) / hb) ** 2, 0.0, 1.0))
        upper = np.clip((1.0 - h) / (1.0 - hb), 0.0, 1.0) ** 1.25
        w = W0 * np.where(h < hb, lower, upper) + 1e-4
        q = np.abs(xd) / w
        shape = sstep(1.0, 0.45, q + 0.25 * turb * (0.4 + hc)) * sstep(-0.03, 0.05, h)
        cw = 0.55 * W0 * np.where(h < hb, lower, np.clip((0.60 - h) / (0.60 - hb), 0.0, 1.0) ** 1.1) + 1e-4
        core = sstep(1.0, 0.30, np.abs(xd) / cw + 0.20 * turb) * sstep(0.0, 0.08, h)
        det = n01(loop_fbm(nC, X * 4.5, Y, t, 4.5, V, 2, 3))
        # 先端は外側から削れて二股・三股の舌になる
        thr = 0.85 * sstep(0.42, 1.05, h)
        fld = 0.55 * det + 0.45 * np.clip(1.0 - q, 0.0, 1.0)
        shape = shape * sstep(thr - 0.05, thr + 0.10, fld + 0.12)
        tex = 0.60 + 0.40 * det ** 1.2
        a = np.clip(shape * tex * 0.74 + core, 0.0, 1.0)
        # 先から千切れて昇る小さな炎（1 ループに 2 つ）
        for b in range(2):
            life = ((t + 0.5 * b + 0.15) % 1.0) / 0.45
            if life >= 1.0:
                continue
            by = 0.42 + 0.40 * life
            bx = 0.05 * math.sin(2 * math.pi * (life * 0.7 + b * 0.37)) + (0.04 if b else -0.03)
            size = 0.075 * (1.0 - 0.6 * life)
            dx = (X - bx) / size
            dy = (Y - by) / (size * 1.8)
            blob = sstep(1.0, 0.3, np.hypot(dx, np.where(dy > 0, dy * 0.7, dy * 1.3)) + 0.35 * turb)
            a = np.maximum(a, blob * math.sin(math.pi * life) ** 0.8 * 0.85)
        out.append(down(a, ss))
    return out


# --- 4. electric_arc -------------------------------------------------------------------------------

def fx_electric_arc():
    """中心を横切る枝分かれした稲妻 2〜3 本。芯は 1〜2 px のアルファ 255、周りにやわらかい光。コマごとに配置が変わる（明滅）。"""
    ss = 4
    out = []
    for i in range(FRAMES):
        rng = np.random.default_rng(4100 + i)
        core = np.zeros((CELL * ss, CELL * ss))
        nb = 3 if (i % 3 != 1) else 2
        a0 = rng.uniform(0, math.pi)
        for b in range(nb):
            ang = a0 + b * math.pi / nb + rng.uniform(-0.25, 0.25)
            dirv = np.array([math.cos(ang), math.sin(ang)])
            c = rng.uniform(-0.10, 0.10, 2)
            r0, r1 = rng.uniform(0.62, 0.80), rng.uniform(0.62, 0.80)
            p0, p1 = c + dirv * r0, c - dirv * r1
            main = jagged(p0, p1, 6, 0.20, rng, decay=0.52)
            s = np.linspace(0, 1, len(main))
            taper = np.sin(np.pi * s) ** 0.45
            core_r = (0.55 + 0.45 * rng.uniform(0.7, 1.0)) * (0.35 + 0.65 * taper)
            stroke(core, main, core_r, 0.55 + 0.45 * taper, ss)
            # 枝
            for _ in range(rng.integers(2, 5)):
                j = int(rng.integers(8, len(main) - 12))
                d = main[j + 3] - main[j]
                d /= np.linalg.norm(d) + 1e-9
                side = rng.choice([-1, 1])
                bd = rot(side * rng.uniform(0.35, 0.95)) @ d
                L = rng.uniform(0.14, 0.34)
                q1 = main[j] + bd * L
                br = jagged(main[j], q1, 4, 0.24, rng, decay=0.52)
                sb = np.linspace(0, 1, len(br))
                stroke(core, br, 0.7 * (1.0 - 0.75 * sb) * taper[j] + 0.15, 0.85 * (1 - 0.6 * sb) * taper[j], ss)
                if rng.random() < 0.5:
                    k = int(rng.integers(3, len(br) - 4))
                    d2 = br[k + 2] - br[k]
                    d2 /= np.linalg.norm(d2) + 1e-9
                    q2 = br[k] + rot(-side * rng.uniform(0.3, 0.8)) @ d2 * rng.uniform(0.07, 0.16)
                    br2 = jagged(br[k], q2, 3, 0.25, rng)
                    s2 = np.linspace(0, 1, len(br2))
                    stroke(core, br2, 0.35 * (1 - 0.7 * s2) + 0.12, 0.6 * (1 - 0.7 * s2) * taper[j], ss)
        c128 = down(core, ss)
        g1 = blur(c128, 2.0)
        g2 = blur(c128, 6.0)
        glow = 1.0 - np.exp(-(g1 * 2.6 + g2 * 3.2))
        flick = 0.88 + 0.12 * rng.random()
        a = np.maximum(np.clip(c128 * 1.6, 0, 1), glow * 0.62) * flick
        out.append(a)
    return out


# --- 5. energy_burst -------------------------------------------------------------------------------

def fx_energy_burst():
    """放射状の衝撃。0〜1 コマは白い円の閃光、その後ノイズで崩れた衝撃の輪と光の筋が広がり、縁から溶けて消える。"""
    ss = 2
    X, Y = grid(ss)
    r = np.hypot(X, Y)
    th = np.arctan2(Y, X)
    nA, nB, nC, nD = Perlin3(5101), Perlin3(5102), Perlin3(5103), Perlin3(5105)
    rng = np.random.default_rng(5104)
    K = 28
    ray_ang = rng.uniform(-math.pi, math.pi, K)
    ray_w = rng.uniform(0.010, 0.024, K)
    ray_in = rng.uniform(0.18, 0.42, K)
    ray_out = rng.uniform(0.02, 0.12, K)
    ray_amp = rng.uniform(0.45, 1.0, K)
    flash_amp = [1.0, 1.0, 0.55, 0.22, 0.06]
    out = []
    for i in range(FRAMES):
        tt = np.clip((i - 1) / (FRAMES - 2), 0.0, 1.0)
        a = np.zeros_like(X)
        if i < len(flash_amp):
            rf = 0.30 + 0.07 * i
            edge_n = fbm(nA, np.cos(th) * 3.0, np.sin(th) * 3.0, i * 0.3, 4)
            loc = fbm(nD, X * 6.0, Y * 6.0, i * 0.2, 3)
            rfn = rf * (1.0 + 0.12 * edge_n) + 0.02 * loc
            disk = sstep(rfn, rfn - 0.07, r)
            halo = np.exp(-((r / (rf * 1.4)) ** 2) * 1.3) * 0.55
            a = np.maximum(a, flash_amp[i] * np.clip(disk + halo, 0, 1))
        if i >= 1:
            rr = 0.24 + 0.54 * ease_out(tt, 2.3)  # 0.24 → 0.78
            ang_n = fbm(nB, np.cos(th) * 2.5, np.sin(th) * 2.5, tt * 1.2, 4)
            zx, zy = X / (0.6 + rr), Y / (0.6 + rr)
            loc_n = fbm(nC, zx * 4.0, zy * 4.0, tt * 1.5, 4)
            rn = rr * (1.0 + 0.07 * ang_n) + 0.025 * loc_n
            dr = r - rn
            wtrail = 0.05 + 0.10 * tt
            inner = np.where(dr < 0, np.exp(-np.clip(-dr, 0, None) / wtrail), 0.0)
            outer = np.where(dr >= 0, np.exp(-(np.clip(dr, 0, None) / 0.020) ** 2), 0.0)
            ring = inner * 0.62 + outer + 0.5 * np.exp(-(dr / 0.016) ** 2)
            rays = np.zeros_like(X)
            for k in range(K):
                dth = np.angle(np.exp(1j * (th - ray_ang[k])))
                perp = np.abs(dth) * np.maximum(r, 0.05)
                r_out = rn + ray_out[k] * (1.0 - 0.4 * tt)
                r_in = rn - ray_in[k] * (0.5 + 0.6 * tt)
                along = (r - r_in) / np.maximum(r_out - r_in, 1e-3)
                pk = (rn - r_in) / np.maximum(r_out - r_in, 1e-3)
                prof = np.where(along < pk, sstep(0.0, pk, along) ** 1.5, sstep(1.0, pk, along))
                wk = ray_w[k] * (1.0 - 0.45 * tt) * (0.4 + 0.6 * np.clip(along, 0, 1))
                rays = np.maximum(rays, ray_amp[k] * prof * np.exp(-(perp / wk) ** 2))
            body = np.clip(ring + rays * 0.95, 0.0, 1.0)
            er = n01(fbm(nA, zx * 5.0 + 11.0, zy * 5.0, tt * 2.0, 4))
            field = 0.80 * er + 0.20 * np.clip(1.0 - np.abs(dr) / 0.2, 0, 1)
            body = dissolve(body, field, keep_curve(tt, 0.28, 1.04, 1.1), soft=0.045)
            body = body * (1.0 - 0.45 * sstep(0.5, 1.0, tt))
            a = np.maximum(a, body)
        out.append(down(np.clip(a, 0, 1), ss))
    return out


# --- 6. shock_ring ---------------------------------------------------------------------------------

def fx_shock_ring():
    """地面の衝撃波の輪。細く明るい先端が半径 0.15 → 0.45（コマの大きさ比）へ広がり、内側へやわらかい光を引く。縁はノイズで途切れて崩れる。"""
    ss = 2
    X, Y = grid(ss)
    r = np.hypot(X, Y)
    th = np.arctan2(Y, X)
    nA, nB, nC, nD, nE = (Perlin3(s) for s in (6101, 6102, 6103, 6105, 6106))
    rng = np.random.default_rng(6104)
    K = 44
    sc_ang = rng.uniform(-math.pi, math.pi, K)
    sc_len = rng.uniform(0.06, 0.18, K)
    sc_amp = rng.uniform(0.25, 0.6, K)
    out = []
    for i in range(FRAMES):
        t = i / (FRAMES - 1)
        rr = 0.30 + 0.60 * ease_out(t, 2.0)  # 0.15 → 0.45（コマ比）
        ang = fbm(nA, np.cos(th) * 3.0, np.sin(th) * 3.0, t * 1.4, 4)
        loc = fbm(nB, X * 6.0, Y * 6.0, t * 1.2, 3)
        rn = rr * (1.0 + 0.028 * ang) + 0.010 * loc
        dr = r - rn
        thick = n01(fbm(nD, np.cos(th) * 2.5 + 4.0, np.sin(th) * 2.5, t, 3) * 1.4)
        width = (1.0 + 2.4 * thick) * PX * (1.0 - 0.35 * t)
        edge = np.where(dr > 0, np.exp(-(dr / (1.0 * PX)) ** 2), np.exp(-(np.clip(-dr, 0, None) / width) ** 2))
        edge = edge * (0.62 + 0.38 * thick)
        trail_w = 0.06 + 0.20 * rr
        trail = np.where(dr < 0, np.exp(-(np.clip(-dr, 0, None) / trail_w) ** 1.3), 0.0)
        mott = n01(fbm(nE, X * 5.0, Y * 5.0, t * 1.5, 4))
        trail = trail * (0.30 + 0.20 * mott) * (1.0 - t) ** 0.8
        scr = np.zeros_like(X)
        for k in range(K):
            dth = np.angle(np.exp(1j * (th - sc_ang[k])))
            perp = np.abs(dth) * np.maximum(r, 0.05)
            along = (rn - r) / sc_len[k]
            prof = sstep(-0.05, 0.15, along) * sstep(1.0, 0.2, along)
            scr = np.maximum(scr, sc_amp[k] * prof * np.exp(-(perp / (1.0 * PX)) ** 2))
        ring = np.clip(edge + scr * (1.0 - 0.6 * t), 0.0, 1.0)
        # 縁の途切れ: 細かいノイズと角度のノイズの谷から抜ける（最初から少し切れている）
        gaps = n01(fbm(nC, np.cos(th) * 4.0, np.sin(th) * 4.0, t * 2.0, 4))
        gaps2 = n01(fbm(nC, X * 9.0 + 3.0, Y * 9.0, t * 2.5, 3))
        field = gaps * 0.40 + gaps2 * 0.60
        ring = dissolve(ring, field, 0.94 * keep_curve(t, 0.15, 1.03, 1.1), soft=0.035)
        trail = trail * sstep(0.25, 0.55, gaps2 + 0.5 * (1.0 - t))
        a = np.clip(np.maximum(ring, trail), 0.0, 1.0) * (1.0 - 0.4 * sstep(0.55, 1.0, t))
        out.append(down(a, ss))
    return out


# --- 7. slash_fade ---------------------------------------------------------------------------------

def fx_slash_fade():
    """三日月形の斬撃（上半分・左から右へ振る）。0〜2 コマで弧が伸び、その後ノイズで削れつつ外へ少し流れて消える。"""
    ss = 2
    X, Y = grid(ss)
    cy = -0.16
    xr, yr = X, Y - cy
    r = np.hypot(xr, yr)
    th = np.arctan2(yr, xr)
    th = np.where(th < -math.pi / 2, th + 2 * math.pi, th)  # [-π/2, 3π/2)
    th_s, th_e = math.pi + 0.16, -0.10
    s = (th_s - th) / (th_s - th_e)  # 0 = 左端（振り始め）、1 = 右端
    inarc = (s > 0) & (s < 1)
    sc = np.clip(s, 0, 1)
    nA, nB = Perlin3(7101), Perlin3(7102)
    sweep = [0.42, 0.78, 1.10]
    out = []
    for i in range(FRAMES):
        tt = np.clip((i - 2) / (FRAMES - 3), 0.0, 1.0)
        Ro = 0.78 + 0.07 * ease_out(tt, 1.6)
        tau_max = 0.32 * (1.0 - 0.30 * tt)
        if i < len(sweep):
            head = sweep[i]
            boost = 1.0 + 0.30 * np.exp(-((sc - head) / 0.16) ** 2)
        else:
            head = 2.0
            boost = 1.0
        prof = np.sin(np.pi * sc ** 0.8) ** 1.1
        tau = tau_max * prof * boost + 1e-4
        streak = fbm(nA, sc * 2.5, r * 18.0, tt * 1.5 + i * 0.05, 4)
        Ron = Ro + 0.010 * streak
        q = (Ron - r) / tau  # 0 = 外縁、1 = 内縁
        qc = np.clip(q, 0.0, 1.0)
        lines = n01(streak * 1.3) ** 1.3
        body = (1.0 - qc) ** 1.4 * (0.35 + 0.65 * lines)
        body = np.maximum(body, sstep(0.32, 0.0, q))  # 外縁の太く明るい刃
        body = np.where((q >= 0) & (q <= 1), body, 0.0) * sstep(1.0, 0.8, q)
        outer = np.where(q < 0, np.exp(-((r - Ron) / (1.3 * PX)) ** 2), 0.0) * prof ** 0.3
        # 内側の細い追い筋（二重の斬撃線）
        s2 = np.clip((s - 0.18) / 0.70, 0.0, 1.0)
        r2 = Ron - 0.55 * tau_max * np.sin(np.pi * s2) ** 0.9 - 0.03
        line2 = np.exp(-((r - r2) / (1.1 * PX)) ** 2) * np.sin(np.pi * s2) ** 1.2 * 0.6
        a = np.clip(body + outer + line2, 0.0, 1.0)
        a = a * sstep(head + 0.05, head - 0.08, sc)
        if tt > 0:
            ero = n01(fbm(nB, sc * 6.0, r * 10.0, tt * 2.0, 4))
            field = 0.55 * ero + 0.30 * (1.0 - qc) + 0.15 * sc
            a = dissolve(a, field, keep_curve(tt, 0.0, 1.03, 0.85), soft=0.04)
            a = a * (1.0 - 0.3 * tt)
        a = np.where(inarc, a, 0.0)
        out.append(down(np.clip(a, 0, 1), ss))
    return out


# --- 8. ice_shatter --------------------------------------------------------------------------------

def _ice_shards(rng):
    shards = []
    N = 11
    base = rng.uniform(0, 2 * math.pi)
    for k in range(N):
        ang = base + 2 * math.pi * k / N + rng.uniform(-0.18, 0.18)
        L = rng.uniform(0.34, 0.62) if k % 3 else rng.uniform(0.52, 0.66)
        W = rng.uniform(0.07, 0.13)
        r0 = rng.uniform(0.0, 0.07)
        shards.append(dict(ang=ang, L=L, W=W, r0=r0,
                           mid=rng.uniform(0.45, 0.65), wl=rng.uniform(0.75, 1.0), wr=rng.uniform(0.7, 1.0),
                           tip=rng.uniform(-0.25, 0.25) * W,
                           cuts=sorted(rng.uniform(0.3, 0.75, int(rng.integers(1, 3)))),
                           tilt=rng.uniform(-0.6, 0.6, 3), lit=rng.uniform(0.75, 1.0)))
    return shards


def _shard_facets(sh):
    """1 本の氷柱を軸の左右 2 面に分けた局所座標の多角形（a = 軸方向, b = 横）。"""
    r0, L, W = sh["r0"], sh["L"], sh["W"]
    bl = np.array([r0, -W])
    ml = np.array([r0 + sh["mid"] * L, -W * sh["wl"]])
    tip = np.array([r0 + L, sh["tip"]])
    mr = np.array([r0 + (sh["mid"] - 0.08) * L, W * sh["wr"]])
    br = np.array([r0, W])
    sp = np.array([r0 + 0.05 * L, 0.0])
    return [np.array([bl, ml, tip, sp]), np.array([sp, tip, mr, br])], np.array([bl, ml, tip, mr, br])


def fx_ice_shatter():
    """氷の結晶片の塊。とがった多角形の面（縁が明るく、面ごとに濃淡）が現れ、ひびが入り、外へ割れ飛んで消える。"""
    ss = 4
    rng = np.random.default_rng(8101)
    shards = _ice_shards(rng)
    # 割れた後の破片（各氷柱をひびの線で切る）
    pieces = []
    for si, sh in enumerate(shards):
        facets, outline = _shard_facets(sh)
        cuts = [sh["r0"] + c * sh["L"] for c in sh["cuts"]]
        bounds = [-1.0] + cuts + [9.0]
        for pi in range(len(bounds) - 1):
            lo, hi = bounds[pi], bounds[pi + 1]
            tl = sh["tilt"][pi % 3]
            pf = []
            for fct in facets + [outline]:
                poly = fct
                if lo > -1:
                    poly = clip_half(poly, np.array([lo, 0.0]), np.array([1.0, tl]))
                if poly is not None and hi < 9:
                    poly = clip_half(poly, np.array([hi, 0.0]), np.array([-1.0, -sh["tilt"][(pi + 1) % 3]]))
                pf.append(poly)
            if pf[-1] is None:
                continue
            cen = pf[-1].mean(axis=0)
            pieces.append(dict(shard=si, facets=pf[:2], outline=pf[-1], cen=cen,
                               v=rng.uniform(0.10, 0.22) + 0.25 * cen[0], vs=rng.normal(0, 0.05),
                               w=rng.normal(0, 0.9), fade=rng.uniform(0.70, 1.0)))
    dust = [dict(ang=rng.uniform(0, 2 * math.pi), v=rng.uniform(0.35, 0.75), r=rng.uniform(0.6, 1.4),
                 t0=rng.uniform(0.0, 0.25)) for _ in range(26)]
    out = []
    for i in range(FRAMES):
        canvas = np.zeros((CELL * ss, CELL * ss))
        lines = np.zeros_like(canvas)
        grow = [0.70, 0.90, 1.0][i] if i < 3 else 1.0
        tau = np.clip((i - 3) / (FRAMES - 4), 0.0, 1.0)
        for pc in pieces:
            sh = shards[pc["shard"]]
            R = rot(sh["ang"])
            if i <= 3:
                off = np.zeros(2)
                ang_off = 0.0
                scale = grow
                alpha = 1.0
            else:
                travel = ease_out(tau, 1.8)
                off = np.array([pc["v"] * travel, pc["vs"] * travel])
                ang_off = pc["w"] * travel
                scale = 1.0 - 0.35 * tau
                alpha = np.clip(1.0 - (tau / pc["fade"]) ** 1.4, 0, 1)
            if alpha <= 0.01:
                continue

            def xf(poly):
                p = (poly - pc["cen"]) * scale
                p = p @ rot(ang_off).T + pc["cen"] * scale + off * np.array([1.0, 1.0])
                return p @ R.T

            lit = sh["lit"]
            f0, f1 = pc["facets"]
            spine0 = np.array([sh["r0"], 0.0])
            spine1 = np.array([sh["r0"] + sh["L"], 0.0])
            if f0 is not None:
                fill_poly(canvas, xf(f0), ss, 0.95 * lit * alpha, 0.50 * lit * alpha, xf(spine0[None])[0], xf(spine1[None])[0])
            if f1 is not None:
                fill_poly(canvas, xf(f1), ss, 0.40 * alpha, 0.72 * alpha, xf(spine0[None])[0], xf(spine1[None])[0])
            ol = xf(pc["outline"])
            loop = np.vstack([ol, ol[:1]])
            stroke(lines, loop, 0.65, alpha, ss)
            if f0 is not None and f1 is not None:
                # 稜線（2 面の境目）
                sp = xf(np.array([f0[-1], f0[2]]))
                stroke(lines, sp, 0.5, 0.85 * alpha, ss)
        # ひび（割れる直前のコマ）
        if i in (2, 3):
            crng = np.random.default_rng(8200)
            for sh in shards:
                R = rot(sh["ang"])
                for c in sh["cuts"]:
                    a_ = sh["r0"] + c * sh["L"]
                    p0 = np.array([a_ - 0.03, -sh["W"] * 0.9]) @ R.T
                    p1 = np.array([a_ + 0.03, sh["W"] * 0.9]) @ R.T
                    cr = jagged(p0, p1, 3, 0.2, crng)
                    stroke(lines, cr, 0.55, 0.9 if i == 3 else 0.5, ss)
        a = np.maximum(down(canvas, ss), down(lines, ss))
        # 中心の冷気の閃光
        X, Y = grid(1)
        rr = np.hypot(X, Y)
        flash = [0.95, 0.75, 0.45, 0.25, 0.1][i] if i < 5 else 0.0
        if flash > 0:
            a = np.maximum(a, flash * np.exp(-(rr / (0.18 + 0.05 * i)) ** 2))
            a = a + 0.25 * flash * np.exp(-(rr / 0.5) ** 2) * (1 - a)
        # 氷の粉
        if i >= 3:
            dc = np.zeros((CELL * ss, CELL * ss))
            for dd in dust:
                tl = np.clip((tau - dd["t0"]) / (1.0 - dd["t0"]), 0, 1)
                if tl <= 0 or tl >= 1:
                    continue
                rad = 0.15 + dd["v"] * ease_out(tl, 2.0) * 0.85
                p = np.array([math.cos(dd["ang"]), math.sin(dd["ang"])]) * rad
                q = p + np.array([math.cos(dd["ang"]), math.sin(dd["ang"])]) * 0.03 * (1 - tl)
                stroke(dc, np.array([p, q]), dd["r"] * (1 - 0.5 * tl), (1 - tl) ** 1.2, ss)
            a = np.maximum(a, down(dc, ss))
        out.append(np.clip(a, 0, 1))
    return out


# --- 9. spark_twinkle ------------------------------------------------------------------------------

def fx_spark_twinkle():
    """4 方向に光が伸びるきらめき（大きさ・回転・明るさが脈打つ）と小さなきらめき。16 コマで継ぎ目なくループ。"""
    ss = 2
    X, Y = grid(ss)
    r = np.hypot(X, Y)
    rng = np.random.default_rng(9101)
    smalls = [dict(p=np.array([math.cos(a_), math.sin(a_)]) * rad, ph=ph, L=L)
              for a_, rad, ph, L in zip(rng.uniform(0, 2 * math.pi, 6), rng.uniform(0.40, 0.72, 6),
                                        np.arange(6) / 6 + rng.uniform(-0.04, 0.04, 6), rng.uniform(0.09, 0.15, 6))]

    def star(x, y, L, w, rot_):
        c, s = math.cos(rot_), math.sin(rot_)
        u = x * c + y * s
        v = -x * s + y * c
        acc = np.zeros_like(x)
        for along, perp in ((np.abs(u), np.abs(v)), (np.abs(v), np.abs(u))):
            k = np.clip(1.0 - along / L, 0.0, 1.0)
            acc = np.maximum(acc, k ** 1.6 * np.exp(-perp / (w * (0.25 + 0.75 * k) + 1e-6)))
        return acc

    out = []
    for i in range(FRAMES):
        t = i / FRAMES
        pulse = 0.5 - 0.5 * math.cos(2 * math.pi * t)
        sc = 0.55 + 0.45 * pulse ** 1.3
        inten = 0.60 + 0.40 * pulse
        ang = 0.5 * math.pi * t  # 4 回対称なので 90° でちょうど一周
        a = star(X, Y, 0.86 * sc, 0.020, ang)
        a = np.maximum(a, 0.65 * star(X, Y, 0.40 * sc * (0.8 + 0.2 * math.sin(2 * math.pi * t + 1.3) ** 2), 0.012,
                                      ang + math.pi / 4))
        core = np.exp(-(r / (0.075 * sc)) ** 2) + 0.38 * np.exp(-(r / (0.26 * sc)) ** 2)
        a = np.clip(np.maximum(a, core) + 0.25 * core, 0, 1) * inten
        for sm in smalls:
            k = max(0.0, math.sin(2 * math.pi * (t + sm["ph"]))) ** 2
            if k < 0.01:
                continue
            x, y = X - sm["p"][0], Y - sm["p"][1]
            rs = np.hypot(x, y)
            s_ = star(x, y, sm["L"] * (0.4 + 0.6 * k), 0.010, -ang * 0.5)
            s_ = np.maximum(s_, np.exp(-(rs / 0.025) ** 2))
            a = np.maximum(a, k * s_)
        out.append(down(np.clip(a, 0, 1), ss))
    return out


# --- 10. dark_wisp ---------------------------------------------------------------------------------

def _wisp_field(nz, t, n=96):
    """筋を流す速度場: 外向き + 中心の渦 + curl noise。格子 n × n（y 上向き）で返す。"""
    c = (np.arange(n) + 0.5) / n * 2.4 - 1.2
    Xg, Yg = np.meshgrid(c, c)
    h = c[1] - c[0]
    psi = fbm(nz, Xg * 1.4, Yg * 1.4, 0.35 * t, 3)
    dpy, dpx = np.gradient(psi, h)
    rr2 = Xg * Xg + Yg * Yg
    rr = np.sqrt(rr2) + 1e-3
    swirl = 1.6 * np.exp(-rr2 / 0.45)
    vx = 0.50 * Xg / rr * sstep(0.0, 0.12, rr) - swirl * Yg + 0.45 * dpy
    vy = 0.50 * Yg / rr * sstep(0.0, 0.12, rr) + swirl * Xg - 0.45 * dpx
    return c, vx, vy


def _sample(c, field, p):
    """格子の値を双線形で引く（p は (N, 2) の正規化座標）。"""
    h = c[1] - c[0]
    fx = (p[:, 0] - c[0]) / h
    fy = (p[:, 1] - c[0]) / h
    return ndimage.map_coordinates(field, [fy, fx], order=1, mode="nearest")


def fx_dark_wisp():
    """渦を巻く細い煙の筋（魔・血の効果用）。流れ場の流線に沿った長く細い筋が巻き、伸び、ほつれて消える。"""
    ss = 4
    rng = np.random.default_rng(10101)
    nF, nW, nE = Perlin3(10102), Perlin3(10103), Perlin3(10104)
    S = 10
    seeds = []
    for k in range(S):
        ang = 2 * math.pi * (k + rng.uniform(0.2, 0.8)) / S
        seeds.append(dict(ang=ang, r=rng.uniform(0.05, 0.22), L=rng.uniform(0.70, 1.25),
                          w=rng.uniform(0.40, 0.70), amp=rng.uniform(0.65, 1.0), fray=int(rng.integers(2, 4)),
                          spread=rng.uniform(0.012, 0.03), seed=k * 7.3))
    Xs, Ys = grid(1)
    n = CELL
    gx, gy = np.meshgrid(np.arange(n, dtype=np.float32), np.arange(n, dtype=np.float32))
    M = 130
    out = []
    for i in range(FRAMES):
        t = i / (FRAMES - 1)
        c, vx, vy = _wisp_field(nF, t)
        canvas = np.zeros((CELL * ss, CELL * ss))
        for sd in seeds:
            L = sd["L"] * (0.30 + 0.70 * ease_out(t, 1.6))
            ds = L / (M - 1)
            ang = sd["ang"] + 0.6 * t
            p = np.array([[math.cos(ang), math.sin(ang)]]) * sd["r"] * (1.0 + 0.9 * t)
            pts = np.zeros((M, 2))
            tang = np.zeros((M, 2))
            for j in range(M):
                pts[j] = p[0]
                v = np.array([_sample(c, vx, p)[0], _sample(c, vy, p)[0]])
                v = v / (np.linalg.norm(v) + 1e-6)
                tang[j] = v
                p = p + ds * v[None, :]
                rp = np.hypot(*p[0])
                if rp > 0.86:  # 枠に近づいたら外へ出さない
                    p = p * (0.86 / rp)
            s = np.linspace(0, 1, M)
            nrm = np.stack([-tang[:, 1], tang[:, 0]], axis=1)
            alpha_s = np.sin(np.pi * s ** 0.75) ** 0.9 * sd["amp"]
            for f in range(sd["fray"]):
                off = (f - (sd["fray"] - 1) / 2) * (0.004 + sd["spread"] * s ** 1.3 * (0.5 + 1.2 * t))
                fn = fbm(nW, s * 5.0 + f * 3.1, sd["seed"] + f, t, 2)
                q = pts + nrm * (off + 0.02 * fn * s)[:, None]
                wr = sd["w"] * (0.30 + 0.70 * np.sin(np.pi * s) ** 0.6) * (1.0 - 0.35 * f / sd["fray"])
                stroke(canvas, q, wr * (1.0 + 0.7 * t), alpha_s * (1.0 if f == 0 else 0.55), ss)
        a = down(canvas, ss)
        dx = fbm(nW, Xs * 2.0, Ys * 2.0, t * 0.9, 3) * (1.2 + 2.0 * t)
        dy = fbm(nW, Xs * 2.0 + 7.7, Ys * 2.0, t * 0.9 + 3.0, 3) * (1.2 + 2.0 * t)
        a = cv2.remap(a.astype(np.float32), gx + dx.astype(np.float32), gy + dy.astype(np.float32),
                      cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0).astype(np.float64)
        sharp = blur(a, 0.25 + 0.8 * t)
        haze = blur(a, 4.0 + 3.0 * t)
        a = np.clip(sharp * 1.35 + haze * 0.40, 0, 1)
        er = n01(fbm(nE, Xs * 3.5, Ys * 3.5, t * 1.6, 4))
        a = dissolve(a, er * 0.85 + 0.15 * a, keep_curve(t, 0.35, 1.04, 1.1), soft=0.06)
        a = a * (1.0 - 0.35 * sstep(0.5, 1.0, t))
        out.append(np.clip(a, 0, 1))
    return out


# --- 11. ground_crack ------------------------------------------------------------------------------

def _crack_network(rng):
    """中心から放射状に伸びる亀裂。各点に「中心からの到達距離」を持たせ、伸びる順を決める。"""
    paths = []  # (pts(M,2), dist(M,), level)

    def walk(p, heading, target, length, d0, step):
        pts, dist = [p.copy()], [d0]
        h = heading
        n = max(2, int(round(length / step)))
        for _ in range(n):
            h = h + rng.normal(0, 0.36) + 0.30 * np.angle(np.exp(1j * (target - h)))
            sl = step * rng.uniform(0.6, 1.4)
            p = p + sl * np.array([math.cos(h), math.sin(h)])
            if np.hypot(*p) > 0.86:
                break
            pts.append(p.copy())
            dist.append(dist[-1] + sl)
        return np.array(pts), np.array(dist)

    M = 7
    base = rng.uniform(0, 2 * math.pi)
    mains = []
    for k in range(M):
        phi = base + 2 * math.pi * k / M + rng.uniform(-0.28, 0.28)
        start = np.array([math.cos(phi), math.sin(phi)]) * 0.06
        pts, dist = walk(start, phi, phi, rng.uniform(0.60, 0.84), 0.06, 0.05)
        paths.append((pts, dist, 0))
        mains.append((pts, dist))
        for _ in range(int(rng.integers(3, 6))):
            j = int(rng.integers(2, max(3, len(pts) - 3)))
            side = rng.choice([-1, 1])
            hb = phi + side * rng.uniform(0.45, 1.0)
            bp, bd = walk(pts[j], hb, hb - side * 0.25, rng.uniform(0.10, 0.30), dist[j], 0.04)
            paths.append((bp, bd, 1))
            if len(bp) > 3 and rng.random() < 0.6:
                jj = int(rng.integers(1, len(bp) - 1))
                h2 = hb - side * rng.uniform(0.5, 1.1)
                b2, d2 = walk(bp[jj], h2, h2, rng.uniform(0.05, 0.14), bd[jj], 0.03)
                paths.append((b2, d2, 2))
    # 同心円状の短いひび（隣り合う主亀裂の間）
    for k in range(M):
        if rng.random() < 0.65:
            pa, da = mains[k]
            pb, db = mains[(k + 1) % M]
            rad = rng.uniform(0.20, 0.50)
            ja = int(np.argmin(np.abs(np.hypot(pa[:, 0], pa[:, 1]) - rad)))
            jb = int(np.argmin(np.abs(np.hypot(pb[:, 0], pb[:, 1]) - rad * rng.uniform(0.85, 1.15))))
            q1 = pa[ja] + (pb[jb] - pa[ja]) * (rng.uniform(0.35, 0.7) if rng.random() < 0.5 else 1.0)
            cp = jagged(pa[ja], q1, 3, 0.16, rng, decay=0.5)
            seg = np.hypot(*np.diff(cp, axis=0).T)
            cd = da[ja] + np.concatenate([[0], np.cumsum(seg)])
            paths.append((cp, cd, 2))
    return paths


def fx_ground_crack():
    """地面のひび割れ。中心から枝分かれした亀裂が 0〜9 コマで伸び、10〜15 コマで薄れて消える（地面に寝かせて使う）。"""
    ss = 4
    rng = np.random.default_rng(11101)
    paths = _crack_network(rng)
    dmax = max(float(d.max()) for _, d, _ in paths)
    nA, nB = Perlin3(11102), Perlin3(11103)
    X, Y = grid(1)
    rr = np.hypot(X, Y)
    th = np.arctan2(Y, X)
    out = []
    for i in range(FRAMES):
        front = dmax * 1.02 * ease_out((i + 1) / 10.0, 2.0) if i < 10 else dmax * 1.1
        fade = np.clip((i - 9) / 6.4, 0.0, 1.0)
        canvas = np.zeros((CELL * ss, CELL * ss))
        for pts, dist, level in paths:
            k = int((dist <= front).sum())
            if k < 1:
                continue
            q = pts[:k]
            dd = dist[:k]
            if k < len(pts):
                f = (front - dist[k - 1]) / max(1e-6, dist[k] - dist[k - 1])
                q = np.vstack([q, pts[k - 1] + (pts[k] - pts[k - 1]) * np.clip(f, 0, 1)])
                dd = np.append(dd, front)
            if len(q) < 2:
                continue
            rad = np.hypot(q[:, 0], q[:, 1])
            base_w = [1.35, 0.85, 0.6][level]
            w = base_w * (0.35 + 0.65 * np.clip(1.0 - rad / 0.9, 0, 1)) + 0.3
            w = w * (0.4 + 0.6 * np.clip((front - dd) / 0.08, 0.0, 1.0))
            stroke(canvas, q, w, np.full(len(q), 1.0 if level == 0 else 0.92), ss)
        line = down(canvas, ss)
        # 中心の砕けた跡（ギザギザの欠け）
        cn = fbm(nA, X * 7.0, Y * 7.0, 0.3, 4)
        spikes = n01(fbm(nA, np.cos(th) * 4.0 + 9.0, np.sin(th) * 4.0, 0.7, 3))
        crater_r = 0.12 * ease_out(min(1.0, (i + 1) / 3.0), 2.0) * (0.75 + 0.6 * spikes)
        crater = sstep(crater_r * 1.1, crater_r * 0.7, rr * (1.0 + 0.5 * cn)) * (0.55 + 0.45 * n01(cn * 2))
        glow = np.clip(blur(line, 1.6) * 1.2 + blur(line, 4.0) * 0.6, 0, 1) * 0.42 * (1.0 - fade) ** 1.5
        a = np.maximum(np.maximum(line, crater), glow)
        if fade > 0:
            ero = n01(fbm(nB, X * 6.0, Y * 6.0, fade * 1.5, 4))
            field = 0.65 * ero + 0.35 * np.clip(1.0 - rr / 0.9, 0, 1)
            a = dissolve(a, field, keep_curve(float(fade), 0.0, 1.05, 0.9), soft=0.04)
            a = a * (1.0 - 0.4 * fade)
        out.append(np.clip(a, 0, 1))
    return out


# --- 12. hit_flash ---------------------------------------------------------------------------------

def fx_hit_flash():
    """鋭い命中の火花。8 方向の光の棘と白い芯。棘はすぐ縮み、火花の点が飛ぶ。10 コマ目以降は空。"""
    ss = 4
    rng = np.random.default_rng(12101)
    rot0 = rng.uniform(0, math.pi / 4)
    ray_ang = [rot0 + j * math.pi / 4 + rng.uniform(-0.09, 0.09) for j in range(8)]
    ray_len = [(0.86 if j % 2 == 0 else 0.55) * rng.uniform(0.82, 1.0) for j in range(8)]
    ray_w = [(0.060 if j % 2 == 0 else 0.040) * rng.uniform(0.85, 1.1) for j in range(8)]
    sparks = [dict(ang=rng.uniform(0, 2 * math.pi), v=rng.uniform(0.45, 0.85), w=rng.uniform(0.9, 1.5),
                   life=rng.uniform(0.65, 1.0)) for _ in range(12)]
    X, Y = grid(2)
    r = np.hypot(X, Y)
    th = np.arctan2(Y, X)
    out = []
    LIFE = 10
    for i in range(FRAMES):
        if i >= LIFE:
            out.append(np.zeros((CELL, CELL)))
            continue
        t = i / LIFE
        k = 1.0 - t
        a = np.zeros_like(X)
        for j in range(8):
            dth = np.angle(np.exp(1j * (th - ray_ang[j])))
            along = r * np.cos(dth)
            perp = np.abs(r * np.sin(dth))
            L = ray_len[j] * (k ** 1.7) * (1.0 if i > 0 else 0.9)
            if L < 0.02:
                continue
            u = np.clip(along / L, 0.0, 1.0)
            wb = ray_w[j] * (0.35 + 0.65 * k ** 0.8)
            half = wb * (1.0 - u) ** 1.25
            spike = sstep(half + 1.2 * PX, half - 0.6 * PX, perp) * (along > 0) * (along < L)
            soft = np.exp(-perp / (half * 1.6 + 1.5 * PX)) * (1.0 - u) ** 1.5 * (along > 0) * 0.5
            a = np.maximum(a, np.maximum(spike, soft))
        rc = 0.20 * (k ** 0.9) * (1.15 if i == 0 else 1.0)
        core = sstep(rc, rc * 0.55, r)
        halo = np.exp(-(r / (rc * 2.2 + 1e-3)) ** 2) * 0.55 * k
        a = np.clip(np.maximum(a, core) + halo * (1 - a), 0, 1) * (1.0 if i < 6 else (1.0 - (i - 5) / 5.0))
        a = down(a, 2)
        # 飛ぶ火花（短い尾の点）
        sc = np.zeros((CELL * ss, CELL * ss))
        for sp in sparks:
            tl = t / sp["life"]
            if tl >= 1.0 or i == 0:
                continue
            d = np.array([math.cos(sp["ang"]), math.sin(sp["ang"])])
            rad = 0.12 + sp["v"] * ease_out(tl, 1.8)
            p = d * rad + np.array([0.0, -0.12 * tl * tl])
            q = p - d * (0.10 * sp["v"] * (1.0 - tl) + 0.015)
            stroke(sc, np.array([q, p]), np.array([sp["w"] * 0.4, sp["w"]]) * (1 - 0.4 * tl),
                   np.array([0.2, 1.0]) * (1.0 - tl) ** 0.7, ss)
        a = np.maximum(a, down(sc, ss))
        out.append(np.clip(a, 0, 1))
    return out


# --- 一覧 ------------------------------------------------------------------------------------------

SHEETS = [
    # name, 生成関数, mode, suggestedFPS, 確認用の色, 地面に寝かせるか
    ("smoke_puff", fx_smoke_puff, "once", 20, "gold", False),
    ("fire_burst", fx_fire_burst, "once", 24, "orange", False),
    ("flame_loop", fx_flame_loop, "loop", 20, "orange", False),
    ("electric_arc", fx_electric_arc, "loop", 20, "cyan", False),
    ("energy_burst", fx_energy_burst, "once", 24, "gold", False),
    ("shock_ring", fx_shock_ring, "once", 24, "gold", True),
    ("slash_fade", fx_slash_fade, "once", 24, "gold", False),
    ("ice_shatter", fx_ice_shatter, "once", 20, "cyan", False),
    ("spark_twinkle", fx_spark_twinkle, "loop", 16, "gold", False),
    ("dark_wisp", fx_dark_wisp, "once", 16, "gold", False),
    ("ground_crack", fx_ground_crack, "once", 20, "gold", True),
    ("hit_flash", fx_hit_flash, "once", 24, "gold", False),
]

TINTS = {"orange": (255, 138, 36), "cyan": (70, 225, 255), "gold": (255, 204, 70)}
BG_GRASS = (0x5A, 0x6A, 0x50)
BG_DARK = (0x1B, 0x1F, 0x24)


def cell_window():
    """外周 2 px は 0、そこから数 px でなめらかに 1 へ（はみ出しの保険）。"""
    i = np.arange(CELL) + 0.5
    d = np.minimum(i, CELL - i)  # 画素の中心からコマの端までの距離
    w1 = np.where(np.arange(CELL) < BORDER, 0.0, sstep(BORDER, BORDER + 5.0, d))
    w1 = np.where(np.arange(CELL) >= CELL - BORDER, 0.0, w1)
    return np.outer(w1, w1)


def assemble(frames):
    assert len(frames) == FRAMES
    win = cell_window()
    alpha = np.zeros((SHEET, SHEET), np.uint8)
    for k, fr in enumerate(frames):
        assert fr.shape == (CELL, CELL), fr.shape
        a = np.clip(fr, 0.0, 1.0) * win
        q = np.round(a * 255.0)
        q[q < 2] = 0  # ほぼ透明なちりは捨てる（容量と見た目のため）
        r, c = divmod(k, GRID)
        alpha[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = q.astype(np.uint8)
    rgba = np.empty((SHEET, SHEET, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = alpha
    return rgba


def check_sheet(name, rgba):
    a = rgba[..., 3]
    for k in range(FRAMES):
        r, c = divmod(k, GRID)
        cell = a[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL]
        edge = np.concatenate([cell[:BORDER].ravel(), cell[-BORDER:].ravel(), cell[:, :BORDER].ravel(),
                               cell[:, -BORDER:].ravel()])
        if edge.max() != 0:
            raise SystemExit(f"{name}: frame {k} の外周 {BORDER} px が透明でない")
    if (rgba[..., :3] != 255).any():
        raise SystemExit(f"{name}: RGB が白でない")


def save_png(path, rgba):
    Image.fromarray(rgba, "RGBA").save(path, format="PNG", optimize=True)


def write_preview(path, name, rgba, tint, ground):
    a = rgba[..., 3].astype(np.float64)[..., None] / 255.0
    col = np.array(TINTS[tint], np.float64)
    panels = []
    for bg in (BG_GRASS, BG_DARK):
        b = np.array(bg, np.float64)
        img = b * (1 - a) + col * a
        panels.append(img)
    if ground:
        # 斜め 45° から見た地面（縦を cos45° に潰す）
        b = np.array(BG_GRASS, np.float64)
        sq = np.zeros((SHEET, SHEET, 3)) + b
        hh = int(round(CELL * math.cos(math.pi / 4)))
        for k in range(FRAMES):
            r, c = divmod(k, GRID)
            cell = rgba[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL, 3]
            small = cv2.resize(cell, (CELL, hh), interpolation=cv2.INTER_AREA).astype(np.float64)[..., None] / 255
            y0 = r * CELL + (CELL - hh) // 2
            sq[y0:y0 + hh, c * CELL:(c + 1) * CELL] = b * (1 - small) + col * small
        panels.append(sq)
    gap = 8
    head = 18
    W = SHEET * len(panels) + gap * (len(panels) - 1)
    out = np.zeros((SHEET + head, W, 3)) + 40
    for p, img in enumerate(panels):
        x0 = p * (SHEET + gap)
        out[head:, x0:x0 + SHEET] = img
        for g in range(1, GRID):
            out[head:, x0 + g * CELL] = out[head:, x0 + g * CELL] * 0.6
            out[head + g * CELL, x0:x0 + SHEET] = out[head + g * CELL, x0:x0 + SHEET] * 0.6
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")
    dr = ImageDraw.Draw(im)
    label = f"{name}  (grass / dark" + (" / ground 45deg)" if ground else ")")
    dr.text((4, 3), label, fill=(230, 230, 230))
    for p in range(len(panels)):
        for k in range(FRAMES):
            r, c = divmod(k, GRID)
            dr.text((p * (SHEET + gap) + c * CELL + 3, head + r * CELL + 2), str(k), fill=(200, 200, 200))
    im.save(path, format="PNG", optimize=True)


def write_manifest(out_dir):
    items = []
    for name, _, mode, fps, _, _ in sorted(SHEETS, key=lambda s: s[0]):
        path = os.path.join(out_dir, name + ".png")
        if not os.path.exists(path):
            continue
        data = open(path, "rb").read()
        items.append({"name": name, "file": name + ".png", "rows": GRID, "columns": GRID, "frames": FRAMES,
                      "frameSize": CELL, "mode": mode, "suggestedFPS": fps, "bytes": len(data),
                      "sha256": hashlib.sha256(data).hexdigest()})
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(items, f, indent=2, ensure_ascii=False)
        f.write("\n")
    return items


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", action="append", help="このシートだけ作る（複数指定可）")
    ap.add_argument("--out", default=DEFAULT_OUT, help="PNG と manifest.json の出力先")
    ap.add_argument("--preview", help="確認用の合成画像の出力先（リポジトリの外を指定する）")
    args = ap.parse_args(argv)
    names = [s[0] for s in SHEETS]
    todo = SHEETS
    if args.only:
        bad = [n for n in args.only if n not in names]
        if bad:
            ap.error("unknown sheet: " + ", ".join(bad) + "（" + ", ".join(names) + "）")
        todo = [s for s in SHEETS if s[0] in args.only]
    os.makedirs(args.out, exist_ok=True)
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
    for name, fn, mode, fps, tint, ground in todo:
        rgba = assemble(fn())
        check_sheet(name, rgba)
        path = os.path.join(args.out, name + ".png")
        save_png(path, rgba)
        size = os.path.getsize(path)
        print(f"{name:14s} {size:7d} bytes  {mode}")
        if size > 350 * 1024:
            print(f"  warning: {name} is larger than 350 KB", file=sys.stderr)
        if args.preview:
            write_preview(os.path.join(args.preview, name + "_preview.png"), name, rgba, tint, ground)
    write_manifest(args.out)


if __name__ == "__main__":
    main()
