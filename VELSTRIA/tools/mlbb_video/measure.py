#!/usr/bin/env python3
"""MLBB の画面収録からスキルの幾何と時間を測る道具（docs/kits/Tigreal.md「動画で測った値」の手順を道具にしたもの）。

前提:
- コマは ffmpeg で 1 枚ずつの PNG に切り出しておく（例: ffmpeg -i in.mp4 -vf fps=30 frames/%04d.png）。コマ n の時刻 = (n - 1) / fps。
- MLBB のカメラは自分のヒーローに固定（ヒーローは画面の同じ位置）。地面への写像は 1 本の式で表せる:
      u = u0 + x / (1 + q z),  v = v0 - c z / (1 + q z)
  x, z = ヒーローの足元から見た地面の座標（右 / 奥。「ヒーロー px」= ヒーローの位置での横 1 px）、(u0, v0) = 足元の画素、
  c = 奥行きの縮み、q = 遠近の強さ（1/px）。縮尺 s（ヒーロー px / MLBB の距離 1）は歩く速さで決める。
- 画像・コマ・動画はリポジトリに入れない（公開リポジトリ。著作物）。出力は既定で一時フォルダ（--out）。

使い方（Tigreal の例。数値は docs/kits/Tigreal.md）:
  python measure.py ring   --frames F --ref 35 --at 39,40,41 --guess 557,311,176,125 --exclude 480,130,640,330 --name ult
  python measure.py ring   --frames F --ref 262 --at 276,280,284 --guess 552,305,352,208 --exclude ... --name s2
  python measure.py camera ult s2                       # 2 つの同心の照準円から u0, v0, c, q と半径（px）→ cam.json
  python measure.py speed  --frames F --from 100 --to 126 --floor 91,62,0,230 --speed 2.6   # 床の特徴点の歩き → 縮尺 s
  python measure.py move   --frames F 300 335 --patch 980,470,50 --guess -217,-243          # 止まったコマどうしの地面のずれ
  python measure.py shape  --frames F --ref 127 --at 132,136,140 --roi 480,60,900,330 --name s1   # 照準の輪郭 → 地面（単位）
  python measure.py trapezoid s1 --left 0.4,2.6:1.9,5.2 --right 1.5,0:5.3,3.1 --far 3.2,5.1:5.3,3.1   # 左右・奥の辺の当てはめ
  python measure.py bands  --frames F --ref 199 --from 199 --to 236 --axis 48.5 --bands 30:150,150:260,260:420   # 爆発の時刻
  python measure.py point  410,300 655,233              # 画素 → 地面（単位）
  python measure.py rect   --frames F 100               # 真上から見た図（地面の円が円に見えれば写像は正しい）
  python measure.py montage --frames F --box 380,40,980,380 --scale 0.5 196 198 200 204   # コマの一覧（目視用）
  python measure.py diff   --frames F 40 35 --gain 4    # 差分画像（照準の縁を見る）

依存: numpy, opencv-python-headless, scipy（pip install numpy opencv-python-headless scipy）。
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import tempfile
from dataclasses import dataclass, asdict

import cv2
import numpy as np
from scipy.ndimage import map_coordinates
from scipy.optimize import least_squares

DEFAULT_OUT = os.path.join(tempfile.gettempdir(), "mlbb_video_out")


# ---------------------------------------------------------------- コマ

class Frames:
    def __init__(self, folder: str, pattern: str = "%04d.png"):
        self.folder = folder
        self.pattern = pattern
        self._cache: dict[int, np.ndarray] = {}

    def bgr(self, n: int) -> np.ndarray:
        if n not in self._cache:
            im = cv2.imread(os.path.join(self.folder, self.pattern % n))
            if im is None:
                raise SystemExit(f"コマ {n} が読めない: {os.path.join(self.folder, self.pattern % n)}")
            if len(self._cache) > 64:
                self._cache.clear()
            self._cache[n] = im
        return self._cache[n]

    def gray(self, n: int) -> np.ndarray:
        return cv2.cvtColor(self.bgr(n), cv2.COLOR_BGR2GRAY)

    def f32(self, n: int) -> np.ndarray:
        return self.bgr(n).astype(np.float32)


def parse_boxes(items: list[str] | None) -> list[tuple[int, int, int, int]]:
    return [tuple(int(v) for v in s.split(",")) for s in (items or [])]


def in_boxes(x: float, y: float, boxes) -> bool:
    return any(x0 <= x <= x1 and y0 <= y <= y1 for x0, y0, x1, y1 in boxes)


def ui_mask(shape, boxes) -> np.ndarray:
    """UI（ミニマップ・ボタン・ジョイスティック・自分の体）を除く 0/255 の画素マスク。"""
    m = np.full(shape[:2], 255, np.uint8)
    for x0, y0, x1, y1 in boxes:
        m[max(0, y0):y1, max(0, x0):x1] = 0
    return m


# 1108×512 の iPhone 横画面の MLBB の既定の UI（端末で違えば --ui で置き換える）
DEFAULT_UI = [(0, 0, 215, 175), (460, 120, 660, 345), (700, 230, 1108, 512), (450, 380, 720, 512),
              (100, 300, 320, 512), (800, 0, 1108, 120), (450, 0, 650, 60), (0, 220, 330, 300)]


# ---------------------------------------------------------------- カメラ（地面への写像）

@dataclass
class GroundCam:
    u0: float
    v0: float
    c: float
    q: float
    s: float | None = None          # ヒーロー px / MLBB の距離 1（speed で決める）
    radii_px: dict | None = None    # camera で当てはめた円の半径（px）

    def unproject(self, u, v):
        dv = self.v0 - np.asarray(v, float)
        z = dv / (self.c - self.q * dv)
        x = (np.asarray(u, float) - self.u0) * (1 + self.q * z)
        return x, z

    def project(self, x, z):
        w = 1 + self.q * np.asarray(z, float)
        return self.u0 + np.asarray(x, float) / w, self.v0 - self.c * np.asarray(z, float) / w

    def units(self, px):
        if not self.s:
            raise SystemExit("縮尺 s が未定（先に speed を回す）")
        return np.asarray(px, float) / self.s

    def save(self, path: str):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(asdict(self), f, indent=2, ensure_ascii=False)

    @staticmethod
    def load(path: str) -> "GroundCam":
        with open(path, encoding="utf-8") as f:
            return GroundCam(**json.load(f))


# ---------------------------------------------------------------- 照準の円

def cyan_score(fr: Frames, frames: list[int], ref: int) -> np.ndarray:
    """照準（水色）の差分の強さ。何コマかの中央値でアニメーションを消す。"""
    acc = []
    R = fr.f32(ref)
    for n in frames:
        d = fr.f32(n) - R
        acc.append((d[..., 0] + d[..., 1]) / 2 - np.maximum(d[..., 2], 0) * 0.5)
    med = np.ascontiguousarray(np.median(np.array(acc), axis=0), dtype=np.float32)
    return cv2.GaussianBlur(med, (3, 3), 0)


def _ellipse_r(ex, ey, ell):
    (cx, cy), (w, h), ang = ell
    t = math.radians(ang)
    rx = ex * math.cos(t) + ey * math.sin(t)
    ry = -ex * math.sin(t) + ey * math.cos(t)
    return 1 / math.sqrt((rx / (w / 2)) ** 2 + (ry / (h / 2)) ** 2)


def _ray_points(sc, ell, win, step, minv, boxes):
    H, W = sc.shape
    (cx, cy) = ell[0]
    pts = []
    for deg in np.arange(0, 360, step):
        t = math.radians(deg)
        ex, ey = math.cos(t), math.sin(t)
        r0 = _ellipse_r(ex, ey, ell)
        rs = np.arange(max(5, r0 - win), r0 + win, 0.25)
        xs, ys = cx + rs * ex, cy + rs * ey
        ok = (xs >= 1) & (xs < W - 2) & (ys >= 1) & (ys < H - 2)
        if ok.sum() < len(rs) * 0.8:
            continue
        vals = map_coordinates(sc, [ys, xs], order=1, cval=-1e9)
        vals[~ok] = -1e9
        i = int(np.argmax(vals))
        if vals[i] < minv or in_boxes(xs[i], ys[i], boxes):
            continue
        pts.append((xs[i], ys[i], vals[i], deg))
    return np.array(pts)


def extract_ring(fr: Frames, frames, ref, guess, boxes, minv=12.0):
    """照準の円（地面の円が楕円に写ったもの）の縁の画素を、中心からの放射で拾う（2 段: 粗く → 楕円 → 細かく）。"""
    sc = cyan_score(fr, frames, ref)
    u, v, ax, ay = guess
    p = _ray_points(sc, ((u, v), (2 * ax, 2 * ay), 0), 20, 1.0, minv, boxes)
    e = cv2.fitEllipse(p[:, :2].astype(np.float32))
    p2 = _ray_points(sc, e, 5, 0.5, minv, boxes)
    e2 = cv2.fitEllipse(p2[:, :2].astype(np.float32))
    d = []
    for x, y, *_ in p2:
        ex, ey = x - e2[0][0], y - e2[0][1]
        rr = math.hypot(ex, ey)
        d.append(rr - _ellipse_r(ex / rr, ey / rr, e2))
    d = np.array(d)
    return p2[np.abs(d - np.median(d)) < 2.5], e2


def fit_camera(rings: list[np.ndarray], fix_q: float | None = None):
    """同心の円（どれも中心はヒーローの足元）から u0, v0, c, q と各半径（ヒーロー px）を当てはめる。1 つの円では q が決まらない。"""
    def resid(p):
        cam = GroundCam(*p[:4])
        out = []
        for k, pts in enumerate(rings):
            x, z = cam.unproject(pts[:, 0], pts[:, 1])
            out.append((np.hypot(x, z) - p[4 + k]) / (1 + p[3] * z))
        return np.concatenate(out)
    p0 = [554, 300, 0.7, 0.0005] + [150.0 * (k + 1) for k in range(len(rings))]
    lo = [300, 100, 0.3, 0.0] + [10] * len(rings)
    hi = [800, 450, 1.2, 0.004] + [2000] * len(rings)
    if fix_q is not None:
        p0[3], lo[3], hi[3] = fix_q, fix_q - 1e-12, fix_q + 1e-12
    r = least_squares(resid, p0, loss="soft_l1", f_scale=1.0, bounds=(lo, hi))
    return r.x, float(np.sqrt(np.mean(r.fun ** 2)))


# ---------------------------------------------------------------- 地面の特徴点の動き

def track_pair(g0, g1, mask, cam: GroundCam, max_fb=0.3, min_move=0.4):
    """2 コマの間の特徴点（LK）を地面へ戻した変位（ヒーロー px）。画面に固定の UI（動かない点）は捨てる。"""
    p0 = cv2.goodFeaturesToTrack(g0, 800, 0.003, 5, mask=mask)
    if p0 is None:
        return np.zeros((0, 2)), np.zeros((0, 2))
    p1, st, _ = cv2.calcOpticalFlowPyrLK(g0, g1, p0, None, winSize=(21, 21), maxLevel=3)
    pb, st2, _ = cv2.calcOpticalFlowPyrLK(g1, g0, p1, None, winSize=(21, 21), maxLevel=3)
    fb = np.linalg.norm((pb - p0).reshape(-1, 2), axis=1)
    ok = (st.ravel() == 1) & (st2.ravel() == 1) & (fb < max_fb)
    A, B = p0.reshape(-1, 2)[ok], p1.reshape(-1, 2)[ok]
    mv = np.hypot(*(B - A).T) > min_move
    A, B = A[mv], B[mv]
    xa, za = cam.unproject(A[:, 0], A[:, 1])
    xb, zb = cam.unproject(B[:, 0], B[:, 1])
    return np.c_[xb - xa, zb - za], np.c_[xa, za]


def robust_mean(D, tol=0.6):
    if len(D) == 0:
        return None, 0
    med = np.median(D, axis=0)
    inl = np.hypot(*(D - med).T) < tol
    if inl.sum() == 0:
        return med, 0
    return D[inl].mean(axis=0), int(inl.sum())


def ground_grid(cam: GroundCam, shape):
    vs, us = np.mgrid[0:shape[0], 0:shape[1]]
    x, z = cam.unproject(us.ravel().astype(float), vs.ravel().astype(float))
    return x.reshape(shape[:2]), z.reshape(shape[:2])


# ---------------------------------------------------------------- 真上から見た図

def rectify(fr: Frames, n: int, cam: GroundCam, xr=(-700, 700), zr=(-250, 650), highpass=False):
    xs = np.arange(xr[0], xr[1], 1.0)
    zs = np.arange(zr[1], zr[0], -1.0)
    GX, GZ = np.meshgrid(xs, zs)
    U, V = cam.project(GX.ravel(), GZ.ravel())
    im = fr.gray(n).astype(np.float32)
    if highpass:
        im = im - cv2.GaussianBlur(im, (0, 0), 6)
    r = map_coordinates(im, [V, U], order=1, cval=0).reshape(GX.shape)
    H, W = im.shape
    ok = ((U >= 0) & (U < W - 1) & (V >= 0) & (V < H - 1)).reshape(GX.shape)
    return r, ok, xr, zr


# ---------------------------------------------------------------- 出力

def out_dir(args) -> str:
    d = args.out or DEFAULT_OUT
    os.makedirs(d, exist_ok=True)
    return d


def topdown_png(path, polys_or_pts, s, extent=(-4, 8, -1, 10), k=80, circles=(2, 4, 6, 8)):
    """地面（MLBB の単位）の点・輪郭を真上から描く（ヒーロー = 赤い点、灰色の格子 = 1 単位）。"""
    x0, x1, z0, z1 = extent
    W, H = int((x1 - x0) * k), int((z1 - z0) * k)
    img = np.zeros((H, W, 3), np.uint8)
    to = lambda x, z: (int((x - x0) * k), int((z1 - z) * k))
    for gx in range(int(x0), int(x1) + 1):
        cv2.line(img, to(gx, z0), to(gx, z1), (50, 50, 50), 1)
    for gz in range(int(z0), int(z1) + 1):
        cv2.line(img, to(x0, gz), to(x1, gz), (50, 50, 50), 1)
    for r in circles:
        cv2.circle(img, to(0, 0), int(r * k), (0, 120, 255), 1)
    cols = [(255, 255, 0), (0, 255, 0), (255, 0, 255), (0, 200, 255)]
    for i, P in enumerate(polys_or_pts):
        P = np.asarray(P)
        pts = np.array([to(x, z) for x, z in P], np.int32)
        cv2.polylines(img, [pts.reshape(-1, 1, 2)], True, cols[i % len(cols)], 1)
    cv2.circle(img, to(0, 0), 5, (0, 0, 255), -1)
    cv2.imwrite(path, img)


def load_cam(args) -> GroundCam:
    path = args.cam or os.path.join(out_dir(args), "cam.json")
    return GroundCam.load(path)


# ---------------------------------------------------------------- サブコマンド

def cmd_ring(args):
    fr = Frames(args.frames, args.pattern)
    frames = [int(a) for a in args.at.split(",")]
    guess = [float(a) for a in args.guess.split(",")]
    pts, e = extract_ring(fr, frames, args.ref, guess, parse_boxes(args.exclude), args.min)
    path = os.path.join(out_dir(args), f"ring_{args.name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"frames": frames, "ref": args.ref, "points": pts[:, :2].tolist(), "ellipse": e}, f)
    print(f"{args.name}: 縁の点 {len(pts)}、楕円 中心=({e[0][0]:.1f},{e[0][1]:.1f}) 軸=({e[1][0]/2:.1f},{e[1][1]/2:.1f}) 角={e[2]:.1f} → {path}")
    vis = fr.bgr(frames[0]).copy()
    for x, y in pts[:, :2]:
        cv2.circle(vis, (int(round(x)), int(round(y))), 1, (0, 0, 255), -1)
    cv2.imwrite(os.path.join(out_dir(args), f"ring_{args.name}.png"), vis)


def cmd_camera(args):
    rings = []
    for name in args.rings:
        with open(os.path.join(out_dir(args), f"ring_{name}.json"), encoding="utf-8") as f:
            rings.append(np.array(json.load(f)["points"]))
    p, rms = fit_camera(rings)
    cam = GroundCam(*p[:4], radii_px={n: float(r) for n, r in zip(args.rings, p[4:])})
    old = None
    path = args.cam or os.path.join(out_dir(args), "cam.json")
    if os.path.exists(path):
        try:
            old = GroundCam.load(path)
        except Exception:
            old = None
    if old and old.s:
        cam.s = old.s
    cam.save(path)
    print(f"u0={cam.u0:.2f} v0={cam.v0:.2f} c={cam.c:.4f} q={cam.q:.6f}/px  残差 rms={rms:.2f}px → {path}")
    for n, r in cam.radii_px.items():
        print(f"  円 {n}: 半径 {r:.1f} ヒーロー px" + (f" = {r / cam.s:.3f} 単位" if cam.s else ""))
    if len(rings) > 1:
        print("  q を固定したときの残差（最小の近くで鋭いほど q がよく決まっている）:")
        for dq in (-3e-4, -1.5e-4, 0, 1.5e-4, 3e-4):
            _, r2 = fit_camera(rings, fix_q=max(0.0, cam.q + dq))
            print(f"    q={max(0.0, cam.q + dq):.5f}: rms={r2:.2f}px")


def cmd_speed(args):
    """歩きの縮尺: 床（地面の高さ）の特徴点だけで 1 コマの変位を測る。岩・草・建物の上の点は地面より速く動いて見える
    （高さ h の点の見かけの変位 = 地面 × カメラの高さ / (カメラの高さ − h)）ので、床の範囲（--floor）を必ず与える。"""
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    shape = fr.bgr(args.start).shape
    GX, GZ = ground_grid(cam, shape)
    ui = ui_mask(shape, DEFAULT_UI if not args.ui else parse_boxes(args.ui))
    fx, fz, r0, r1 = [float(a) for a in args.floor.split(",")] if args.floor else (0, 0, 0, 1e9)
    center = np.array([fx, fz])
    rows = []
    path_len = 0.0
    for n in range(args.start, args.end):
        d = np.hypot(GX - center[0], GZ - center[1])
        m = (((d > r0) & (d < r1)).astype(np.uint8) * 255) & ui
        D, _ = track_pair(fr.gray(n), fr.gray(n + 1), m, cam)
        g, k = robust_mean(D)
        Dall, _ = track_pair(fr.gray(n), fr.gray(n + 1), ui, cam)
        ga, _ = robust_mean(Dall)
        if g is None or k < 5:
            print(f"{n}->{n + 1}: 床の点が足りない ({k})")
            continue
        center = center + g     # 床の範囲は世界に固定（カメラと一緒に動かない）
        mag = float(np.hypot(*g))
        path_len += mag
        rows.append(mag)
        print(f"{n}->{n + 1}: 床 |d|={mag:.3f} 向き={math.degrees(math.atan2(g[1], g[0])):6.1f}° 点={k:3d}   全部の点 |d|={np.hypot(*ga) if ga is not None else float('nan'):.3f}")
    rows = np.array(rows)
    full = rows[rows > 0.8 * np.median(rows)] if len(rows) else rows
    if len(full) == 0:
        return
    v = float(np.mean(full))
    print(f"歩き: 1 コマ {v:.3f} ± {np.std(full) / math.sqrt(len(full)):.3f} ヒーロー px（{len(full)} コマ）、道のり {path_len:.1f} px")
    if args.speed:
        s = v * args.fps / args.speed
        cam.s = s
        cam.save(args.cam or os.path.join(out_dir(args), "cam.json"))
        print(f"縮尺 s = {v:.3f} × {args.fps} / {args.speed} = {s:.2f} ヒーロー px / 単位（cam.json に保存）")


def _patch_match(A, B, cx, cy, hf, ex, ey, sr):
    tpl = A[cy - hf:cy + hf, cx - hf:cx + hf]
    S = B[ey - hf - sr:ey + hf + sr, ex - hf - sr:ex + hf + sr]
    res = cv2.matchTemplate(S, tpl, cv2.TM_CCOEFF_NORMED)
    _, mv, _, ml = cv2.minMaxLoc(res)

    def sub(arr, i):
        if 0 < i < len(arr) - 1:
            d = arr[i - 1] - 2 * arr[i] + arr[i + 1]
            return i + (0.5 * (arr[i - 1] - arr[i + 1]) / d if d != 0 else 0)
        return i
    px, py = sub(res[ml[1]], ml[0]), sub(res[:, ml[0]], ml[1])
    return ex - sr + px, ey - sr + py, mv


def cmd_move(args):
    """止まったコマ a → b の地面のずれ（ヒーロー px と単位）。床の小片（--patch c,r,半幅。真上から見た図の画素）を b から a へ探す。"""
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    ra, oka, xr, zr = rectify(fr, args.a, cam, highpass=True)
    rb, okb, _, _ = rectify(fr, args.b, cam, highpass=True)
    gx, gz = [float(v) for v in args.guess.split(",")] if args.guess else (0.0, 0.0)
    results = []
    for p in args.patch:
        c, r, hf = [int(v) for v in p.split(",")]
        # patch は a の真上から見た図の画素（列 = x + 700、行 = 650 − z）。b では (c + gx, r − gz) のあたりに居る
        tx, ty, sc = _patch_match(ra, rb, c, r, hf, int(round(c + gx)), int(round(r - gz)), args.search)
        dx, dz = tx - c, -(ty - r)
        results.append((dx, dz, sc))
        print(f"小片 ({c},{r})±{hf}: 一致 {sc:.3f}  地面のずれ dx={dx:.2f} dz={dz:.2f} |d|={math.hypot(dx, dz):.2f} px"
              + (f" = {math.hypot(dx, dz) / cam.s:.3f} 単位" if cam.s else ""))
    good = [r for r in results if r[2] > 0.3]
    if good:
        d = np.median(np.array(good)[:, :2], axis=0)
        print(f"一致 0.3 超の中央値: |d|={math.hypot(*d):.2f} px" + (f" = {math.hypot(*d) / cam.s:.3f} 単位" if cam.s else ""))


def cmd_shape(args):
    """照準の塗り（差分）の輪郭を地面（単位）へ戻し、JSON と真上から見た図を書く。ほかの UI（体力バー）に隠れた所は輪郭が欠ける。"""
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    frames = [int(a) for a in args.at.split(",")]
    sc = cyan_score(fr, frames, args.ref)
    x0, y0, x1, y1 = [int(v) for v in args.roi.split(",")]
    m = np.zeros(sc.shape, np.uint8)
    m[y0:y1, x0:x1] = (sc[y0:y1, x0:x1] > args.thr).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n_, lab, st, _ = cv2.connectedComponentsWithStats(m)
    if n_ < 2:
        raise SystemExit("照準が見つからない（--thr を下げる・--ref を確かめる）")
    m = (lab == 1 + np.argmax(st[1:, cv2.CC_STAT_AREA])).astype(np.uint8)
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cnts, key=cv2.contourArea).reshape(-1, 2).astype(float)
    x, z = cam.unproject(c[:, 0], c[:, 1])
    X, Z = cam.units(x), cam.units(z)
    d = out_dir(args)
    with open(os.path.join(d, f"shape_{args.name}.json"), "w", encoding="utf-8") as f:
        json.dump({"pixels": c.tolist(), "ground": np.c_[X, Z].tolist()}, f)
    topdown_png(os.path.join(d, f"shape_{args.name}_top.png"), [np.c_[X, Z]], cam.s)
    vis = fr.bgr(frames[0]).copy()
    cv2.drawContours(vis, [c.astype(np.int32).reshape(-1, 1, 2)], -1, (0, 0, 255), 1)
    cv2.imwrite(os.path.join(d, f"shape_{args.name}.png"), vis)
    r = np.hypot(X, Z)
    print(f"{args.name}: 輪郭 {len(c)} 点、術者からの距離 最小 {r.min():.2f} / 最大 {r.max():.2f} 単位 → {d}")


def _seg_pts(P, a, b, tol=0.2, trim=0.3):
    a, b = np.array(a), np.array(b)
    dv = b - a
    L = np.linalg.norm(dv)
    t = dv / L
    n = np.array([-t[1], t[0]])
    rel = P - a
    s, e = rel @ t, rel @ n
    return P[(np.abs(e) < tol) & (s > trim) & (s < L - trim)]


def _fit_line(Q):
    c = Q.mean(axis=0)
    _, _, vt = np.linalg.svd(Q - c)
    return c, vt[0], float(np.sqrt(np.mean(((Q - c) @ vt[1]) ** 2)))


def cmd_trapezoid(args):
    """輪郭（shape の JSON）の左右・奥の辺を直線で当てはめる。辺はおおよその端点「x,z:x,z」（単位）で選ぶ。
    左右の辺の開き（片側の角度）、術者の位置での半幅、奥の辺の距離（直線）と、術者を中心とする弧としての半径の残差を出す。"""
    with open(os.path.join(out_dir(args), f"shape_{args.name}.json"), encoding="utf-8") as f:
        P = np.array(json.load(f)["ground"])
    def seg(s):
        a, b = s.split(":")
        return [float(v) for v in a.split(",")], [float(v) for v in b.split(",")]
    fits = {}
    for key in ("left", "right", "far"):
        s = getattr(args, key)
        if not s:
            continue
        Q = _seg_pts(P, *seg(s))
        if len(Q) < 5:
            print(f"{key}: 点が足りない（端点を見直す）")
            continue
        c, t, rms = _fit_line(Q)
        if key != "far" and t @ np.array([1.0, 1.0]) < 0:
            t = -t
        fits[key] = (c, t, Q)
        r = np.hypot(Q[:, 0], Q[:, 1])
        print(f"{key}: 点 {len(Q)}、直線の残差 {rms:.3f}、術者を中心とする弧なら半径 {r.mean():.3f} ± {r.std():.3f}（単位）")
    if "left" in fits and "right" in fits:
        cl, tl, _ = fits["left"]
        cr, tr, _ = fits["right"]
        axis = (tl + tr) / np.linalg.norm(tl + tr)
        nrm = np.array([axis[1], -axis[0]])
        half = math.degrees(math.acos(max(-1.0, min(1.0, float(tl @ tr))))) / 2

        def at(c, t, s):
            u = (s - c @ axis) / (t @ axis)
            return c + u * t
        w0 = float((at(cr, tr, 0) - at(cl, tl, 0)) @ nrm) / 2
        print(f"軸 {math.degrees(math.atan2(axis[1], axis[0])):.1f}°、左右の辺の開き 片側 {half:.2f}°、術者の位置での半幅 {w0:.3f} 単位"
              + ("（扇なら 0）" if abs(w0) > 0.1 else ""))
        if "far" in fits:
            cf, tf, Qf = fits["far"]
            nf = np.array([tf[1], -tf[0]])
            nf *= np.sign(nf @ axis)
            L = float(cf @ nf)
            print(f"奥の辺: 術者からの距離 {L:.3f} 単位（直線）、奥の半幅 {w0 + L * math.tan(math.radians(half)):.3f} 単位")


def warm(im):
    b, g, r = im[..., 0], im[..., 1], im[..., 2]
    return np.clip((r + g) / 2 - b, 0, 255) + np.clip(im.mean(axis=2) - 120, 0, 255)


def cmd_bands(args):
    """爆発（暖色の光）の時刻: 照準の軸に沿った帯ごとに、前のコマから増えた暖色の量を出す。増えた量が跳ねたコマが爆発の始まり。
    --quantile のコマでは、増えた暖色の軸方向の分布（5〜95%）を出す（炎は上へ伸びるので奥側は膨らむ。手前の端が地面の位置に近い）。"""
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    shape = fr.bgr(args.start).shape
    GX, GZ = ground_grid(cam, shape)
    a = math.radians(args.axis)
    al = GX * math.cos(a) + GZ * math.sin(a)
    ac = GX * math.sin(a) - GZ * math.cos(a)
    valid = ui_mask(shape, DEFAULT_UI if not args.ui else parse_boxes(args.ui)) > 0
    bands = [tuple(float(v) for v in b.split(":")) for b in args.bands.split(",")]
    width = args.width
    R = warm(fr.f32(args.ref))
    prev = warm(fr.f32(args.start - 1))
    for n in range(args.start, args.end):
        cur = warm(fr.f32(n))
        inc = np.clip(cur - prev, 0, None) * valid
        lvl = np.clip(cur - R, 0, None) * valid
        cols = []
        for lo, hi in bands:
            m = (al >= lo) & (al < hi) & (np.abs(ac) < width)
            cols.append(f"[{lo:.0f}:{hi:.0f}] 量={lvl[m].sum() / 1e4:7.1f} 増={inc[m].sum() / 1e4:6.1f}")
        print(f"{n} t={(n - 1) / args.fps:.3f}  " + "  ".join(cols))
        prev = cur
    for n in [int(v) for v in (args.quantile.split(",") if args.quantile else [])]:
        inc = np.clip(warm(fr.f32(n)) - warm(fr.f32(n - 1)), 0, None) * valid
        inc[inc < 30] = 0
        m = (np.abs(ac) < width) & (inc > 0)
        w, A = inc[m], al[m]
        o = np.argsort(A)
        cw = np.cumsum(w[o]) / w.sum()
        q = lambda p: A[o][min(len(A) - 1, np.searchsorted(cw, p))]
        unit = (lambda v: f"{v:.0f}px={v / cam.s:.2f}u") if cam.s else (lambda v: f"{v:.0f}px")
        print(f"コマ {n}: 軸方向 5%={unit(q(.05))} 25%={unit(q(.25))} 50%={unit(q(.5))} 75%={unit(q(.75))} 95%={unit(q(.95))}")


def cmd_point(args):
    cam = load_cam(args)
    for p in args.points:
        u, v = [float(a) for a in p.split(",")]
        x, z = cam.unproject(u, v)
        s = f" = ({x / cam.s:.3f}, {z / cam.s:.3f}) 単位、距離 {math.hypot(x, z) / cam.s:.3f}" if cam.s else ""
        print(f"({u:.1f},{v:.1f}) → 地面 ({float(x):.1f}, {float(z):.1f}) ヒーロー px{s}、向き {math.degrees(math.atan2(z, x)):.1f}°")


def cmd_rect(args):
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    for n in args.n:
        r, ok, _, _ = rectify(fr, n, cam)
        img = np.clip(r, 0, 255).astype(np.uint8)
        img[~ok] = 0
        cv2.circle(img, (700, 650), 4, 255, -1)
        path = os.path.join(out_dir(args), f"rect_{n}.png")
        cv2.imwrite(path, img)
        print(f"真上から見た図（1 画素 = 1 ヒーロー px、ヒーロー = (700, 650)）→ {path}")


def cmd_montage(args):
    fr = Frames(args.frames, args.pattern)
    x0, y0, x1, y1 = [int(v) for v in args.box.split(",")]
    tiles = []
    for n in args.n:
        im = fr.bgr(n)[y0:y1, x0:x1]
        im = cv2.resize(im, None, fx=args.scale, fy=args.scale,
                        interpolation=cv2.INTER_AREA if args.scale < 1 else cv2.INTER_CUBIC)
        cv2.putText(im, f"{n} t={(n - 1) / args.fps:.2f}", (4, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1)
        tiles.append(im)
    h, w = tiles[0].shape[:2]
    cols = args.cols
    rows = (len(tiles) + cols - 1) // cols
    canvas = np.zeros((rows * h, cols * w, 3), np.uint8)
    for i, t in enumerate(tiles):
        r, c = divmod(i, cols)
        canvas[r * h:(r + 1) * h, c * w:(c + 1) * w] = t
    path = os.path.join(out_dir(args), f"montage_{args.n[0]}_{args.n[-1]}.png")
    cv2.imwrite(path, canvas)
    print(path)


def cmd_diff(args):
    fr = Frames(args.frames, args.pattern)
    d = fr.f32(args.a) - fr.f32(args.b)
    vis = np.clip(128 + d * args.gain, 0, 255).astype(np.uint8)
    path = os.path.join(out_dir(args), f"diff_{args.a}_{args.b}.png")
    cv2.imwrite(path, vis)
    print(path)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", help=f"出力のフォルダ（既定 {DEFAULT_OUT}。リポジトリの外に置く）")
    ap.add_argument("--cam", help="カメラの JSON（既定 <out>/cam.json）")
    ap.add_argument("--fps", type=float, default=30.0)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def frames_arg(p):
        p.add_argument("--frames", required=True, help="コマの PNG のフォルダ")
        p.add_argument("--pattern", default="%04d.png")

    p = sub.add_parser("ring", help="照準の円の縁を拾う")
    frames_arg(p)
    p.add_argument("--ref", type=int, required=True, help="照準の無い同じカメラ位置のコマ")
    p.add_argument("--at", required=True, help="照準のあるコマ（カンマ区切り。中央値を使う）")
    p.add_argument("--guess", required=True, help="中心 u,v と半軸 ax,ay の見当")
    p.add_argument("--exclude", action="append", help="除く箱 x0,y0,x1,y1（体・体力バー・ボタン）")
    p.add_argument("--min", type=float, default=12.0)
    p.add_argument("--name", required=True)
    p.set_defaults(fn=cmd_ring)

    p = sub.add_parser("camera", help="同心の照準円からカメラを当てはめる")
    p.add_argument("rings", nargs="+")
    p.set_defaults(fn=cmd_camera)

    p = sub.add_parser("speed", help="床の特徴点の歩きで縮尺を決める")
    frames_arg(p)
    p.add_argument("--from", dest="start", type=int, required=True)
    p.add_argument("--to", dest="end", type=int, required=True)
    p.add_argument("--floor", help="床の範囲: 中心 x,z（--from のコマのヒーロー px）と半径 r0,r1")
    p.add_argument("--speed", type=float, help="移動速度（MLBB の距離 / 秒。260 なら 2.6）")
    p.add_argument("--ui", action="append")
    p.set_defaults(fn=cmd_speed)

    p = sub.add_parser("move", help="止まったコマどうしの地面のずれ")
    frames_arg(p)
    p.add_argument("a", type=int)
    p.add_argument("b", type=int)
    p.add_argument("--patch", action="append", required=True, help="a の真上から見た図の小片 c,r,半幅")
    p.add_argument("--guess", help="ずれの見当 dx,dz（ヒーロー px）")
    p.add_argument("--search", type=int, default=40)
    p.set_defaults(fn=cmd_move)

    p = sub.add_parser("shape", help="照準の輪郭を地面へ")
    frames_arg(p)
    p.add_argument("--ref", type=int, required=True)
    p.add_argument("--at", required=True)
    p.add_argument("--roi", required=True)
    p.add_argument("--thr", type=float, default=25.0)
    p.add_argument("--name", required=True)
    p.set_defaults(fn=cmd_shape)

    p = sub.add_parser("trapezoid", help="輪郭の左右・奥の辺を当てはめる")
    p.add_argument("name")
    p.add_argument("--left")
    p.add_argument("--right")
    p.add_argument("--far")
    p.set_defaults(fn=cmd_trapezoid)

    p = sub.add_parser("bands", help="軸に沿った帯ごとの爆発の時刻")
    frames_arg(p)
    p.add_argument("--ref", type=int, required=True)
    p.add_argument("--from", dest="start", type=int, required=True)
    p.add_argument("--to", dest="end", type=int, required=True)
    p.add_argument("--axis", type=float, required=True, help="照準の軸の向き（度。地面の x 軸から反時計回り）")
    p.add_argument("--bands", required=True, help="lo:hi,lo:hi（軸方向のヒーロー px）")
    p.add_argument("--width", type=float, default=140.0, help="軸からの横の幅（ヒーロー px）")
    p.add_argument("--quantile", help="分布を出すコマ（カンマ区切り）")
    p.add_argument("--ui", action="append")
    p.set_defaults(fn=cmd_bands)

    p = sub.add_parser("point", help="画素 → 地面")
    p.add_argument("points", nargs="+")
    p.set_defaults(fn=cmd_point)

    p = sub.add_parser("rect", help="真上から見た図")
    frames_arg(p)
    p.add_argument("n", type=int, nargs="+")
    p.set_defaults(fn=cmd_rect)

    p = sub.add_parser("montage", help="コマの一覧")
    frames_arg(p)
    p.add_argument("--box", default="0,0,1108,512")
    p.add_argument("--scale", type=float, default=0.5)
    p.add_argument("--cols", type=int, default=6)
    p.add_argument("n", type=int, nargs="+")
    p.set_defaults(fn=cmd_montage)

    p = sub.add_parser("diff", help="差分画像")
    frames_arg(p)
    p.add_argument("a", type=int)
    p.add_argument("b", type=int)
    p.add_argument("--gain", type=float, default=3.0)
    p.set_defaults(fn=cmd_diff)

    args = ap.parse_args(argv)
    args.fn(args)


if __name__ == "__main__":
    main()
