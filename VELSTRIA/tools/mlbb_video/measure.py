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

Franco（docs/kits/Franco.md）で足したもの（カメラは Tigreal の cam.json をそのまま使う）:
  python measure.py arc    --frames F --ref 100 --at 80,84,88,92 --r0 7 --r1 9.5 --skip 25:50 --name s1   # 画面に収まらない大きな照準の円
  python measure.py lines  --frames F --ref 100 --at 80,84,88,92 --axis 37 --s0 1 --s1 7    # 線の照準の断面（向きと半幅）
  python measure.py tip    --frames F --ref 104 --from 107 --to 116 --p0 625,235 --p1 745,178 --theta 40.6 --smax 215   # 飛ぶ鉤の頭の速さ
  python measure.py bar    --frames F --tpl 178:570,146,640,170 --from 100 --to 160   # 的の体力バーの位置と CC の時間のバー（引き寄せ・CC の時刻）
  python measure.py walk   --frames F --from 500 --to 510   # 歩きの特徴点の変位の分布（床の塊 = 最も遅い山）

Aurora（docs/kits/Aurora.md）で足したもの（カメラは Tigreal の c・q。足元 u0, v0 は場面ごとに cam.json を書き換える）:
  python measure.py gshape  --frames F --ref 163 --at 159 --thr 20 --name s2   # 照準の扇・帯の形（歩きながらでも床のずれを打ち消す）
  python measure.py pcircle --frames F --ref 28 --at 44 --guess 3.4,4.3,1.9 --exclude 810,55,905,150 --name meteor   # 地点の照準の円

Zilong（docs/kits/Zilong.md）で足したもの:
  python measure.py panel  --frames F --tpl 457:697,69,752,84 --from 609 --to 722   # 的の総ダメージの表示が変わるコマ（三連突きの間隔）

Saber（docs/kits/Saber.md）で足したもの:
  python measure.py ringhp --frames F --at 59 --r0 3.5 --r1 5.5      # 参照のコマ無しで照準の円（歩きながら・1 コマでも拾える）
  python measure.py hpfill --frames F --tpl 340:770,143,875,178 --bar 26,21,112 --from 330 --to 490 --search 760,100,1108,300   # 的の体力バーの赤の長さ（最後の命中）

Alucard（docs/kits/Alucard.md）で足したもの（カメラは Tigreal の c・q、足元は S1 の射程の円で当て直した (557.3, 294.2)）:
  python measure.py bandlines --frames F --at 340,416 --axis 40 --exclude 810,60,900,140   # 向きの帯の照準（向き・左右の線・奥行き）
  python measure.py barground --frames F --tpl 180:722,119,835,154 --badge 12,23 --start-at 696,92 --from 472 --to 481   # 的の体力バー → 地面（速さ）
  python measure.py wipe      --frames F --x 470 --y 396 --from 425 --to 466   # バフのアイコンの時計回りの減り方（1 周の秒数 = バフの長さ）

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


def cmd_arc(args):
    """画面に収まらない大きな照準の円（Franco の鉤の射程など）: カメラ（cam.json）を固定して、術者から地面の放射に沿って
    照準の差分の強さが最大の半径（山の重心）を拾う。ring と違い楕円を当てはめないので、円の一部しか見えなくてよい。
    --skip で照準の線・扇の向き（度）を、--exclude で UI の箱を除く。結果は ring_<name>.json（camera に渡せる）。"""
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    sc = cyan_score(fr, [int(a) for a in args.at.split(",")], args.ref)
    H, W = sc.shape
    boxes = parse_boxes(args.exclude) + [DEFAULT_UI[0]]
    skips = [tuple(float(v) for v in s.split(":")) for s in (args.skip or [])]
    s = cam.s or 1.0
    out = []
    for deg in np.arange(-180, 180, args.step):
        if any(a0 <= deg <= a1 for a0, a1 in skips):
            continue
        t = math.radians(deg)
        rs = np.arange(args.r0, args.r1, 0.005) * s
        u, v = cam.project(rs * math.cos(t), rs * math.sin(t))
        ok = (u >= 1) & (u < W - 2) & (v >= 1) & (v < H - 2)
        if ok.sum() < len(rs) * 0.9:
            continue
        vals = map_coordinates(sc, [v, u], order=1, cval=-1e9)
        i = int(np.argmax(vals))
        if vals[i] < args.min or in_boxes(u[i], v[i], boxes):
            continue
        j0, j1 = max(0, i - 16), min(len(rs), i + 17)
        w = np.clip(vals[j0:j1] - vals[j0:j1].min(), 0, None)
        rc = float((rs[j0:j1] * w).sum() / w.sum()) if w.sum() > 0 else float(rs[i])
        out.append((deg, rc, float(u[i]), float(v[i])))
    if not out:
        raise SystemExit("縁が見つからない（--r0/--r1・--min・--ref を見直す）")
    A = np.array(out)
    med = np.median(A[:, 1])
    good = np.abs(A[:, 1] - med) < 0.15 * s
    unit = (lambda px: f"{px:.1f} px = {px / cam.s:.3f} 単位") if cam.s else (lambda px: f"{px:.1f} px")
    for lo in range(-180, 180, 30):
        m = (A[:, 0] >= lo) & (A[:, 0] < lo + 30)
        if m.sum():
            print(f"  {lo:+4d}°: {unit(float(np.median(A[m, 1])))}（{m.sum()} 点）")
    print(f"{args.name}: 半径 {unit(float(A[good, 1].mean()))} ± {A[good, 1].std():.2f} px（{good.sum()} 点、角度 "
          f"{A[:, 0].min():.0f}〜{A[:, 0].max():.0f}°）")
    with open(os.path.join(out_dir(args), f"ring_{args.name}.json"), "w", encoding="utf-8") as f:
        json.dump({"points": A[good][:, 2:4].tolist(), "radius_px": float(A[good, 1].mean())}, f)


def cmd_lines(args):
    """線の照準（鉤・突進の矢印）の断面: 軸（--axis 度）に直交する断面ごとに、照準の差分の山（線）の横の位置を出す。
    山の横の位置が軸に沿って一定の割合でずれていれば、軸の向きがずれている（ずれ / 奥行き = tan）。左右の線の間 / 2 = 半幅。"""
    from scipy.signal import find_peaks
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    sc = cyan_score(fr, [int(a) for a in args.at.split(",")], args.ref)
    t = math.radians(args.axis)
    ax = np.array([math.cos(t), math.sin(t)])
    nr = np.array([-math.sin(t), math.cos(t)])
    s = cam.s or 1.0
    rows = []
    for d in np.arange(args.s0, args.s1, 0.25):
        es = np.arange(-args.half, args.half, 0.005)
        P = (d * ax[None, :] + es[:, None] * nr[None, :]) * s
        u, v = cam.project(P[:, 0], P[:, 1])
        vals = map_coordinates(sc, [v, u], order=1, cval=0)
        idx, _ = find_peaks(vals, height=args.min, distance=20)
        rows.append((d, [float(es[i]) for i in idx]))
        print(f"奥行き {d:.2f}: 線の横 " + "  ".join(f"{es[i]:+.3f}" for i in idx))
    # 一番左・一番右の線の直線の当てはめ（向きのずれと半幅）
    L = np.array([(d, p[0]) for d, p in rows if len(p) >= 2])
    R = np.array([(d, p[-1]) for d, p in rows if len(p) >= 2])
    if len(L) >= 3:
        pl, pr = np.polyfit(L[:, 0], L[:, 1], 1), np.polyfit(R[:, 0], R[:, 1], 1)
        slope = (pl[0] + pr[0]) / 2
        half = float(np.mean(np.polyval(pr, L[:, 0]) - np.polyval(pl, L[:, 0]))) / 2 * math.cos(math.atan(slope))
        mid0 = (pl[1] + pr[1]) / 2
        print(f"向き {args.axis + math.degrees(math.atan(slope)):.1f}°、半幅 {half:.3f} 単位、術者の位置での中心の横 {mid0:+.3f}"
              f"（左右の線の開き {math.degrees(math.atan(pr[0]) - math.atan(pl[0])):+.2f}°）")


def cmd_tip(args):
    """飛ぶもの（鉤・弾）の頭: 画面の直線（--p0 → --p1。手元から飛ぶ向き）から --width 以内で、発射前（--ref）とも前のコマとも
    違う画素の、線に沿った最も先の点。宙に浮いた物は地面へ戻すと奥へずれるので、横の座標 u だけで地面の距離を出す:
    r = (u − u0) / (cos θ − q (u − u0) sin θ)（θ = 飛ぶ向き。lines で測る）。的の手前まで（--smax）で当てはめる。"""
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    p0 = np.array([float(v) for v in args.p0.split(",")])
    p1 = np.array([float(v) for v in args.p1.split(",")])
    d = (p1 - p0) / np.linalg.norm(p1 - p0)
    nrm = np.array([-d[1], d[0]])
    H, W = fr.bgr(args.ref).shape[:2]
    vs, us = np.mgrid[0:H, 0:W]
    s_ = (us - p0[0]) * d[0] + (vs - p0[1]) * d[1]
    e_ = (us - p0[0]) * nrm[0] + (vs - p0[1]) * nrm[1]
    band = (np.abs(e_) < args.width) & (s_ > args.smin) & (s_ < args.smax)
    R = fr.f32(args.ref)
    P = fr.f32(args.start - 1)
    th = math.radians(args.theta)
    rows = []
    for n in range(args.start, args.end):
        C = fr.f32(n)
        m = band & (np.abs(C - R).max(axis=2) > args.thr) & (np.abs(C - P).max(axis=2) > args.thr)
        P = C
        if m.sum() < 5:
            print(f"{n}: 動く画素が少ない")
            continue
        S = s_[m]
        k = np.argsort(S)[min(m.sum() - 1, int(args.q * m.sum()))]
        tu, tv = us[m][k], vs[m][k]
        du = tu - cam.u0
        r = du / (math.cos(th) - cam.q * du * math.sin(th))
        rows.append((n, r))
        print(f"{n} t={(n - 1) / args.fps:.3f} 頭 ({tu},{tv}) 距離 {r:.1f} px" + (f" = {r / cam.s:.3f} 単位" if cam.s else ""))
    if len(rows) >= 3:
        A = np.array(rows)
        p = np.polyfit(A[:, 0], A[:, 1], 1)
        res = A[:, 1] - np.polyval(p, A[:, 0])
        v = p[0] * args.fps
        print(f"速さ {p[0]:.2f} px/コマ" + (f" = 毎秒 {v / cam.s:.2f} 単位" if cam.s else "")
              + f"（残差 {res.std():.1f} px）、距離 0 のコマ {-p[1] / p[0]:.2f}")


def cmd_bar(args):
    """的（または味方）の体力バーを追う: --tpl コマ:x0,y0,x1,y1（バッジとバーの左端の箱）のテンプレートで各コマの位置を出す。
    バーの位置は画面の固定のずれでユニットの足元に付いてくるので、引き寄せ・突進の始まりと終わりのコマが分かる。
    バーのすぐ上の白い線（CC の時間のバー）の長さも出す（線の右端が縮む速さ = 残り時間。新しい CC で満タンに戻る）。"""
    fr = Frames(args.frames, args.pattern)
    tn, box = args.tpl.split(":")
    x0, y0, x1, y1 = [int(v) for v in box.split(",")]
    tpl = fr.bgr(int(tn))[y0:y1, x0:x1]
    sx0, sy0, sx1, sy1 = [int(v) for v in args.search.split(",")]
    prev = None
    for n in range(args.start, args.end):
        im = fr.bgr(n)
        r = cv2.matchTemplate(im[sy0:sy1, sx0:sx1], tpl, cv2.TM_CCOEFF_NORMED)
        _, mv, _, ml = cv2.minMaxLoc(r)
        px, py = ml[0] + sx0, ml[1] + sy0
        line = ""
        if py >= 1:
            band = im[py:py + 3, px + 20:px + 130].astype(int).min(axis=2).max(axis=0)
            cols = np.nonzero(band > 150)[0]
            if len(cols):
                end = cols[0]
                for c in cols[1:]:
                    if c - end > 4:
                        break
                    end = c
                line = f" CC の線 {end - cols[0] + 1:3d} px"
        mv_ = "" if prev is None else f" 動き {math.hypot(px - prev[0], py - prev[1]):5.1f}"
        print(f"{n} t={(n - 1) / args.fps:.3f} バー ({px},{py}) 一致 {mv:.2f}{mv_}{line}")
        prev = (px, py)


def cmd_panel(args):
    """的の情報パネル（訓練場の「総ダメージ」の行）が変わるコマ = ダメージが入ったコマ。ダメージの数字（出始めが重なって 1 コマ遅れて
    見える）より正確で、体力が 1 で止まった的にも使える（Zilong の三連突きの間隔）。--tpl コマ:x0,y0,x1,y1 は「総ダメージ」の文字の箱、
    --box dx0,dy0,dx1,dy1 はその左上から見た数字の箱。パネルは的に付いて動くので、パネルが動いたコマ（位置の列）の変化は無視する。"""
    fr = Frames(args.frames, args.pattern)
    tn, box = args.tpl.split(":")
    x0, y0, x1, y1 = [int(v) for v in box.split(",")]
    tpl = fr.bgr(int(tn))[y0:y1, x0:x1]
    ox0, oy0, ox1, oy1 = [int(v) for v in args.box.split(",")]
    prev = None
    prev_at = None
    for n in range(args.start, args.end + 1):
        im = fr.bgr(n)
        r = cv2.matchTemplate(im, tpl, cv2.TM_CCOEFF_NORMED)
        _, mv, _, (px, py) = cv2.minMaxLoc(r)
        digits = (im[py + oy0:py + oy1, px + ox0:px + ox1].astype(np.float32).mean(axis=2) > 170).astype(np.float32)
        d = None if prev is None or prev.shape != digits.shape else float(np.abs(digits - prev).sum())
        moved = prev_at is not None and (px, py) != prev_at
        mark = "" if d is None or d <= args.min else ("  （パネルが動いた）" if moved else "  <== 変化")
        print(f"{n} t={(n - 1) / args.fps:.3f} 一致 {mv:.2f} 位置 ({px},{py}) 変化 {d if d is not None else -1:5.0f}{mark}")
        prev, prev_at = digits, (px, py)


def cmd_ringhp(args):
    """照準の円（水色の細い線）を参照のコマ無しで拾う（Saber の S1・S2・奥義の照準、通常攻撃・強化通常攻撃の足元の円）: 色の強さ
    ((B+G)/2 − R) から 15 px の箱の平均を引いた高域の図（--at の数コマの中央値）で、足元から地面の放射ごとに [r0, r1] の山を拾う。
    歩いている間でも使える（ring・arc は止まったコマの差分が要る）。体力バー・矢印の向きは --skip（度）・--exclude（箱）で除く。"""
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    if not cam.s:
        raise SystemExit("縮尺 s が未定（先に speed を回す）")
    acc = []
    for n in [int(a) for a in args.at.split(",")]:
        im = fr.f32(n)
        sc = (im[..., 0] + im[..., 1]) / 2 - im[..., 2]
        acc.append(sc - cv2.blur(sc, (15, 15)))
    sc = cv2.GaussianBlur(np.median(np.array(acc), axis=0).astype(np.float32), (3, 3), 0)
    H, W = sc.shape
    boxes = parse_boxes(args.exclude) + list(DEFAULT_UI[:1]) + [(700, 230, 1108, 512), (530, 380, 720, 512), (100, 300, 320, 512)]
    skips = [tuple(float(v) for v in s.split(":")) for s in (args.skip or [])]
    out = []
    for deg in np.arange(-180, 180, 2.0):
        if any(a0 <= deg <= a1 for a0, a1 in skips):
            continue
        t = math.radians(deg)
        rs = np.arange(args.r0, args.r1, 0.005) * cam.s
        u, v = cam.project(rs * math.cos(t), rs * math.sin(t))
        if ((u >= 1) & (u < W - 2) & (v >= 1) & (v < H - 2)).sum() < len(rs) * 0.95:
            continue
        vals = map_coordinates(sc, [v, u], order=1)
        i = int(np.argmax(vals))
        if vals[i] < args.min or in_boxes(u[i], v[i], boxes):
            continue
        out.append((deg, rs[i] / cam.s))
    if not out:
        raise SystemExit("縁が見つからない（--r0/--r1・--min を見直す）")
    A = np.array(out)
    for lo in range(-180, 180, 30):
        m = (A[:, 0] >= lo) & (A[:, 0] < lo + 30)
        if m.sum():
            print(f"  {lo:+4d}°: {np.median(A[m, 1]):.3f}（{m.sum()} 本）")
    med = np.median(A[:, 1])
    good = np.abs(A[:, 1] - med) < 0.15
    print(f"半径 {A[good, 1].mean():.3f} ± {A[good, 1].std():.3f} 単位（{good.sum()} / {len(A)} 本、中央値 {med:.3f}）")


def cmd_hpfill(args):
    """的の体力バーの赤い部分の長さ（画素）をコマごとに出す。赤が縮んだコマ = ダメージが入ったコマ（総ダメージの数字が UI に隠れても読める。
    Saber の防御ダウンの最後の命中）。--tpl は名前の文字 + バッジ（同じ見た目のほかの的と取り違えないように名前を含める）、--bar は
    テンプレートの左上から見たバーの左端・赤を数える行・右端。--search で探す範囲を絞る。"""
    fr = Frames(args.frames, args.pattern)
    tn, box = args.tpl.split(":")
    x0, y0, x1, y1 = [int(v) for v in box.split(",")]
    tpl = fr.bgr(int(tn))[y0:y1, x0:x1]
    bx0, by, bx1 = [int(v) for v in args.bar.split(",")]
    sx0, sy0, sx1, sy1 = [int(v) for v in args.search.split(",")]
    prev = None
    for n in range(args.start, args.end + 1):
        im = fr.bgr(n)
        r = cv2.matchTemplate(im[sy0:sy1, sx0:sx1], tpl, cv2.TM_CCOEFF_NORMED)
        _, mv, _, (px, py) = cv2.minMaxLoc(r)
        px, py = px + sx0, py + sy0
        row = im[py + by - 1:py + by + 2, px + bx0:px + bx1].astype(int).mean(axis=0)
        red = (row[:, 2] > 150) & (row[:, 1] < 90) & (row[:, 0] < 90)
        rx = np.nonzero(red)[0]
        rend = int(rx.max()) + 1 if len(rx) else 0
        mark = "" if prev is None or prev == rend else f"  <== 赤 {prev} → {rend}"
        print(f"{n} t={(n - 1) / args.fps:.3f} 一致 {mv:.2f} 位置 ({px},{py}) 赤 {rend:3d} px{mark}")
        prev = rend


def cmd_walk(args):
    """歩きの 1 コマの特徴点の変位（地面へ戻した、歩く向きの成分）の分布。床の点は最も遅い塊、岩・草など高い所の点は速い。
    --floor を決める前の見当に使う（Tigreal: 床 5.40、全部の点の中央値 5.75）。"""
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    shape = fr.bgr(args.start).shape
    ui = ui_mask(shape, DEFAULT_UI if not args.ui else parse_boxes(args.ui))
    allD = []
    for n in range(args.start, args.end):
        D, _ = track_pair(fr.gray(n), fr.gray(n + 1), ui, cam)
        g, _ = robust_mean(D, tol=1.5)
        if g is None:
            continue
        t = g / np.linalg.norm(g)
        along = D @ t
        ok = np.abs(D @ np.array([-t[1], t[0]])) < 0.6
        allD.append(along[ok])
        q = np.percentile(along[ok], [5, 25, 50, 75, 95])
        print(f"{n}: 点 {ok.sum():3d}  5%={q[0]:.2f} 25%={q[1]:.2f} 50%={q[2]:.2f} 75%={q[3]:.2f} 95%={q[4]:.2f}")
    if not allD:
        return
    A = np.concatenate(allD)
    h, e = np.histogram(A, bins=np.arange(np.percentile(A, 1) - 0.2, np.percentile(A, 99) + 0.2, 0.1))
    for c, lo in zip(h, e):
        print(f"{lo:5.2f} {'#' * int(60 * c / max(1, h.max()))} {c}")


def ground_shift(fr: Frames, cam: GroundCam, a: int, b: int, ui, min_points: int = 40) -> np.ndarray:
    """コマ a → b の地面の模様のずれ（ヒーロー px。1 コマずつの特徴点の変位を足す）。歩いている間に使う。
    止まっているコマでは動く点がほとんど無く（演出・草の揺れだけ）、その変位を足すとずれがたまるので、
    動いた点が min_points 未満のコマは 0 とする（歩いているコマは 200〜400 点）。"""
    D = np.zeros(2)
    step = 1 if b >= a else -1
    for n in range(a, b, step):
        d, _ = track_pair(fr.gray(n), fr.gray(n + step), ui, cam)
        g, k = robust_mean(d)
        if g is not None and k >= min_points:
            D = D + g
    return D


def rectify_bgr(fr: Frames, n: int, cam: GroundCam, xr, zr, shift=(0.0, 0.0)):
    """真上から見た図（色）。shift = 地面のずれ（ヒーロー px）を打ち消して、別のコマの地面に重ねる。"""
    xs = np.arange(xr[0], xr[1], 1.0)
    zs = np.arange(zr[1], zr[0], -1.0)
    GX, GZ = np.meshgrid(xs, zs)
    U, V = cam.project(GX.ravel() - shift[0], GZ.ravel() - shift[1])
    im = fr.f32(n)
    out = np.stack([map_coordinates(im[..., c], [V, U], order=1, cval=0).reshape(GX.shape) for c in range(3)], axis=2)
    H, W = im.shape[:2]
    ok = ((U >= 0) & (U < W - 1) & (V >= 0) & (V < H - 1)).reshape(GX.shape)
    return out, ok, U.reshape(GX.shape), V.reshape(GX.shape)


def cmd_gshape(args):
    """歩きながら出した照準（扇・帯）の形: 照準の無いコマ（--ref）の地面を、照準のコマ（--at）の地面のずれだけ動かして重ね、
    真上から見た図の上で照準（水色）の差分を取る（カメラはヒーローに固定なので、照準はヒーローに付いて動き、床は逆へ流れる）。
    輪郭を地面（単位）で shape と同じ JSON に書く（trapezoid にそのまま渡せる）。高い所（岩・草）は床とずれるので残る。"""
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    shape = fr.bgr(args.ref).shape
    ui = ui_mask(shape, DEFAULT_UI if not args.ui else parse_boxes(args.ui))
    boxes = parse_boxes(args.exclude)
    xr, zr = (-700, 700), (-250, 650)
    scores = []
    for n in [int(a) for a in args.at.split(",")]:
        D = ground_shift(fr, cam, args.ref, n, ui)
        A, oka, U, V = rectify_bgr(fr, n, cam, xr, zr)
        R, okr, _, _ = rectify_bgr(fr, args.ref, cam, xr, zr, shift=D)
        d = A - R
        sc = (d[..., 0] + d[..., 1]) / 2 - np.maximum(d[..., 2], 0) * 0.5
        bad = ~(oka & okr)
        for x0, y0, x1, y1 in boxes:
            bad |= (U >= x0) & (U <= x1) & (V >= y0) & (V <= y1)
        sc[bad] = np.nan
        scores.append(sc)
        print(f"コマ {n}: 地面のずれ ({D[0]:+.1f}, {D[1]:+.1f}) ヒーロー px = {math.hypot(*D) / (cam.s or 1):.2f}"
              + (" 単位" if cam.s else ""))
    sc = np.nanmedian(np.array(scores), axis=0)
    sc = np.nan_to_num(sc, nan=0.0).astype(np.float32)
    sc = cv2.GaussianBlur(sc, (5, 5), 0)
    m = (sc > args.thr).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n_, lab, st, _ = cv2.connectedComponentsWithStats(m)
    if n_ < 2:
        raise SystemExit("照準が見つからない（--thr を下げる・--ref を確かめる）")
    m = (lab == 1 + np.argmax(st[1:, cv2.CC_STAT_AREA])).astype(np.uint8)
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cnts, key=cv2.contourArea).reshape(-1, 2).astype(float)
    X, Z = cam.units(c[:, 0] + xr[0]), cam.units(zr[1] - c[:, 1])
    d = out_dir(args)
    with open(os.path.join(d, f"shape_{args.name}.json"), "w", encoding="utf-8") as f:
        json.dump({"ground": np.c_[X, Z].tolist()}, f)
    topdown_png(os.path.join(d, f"shape_{args.name}_top.png"), [np.c_[X, Z]], cam.s)
    vis = np.clip(128 + sc * 2, 0, 255).astype(np.uint8)
    vis = cv2.cvtColor(vis, cv2.COLOR_GRAY2BGR)
    cv2.drawContours(vis, [c.astype(np.int32).reshape(-1, 1, 2)], -1, (0, 0, 255), 1)
    cv2.circle(vis, (-xr[0], zr[1]), 4, (0, 255, 0), -1)
    cv2.imwrite(os.path.join(d, f"gshape_{args.name}.png"), vis)
    np.save(os.path.join(d, f"gshape_{args.name}.npy"), sc)
    r = np.hypot(X, Z)
    print(f"{args.name}: 輪郭 {len(c)} 点、術者からの距離 最小 {r.min():.2f} / 最大 {r.max():.2f} 単位 → {d}")


def cmd_pcircle(args):
    """地点の照準の円（Aurora の隕石の着弾点など、中心が術者でない地面の円）: カメラを固定して、地面の円（中心 cx,cz・半径 r。単位）を
    画面へ写した円周の上の照準の差分の強さの平均が最大になる所を探す（格子で粗く → Nelder-Mead）。楕円の当てはめと違い、UI に隠れた
    所（--exclude）を除いても形が崩れない。確かめに、角度 15° ごとの放射で縁の半径（差分の山）を出す。"""
    from scipy.optimize import minimize
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    if not cam.s:
        raise SystemExit("縮尺 s が未定（先に speed を回す）")
    sc = cyan_score(fr, [int(a) for a in args.at.split(",")], args.ref)
    H, W = sc.shape
    boxes = parse_boxes(args.exclude) + [DEFAULT_UI[0]]
    t = np.radians(np.arange(0, 360, 1.0))

    def ring(cx, cz, r):
        u, v = cam.project((cx + r * np.cos(t)) * cam.s, (cz + r * np.sin(t)) * cam.s)
        ok = (u >= 1) & (u < W - 2) & (v >= 1) & (v < H - 2)
        for x0, y0, x1, y1 in boxes:
            ok &= ~((u >= x0) & (u <= x1) & (v >= y0) & (v <= y1))
        return map_coordinates(sc, [v, u], order=1, cval=0), ok

    def score(p):
        vals, ok = ring(*p)
        return 0.0 if ok.sum() < 60 else -float(np.mean(np.clip(vals[ok], -20, 60)))

    cx0, cz0, r0 = [float(v) for v in args.guess.split(",")]
    sp = args.span
    best = None
    for cx in np.arange(cx0 - sp, cx0 + sp + 1e-9, 0.05):
        for cz in np.arange(cz0 - sp, cz0 + sp + 1e-9, 0.05):
            for r in np.arange(max(0.3, r0 - sp), r0 + sp + 1e-9, 0.05):
                v = score((cx, cz, r))
                if best is None or v < best[0]:
                    best = (v, cx, cz, r)
    res = minimize(score, best[1:], method="Nelder-Mead", options=dict(xatol=1e-3, fatol=1e-3))
    cx, cz, r = res.x
    _, ok = ring(cx, cz, r)
    rr = np.arange(r - 0.4, r + 0.4, 0.01)
    peaks = []
    for deg in range(0, 360, 15):
        th = math.radians(deg)
        u, v = cam.project((cx + rr * math.cos(th)) * cam.s, (cz + rr * math.sin(th)) * cam.s)
        if not ((u >= 1) & (u < W - 2) & (v >= 1) & (v < H - 2)).all() or in_boxes(u.mean(), v.mean(), boxes):
            continue
        vv = map_coordinates(sc, [v, u], order=1, cval=0)
        i = int(np.argmax(vv))
        if vv[i] > args.min:
            peaks.append(rr[i])
    P = np.array(peaks)
    print(f"{args.name}: 中心 ({cx:.3f}, {cz:.3f}) = 術者から {math.hypot(cx, cz):.3f}・向き {math.degrees(math.atan2(cz, cx)):.1f}°、"
          f"半径 {r:.3f} 単位（円周の強さ {-res.fun:.1f}、使った点 {ok.sum()}）"
          + (f"、放射ごとの縁 {np.median(P):.3f} ± {P.std():.3f}（{len(P)} 本）" if len(P) else ""))


def aim_mask(im: np.ndarray) -> np.ndarray:
    """照準の水色の線（B, G が高く R が低い）の 0/1 マスク。ミニマップは除く。"""
    b, g, r = (im[..., k].astype(int) for k in range(3))
    m = (b > 170) & (g > 150) & (r < 140) & (b - r > 90)
    m[:175, :215] = False
    return m


def cmd_bandlines(args):
    """向きの帯の照準（Alucard の吸収・衝撃波の照準）: 水色の画素を地面へ戻し、帯の向き（横の位置の分布が最も尖る向き）を探してから、
    横の位置の山（左右の線・中央の矢印）と、それぞれの線の奥行きの範囲を出す。参照のコマは要らない（歩きながら・回しながらでも 1 コマで測れる）。"""
    from scipy.signal import find_peaks
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    if not cam.s:
        raise SystemExit("縮尺 s が未定（先に speed を回す）")
    boxes = parse_boxes(args.exclude)
    for n in [int(a) for a in args.at.split(",")]:
        m = aim_mask(fr.bgr(n))
        for x0, y0, x1, y1 in boxes:
            m[y0:y1, x0:x1] = False
        vs, us = np.nonzero(m)
        x, z = cam.unproject(us, vs)
        x, z = x / cam.s, z / cam.s
        best = None
        for th in np.arange(args.axis - 8, args.axis + 8, 0.1):
            t = math.radians(th)
            a = x * math.cos(t) + z * math.sin(t)
            e = -x * math.sin(t) + z * math.cos(t)
            sel = (a > args.a0) & (a < args.a1) & (np.abs(e) < args.half)
            h, _ = np.histogram(e[sel], bins=np.arange(-args.half, args.half, 0.03))
            sc = float((h.astype(float) ** 2).sum())
            if best is None or sc > best[0]:
                best = (sc, th)
        th = best[1]
        t = math.radians(th)
        a = x * math.cos(t) + z * math.sin(t)
        e = -x * math.sin(t) + z * math.cos(t)
        sel = (a > args.a0) & (a < args.a1) & (np.abs(e) < args.half)
        h, edges = np.histogram(e[sel], bins=np.arange(-args.half, args.half, 0.03))
        pk, _ = find_peaks(h, height=max(15, h.max() * 0.15), distance=8)
        print(f"コマ {n}: 帯の向き {th:.1f}°")
        for i in pk:
            lo = edges[i]
            near = (e >= lo - 0.06) & (e < lo + 0.09)
            off = float(e[near & sel].mean())
            along = a[near & (a > 0) & (a < 12)]
            print(f"  線の横 {off:+.3f}（{h[i]} 点）、奥行き {np.percentile(along, 1):.2f}〜{np.percentile(along, 99):.2f} 単位")


def ground_at_height(cam: GroundCam, u, v, h):
    """画面の点 (u, v) が地面から高さ h（ヒーロー px）にあるとしたときの真下の地面 (x, z)（ヒーロー px）。
    地面の写像（c, q）を同じ遠近のピンホールとして読み替える: 足元での高さ 1 px の上向き = cos φ（sin φ = c）、奥行きの変化 = sin φ × q / cos φ。"""
    phi = math.asin(cam.c)
    k = math.cos(phi)
    q2 = math.sin(phi) * cam.q / math.cos(phi)
    dv = cam.v0 - np.asarray(v, float)
    z = (dv * (1 - q2 * h) - k * h) / (cam.c - cam.q * dv)
    x = (np.asarray(u, float) - cam.u0) * (1 + cam.q * z - q2 * h)
    return x, z


def cmd_barground(args):
    """的（止まったユニット）の体力バーを前のコマの近くだけで追い（同じ見た目のほかの的に跳ばない）、バッジの中心を地面の上の高さ --height
    （ヒーロー px）の点として真下の地面へ戻す。術者はカメラの中心なので、的の位置の変化 = 術者の動き（逆向き）。床の模様より速さが正確
    （Saber の動画: 床の特徴点は高い所の点で 1.2 倍速く出る）。--tpl はバッジ（レベルの丸）を含む箱、--badge はその左上から見たバッジの中心、
    --dx は足元がバッジの中心から右へずれる量（ヒーロー px。自分の体力バーと足元から 52）。"""
    fr = Frames(args.frames, args.pattern)
    cam = load_cam(args)
    if not cam.s:
        raise SystemExit("縮尺 s が未定（先に speed を回す）")
    tn, box = args.tpl.split(":")
    x0, y0, x1, y1 = [int(v) for v in box.split(",")]
    tpl = fr.bgr(int(tn))[y0:y1, x0:x1]
    h, w = tpl.shape[:2]
    bx, by = [float(v) for v in args.badge.split(",")]
    pu, pv = (float(v) for v in args.start_at.split(",")) if args.start_at else (x0, y0)
    step = 1 if args.end >= args.start else -1
    prev = None
    for n in range(args.start, args.end + step, step):
        im = fr.bgr(n)
        sx0, sy0 = int(max(0, pu - args.search)), int(max(0, pv - args.search))
        sx1, sy1 = int(min(im.shape[1], pu + w + args.search)), int(min(im.shape[0], pv + h + args.search))
        r = cv2.matchTemplate(im[sy0:sy1, sx0:sx1], tpl, cv2.TM_CCOEFF_NORMED)
        _, mv, _, ml = cv2.minMaxLoc(r)
        pu, pv = ml[0] + sx0, ml[1] + sy0
        gx, gz = ground_at_height(cam, pu + bx, pv + by, args.height)
        X, Z = (gx + args.dx) / cam.s, gz / cam.s
        mv_ = "" if prev is None else f"  1 コマ {math.hypot(X - prev[0], Z - prev[1]):.3f}"
        print(f"{n} t={(n - 1) / args.fps:.3f} 一致 {mv:.2f} 的 ({X:+.3f}, {Z:+.3f}) 距離 {math.hypot(X, Z):.3f} 単位{mv_}")
        prev = (X, Z)


def cmd_wipe(args):
    """バフのアイコンの時計回りの暗い扇（残り時間）: アイコン（--x, --y, --size の箱。コマごとに同じ所）を中心から 10° ごとの扇に分け、
    扇の明るさが初めと最後の中間を下回るコマを出す。角度とコマを直線で当てはめ、1 周（360°）のコマ数 = バフの長さ。
    Alucard の追撃のアイコンで 3.7〜4.2 秒、奥義のアイコンで 5.7〜5.9 秒（体力バーの印の 6.1 秒より 4〜7% 短く出る）。アイコンの列は増減で横にずれるので、
    区間はアイコンが同じ所にある間だけにする。"""
    fr = Frames(args.frames, args.pattern)
    sec = args.sector
    S = args.size
    rows = []
    for n in range(args.start, args.end + 1):
        ic = fr.bgr(n)[args.y:args.y + S, args.x:args.x + S].astype(float).mean(axis=2)
        c = (S - 1) / 2
        yy, xx = np.mgrid[0:S, 0:S]
        ang = np.degrees(np.arctan2(c - xx, c - yy)) % 360          # 0 = 上、反時計回り（画面で左回り）
        rr = np.hypot(xx - c, yy - c)
        rows.append([ic[(rr > 3) & (rr < c - 1.5) & (ang >= q) & (ang < q + sec)].mean() for q in np.arange(0, 360, sec)])
    A = np.array(rows)
    ns = np.arange(args.start, args.end + 1)
    pts = []
    for k, q in enumerate(np.arange(0, 360, sec)):
        s = A[:, k]
        hi, lo = float(np.median(s[:2])), float(s.min())
        if hi - lo < args.min or s[-1] > hi - args.min * 0.8:
            continue
        mid = (hi + lo) / 2
        i = int(np.argmax(s < mid))
        if i == 0:
            continue
        t = ns[i - 1] + (s[i - 1] - mid) / (s[i - 1] - s[i])
        pts.append((q + sec / 2, t))
        print(f"  扇 {q:5.1f}〜{q + sec:5.1f}°: 明るさ {hi:.0f} → {lo:.0f}、中間を下回るコマ {t:.1f}")
    if len(pts) < 3:
        raise SystemExit("暗くなる扇が少ない（区間を延ばす・--min を下げる）")
    P = np.array(pts)
    p = np.polyfit(P[:, 0], P[:, 1], 1)
    print(f"1 周 = {p[0] * 360:.0f} コマ = {p[0] * 360 / args.fps:.2f} 秒（扇 {len(P)} 個、0° のコマ {p[1]:.1f}）")


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

    p = sub.add_parser("arc", help="画面に収まらない大きな照準の円（カメラ固定・放射ごと）")
    frames_arg(p)
    p.add_argument("--ref", type=int, required=True)
    p.add_argument("--at", required=True)
    p.add_argument("--r0", type=float, required=True, help="探す半径の下限（単位）")
    p.add_argument("--r1", type=float, required=True, help="探す半径の上限（単位）")
    p.add_argument("--step", type=float, default=0.5, help="角度の刻み（度）")
    p.add_argument("--skip", action="append", help="除く角度 a0:a1（度。照準の線・扇）")
    p.add_argument("--exclude", action="append", help="除く箱 x0,y0,x1,y1")
    p.add_argument("--min", type=float, default=12.0)
    p.add_argument("--name", required=True)
    p.set_defaults(fn=cmd_arc)

    p = sub.add_parser("lines", help="線の照準の断面（向きと半幅）")
    frames_arg(p)
    p.add_argument("--ref", type=int, required=True)
    p.add_argument("--at", required=True)
    p.add_argument("--axis", type=float, required=True, help="軸の見当（度）")
    p.add_argument("--s0", type=float, default=1.0)
    p.add_argument("--s1", type=float, default=6.0)
    p.add_argument("--half", type=float, default=1.2, help="断面の横の範囲（単位）")
    p.add_argument("--min", type=float, default=15.0)
    p.set_defaults(fn=cmd_lines)

    p = sub.add_parser("tip", help="飛ぶものの頭の速さ（画面の横の座標から）")
    frames_arg(p)
    p.add_argument("--ref", type=int, required=True, help="発射前のコマ")
    p.add_argument("--from", dest="start", type=int, required=True)
    p.add_argument("--to", dest="end", type=int, required=True)
    p.add_argument("--p0", required=True, help="手元の画素 u,v")
    p.add_argument("--p1", required=True, help="飛ぶ向きの先の画素 u,v")
    p.add_argument("--theta", type=float, required=True, help="地面での飛ぶ向き（度。lines で測る）")
    p.add_argument("--width", type=float, default=14.0)
    p.add_argument("--smin", type=float, default=30.0, help="線に沿った下限（画素。手元の体を除く）")
    p.add_argument("--smax", type=float, default=1e9, help="線に沿った上限（画素。的の手前まで）")
    p.add_argument("--thr", type=float, default=40.0)
    p.add_argument("--q", type=float, default=0.99)
    p.set_defaults(fn=cmd_tip)

    p = sub.add_parser("bar", help="体力バーの位置と CC の時間のバー")
    frames_arg(p)
    p.add_argument("--tpl", required=True, help="コマ:x0,y0,x1,y1（バッジとバーの左端）")
    p.add_argument("--search", default="200,0,1000,330", help="探す範囲 x0,y0,x1,y1")
    p.add_argument("--from", dest="start", type=int, required=True)
    p.add_argument("--to", dest="end", type=int, required=True)
    p.set_defaults(fn=cmd_bar)

    p = sub.add_parser("walk", help="歩きの特徴点の変位の分布（床の見当）")
    frames_arg(p)
    p.add_argument("--from", dest="start", type=int, required=True)
    p.add_argument("--to", dest="end", type=int, required=True)
    p.add_argument("--ui", action="append")
    p.set_defaults(fn=cmd_walk)

    p = sub.add_parser("gshape", help="歩きながらの照準の形（床のずれを打ち消して地面で差分）")
    frames_arg(p)
    p.add_argument("--ref", type=int, required=True, help="照準の無いコマ（照準のコマの近く）")
    p.add_argument("--at", required=True, help="照準のコマ（カンマ区切り。それぞれ ref に重ねて中央値）")
    p.add_argument("--thr", type=float, default=20.0)
    p.add_argument("--exclude", action="append", help="除く画面の箱 x0,y0,x1,y1（体・体力バー・ボタン）")
    p.add_argument("--ui", action="append", help="地面のずれを測るときに除く UI の箱（既定 DEFAULT_UI）")
    p.add_argument("--name", required=True)
    p.set_defaults(fn=cmd_gshape)

    p = sub.add_parser("pcircle", help="地点の照準の円（中心が術者でない地面の円）の中心と半径")
    frames_arg(p)
    p.add_argument("--ref", type=int, required=True, help="照準の無いコマ")
    p.add_argument("--at", required=True, help="照準のコマ（カンマ区切り。中央値）")
    p.add_argument("--guess", required=True, help="中心 x,z と半径の見当（単位）")
    p.add_argument("--span", type=float, default=0.6, help="格子で探す幅（単位）")
    p.add_argument("--exclude", action="append", help="除く箱 x0,y0,x1,y1")
    p.add_argument("--min", type=float, default=15.0)
    p.add_argument("--name", required=True)
    p.set_defaults(fn=cmd_pcircle)

    p = sub.add_parser("panel", help="的の総ダメージの表示が変わるコマ（ダメージの時刻）")
    frames_arg(p)
    p.add_argument("--tpl", required=True, help="コマ:x0,y0,x1,y1（「総ダメージ」の文字）")
    p.add_argument("--box", default="55,0,122,15", help="文字の箱の左上から見た数字の箱 dx0,dy0,dx1,dy1")
    p.add_argument("--from", dest="start", type=int, required=True)
    p.add_argument("--to", dest="end", type=int, required=True)
    p.add_argument("--min", type=float, default=10.0, help="変化とみなす画素数（数字の変化で 13〜130、ちらつきは 7 前後）")
    p.set_defaults(fn=cmd_panel)

    p = sub.add_parser("ringhp", help="参照のコマ無しで照準の円の半径（歩きながらでも）")
    frames_arg(p)
    p.add_argument("--at", required=True, help="照準のコマ（カンマ区切り。中央値）")
    p.add_argument("--r0", type=float, required=True, help="探す半径の下限（単位）")
    p.add_argument("--r1", type=float, required=True, help="探す半径の上限（単位）")
    p.add_argument("--skip", action="append", help="除く角度 a0:a1（度。矢印・体力バーの向き）")
    p.add_argument("--exclude", action="append", help="除く箱 x0,y0,x1,y1")
    p.add_argument("--min", type=float, default=12.0)
    p.set_defaults(fn=cmd_ringhp)

    p = sub.add_parser("hpfill", help="的の体力バーの赤の長さ（ダメージが入ったコマ）")
    frames_arg(p)
    p.add_argument("--tpl", required=True, help="コマ:x0,y0,x1,y1（名前の文字 + バッジ）")
    p.add_argument("--bar", required=True, help="テンプレートの左上から見たバーの左端・行・右端 dx0,dy,dx1")
    p.add_argument("--search", default="0,0,1108,512", help="探す範囲 x0,y0,x1,y1")
    p.add_argument("--from", dest="start", type=int, required=True)
    p.add_argument("--to", dest="end", type=int, required=True)
    p.set_defaults(fn=cmd_hpfill)

    p = sub.add_parser("bandlines", help="向きの帯の照準の向き・左右の線・奥行き（参照のコマ無し）")
    frames_arg(p)
    p.add_argument("--at", required=True, help="照準のコマ（カンマ区切り。1 コマずつ測る）")
    p.add_argument("--axis", type=float, required=True, help="帯の向きの見当（度。±8° を探す）")
    p.add_argument("--a0", type=float, default=1.5, help="向きを探すときに使う奥行きの下限（単位。体・体力バーを避ける）")
    p.add_argument("--a1", type=float, default=4.8, help="同じく上限（先の三日月を避ける）")
    p.add_argument("--half", type=float, default=2.6, help="横の位置を探す幅（単位）")
    p.add_argument("--exclude", action="append", help="除く箱 x0,y0,x1,y1（取り消しの × など）")
    p.set_defaults(fn=cmd_bandlines)

    p = sub.add_parser("barground", help="的の体力バーを追って地面の位置（術者から）と 1 コマの動き")
    frames_arg(p)
    p.add_argument("--tpl", required=True, help="コマ:x0,y0,x1,y1（名前 + バッジ + バーの箱）")
    p.add_argument("--badge", required=True, help="箱の左上から見たバッジの中心 dx,dy")
    p.add_argument("--start-at", dest="start_at", help="--from のコマでの箱の左上 u,v（無ければ --tpl の箱）")
    p.add_argument("--from", dest="start", type=int, required=True)
    p.add_argument("--to", dest="end", type=int, required=True, help="--from より小さければ逆向きに追う")
    p.add_argument("--height", type=float, default=122.0, help="バッジの中心の地面からの高さ（ヒーロー px）")
    p.add_argument("--dx", type=float, default=52.0, help="足元がバッジの中心から右へずれる量（ヒーロー px）")
    p.add_argument("--search", type=int, default=45, help="前のコマの位置から探す幅（px）")
    p.set_defaults(fn=cmd_barground)

    p = sub.add_parser("wipe", help="バフのアイコンの時計回りの減り方から長さ（1 周の秒数）")
    frames_arg(p)
    p.add_argument("--x", type=int, required=True, help="アイコンの箱の左")
    p.add_argument("--y", type=int, required=True, help="アイコンの箱の上")
    p.add_argument("--size", type=int, default=27, help="箱の一辺（px）")
    p.add_argument("--from", dest="start", type=int, required=True)
    p.add_argument("--to", dest="end", type=int, required=True)
    p.add_argument("--sector", type=float, default=10.0, help="扇の角度（度）")
    p.add_argument("--min", type=float, default=25.0, help="暗くなったとみなす明るさの差")
    p.set_defaults(fn=cmd_wipe)

    args = ap.parse_args(argv)
    args.fn(args)


if __name__ == "__main__":
    main()
