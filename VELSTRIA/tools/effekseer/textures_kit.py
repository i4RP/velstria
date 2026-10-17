#!/usr/bin/env python3
"""キットのヒーローの段に重ねる効果（Effects/Effekseer/Kit/）が使うテクスチャ。numpy・Pillow・scipy が要る。

- 手続きの画（決まった乱数）: Fx_FlameRing（外向きの炎の舌が並ぶ輪。色を焼き込んだ画: 内縁の黄白 → 橙 → 赤の先）・
  Fx_FlameRingCore（同じ舌の根元のまばらな芯。白 + アルファ。加算）・Fx_SoftDisc（平らに満ちた円）・Fx_ThinRing（細い線の輪）・
  Fx_Burst（多数の棘の光芒）・Fx_Spike（立ちのぼる光の棘）
- Blender の画（tools/vfx_assets が作った App/Resources/FX/Textures の白 + アルファ）の写し: Fx_CrackRadial・Fx_Scorch・Fx_Star4
出力: Effects/Effekseer/Texture/Fx_*.png
usage: python3 tools/effekseer/textures_kit.py
"""
import os
import shutil

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "Effects", "Effekseer", "Texture")
BLENDER = os.path.join(ROOT, "App", "Resources", "FX", "Textures")


def save(name, rgba):
    os.makedirs(OUT, exist_ok=True)
    img = Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    img.save(os.path.join(OUT, name + ".png"), optimize=True)
    print(name, img.size)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def polar(n):
    y, x = np.mgrid[0:n, 0:n]
    u = (x + 0.5) / n * 2 - 1
    v = (y + 0.5) / n * 2 - 1
    return np.sqrt(u * u + v * v), np.arctan2(v, u)


def value_noise(rng, shape, cells):
    """滑らかな値のノイズ（格子 cells の双三次補間）。"""
    g = rng.random((cells + 3, cells + 3))
    h, w = shape
    ys = np.linspace(0, cells, h, endpoint=False) + 1
    xs = np.linspace(0, cells, w, endpoint=False) + 1
    yi, xi = np.floor(ys).astype(int), np.floor(xs).astype(int)
    fy, fx = ys - yi, xs - xi
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = g[np.ix_(yi, xi)]
    b = g[np.ix_(yi, xi + 1)]
    c = g[np.ix_(yi + 1, xi)]
    d = g[np.ix_(yi + 1, xi + 1)]
    fx = fx[None, :]
    fy = fy[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def polar_noise(rng, r, th, cells_a, cells_r):
    """角度で繋がる値のノイズ（角度 cells_a・半径 cells_r の格子を双三次でなめらかに）。"""
    from scipy.ndimage import map_coordinates
    g = rng.random((cells_r + 4, cells_a))
    g = np.concatenate([g, g[:, :4]], axis=1)  # 角度の継ぎ目を繋ぐ
    ai = (th + np.pi) / (2 * np.pi) * cells_a
    ri = np.clip(r, 0, 1) * cells_r + 1
    return map_coordinates(g, [ri, ai], order=3, mode="nearest")


def tongues(n=1024, seed=34, inner=0.70, valley=0.86, big=(26, 0.95, 1.0), small=(44, 0.90, 0.94)):
    """外向きの炎の舌の境界 b(θ)（大きい舌と、間の小さい舌）と、縦（半径の向き）の炎の筋のノイズ。"""
    rng = np.random.default_rng(seed)
    r, th = polar(n)
    b = np.full(r.shape, valley)
    for count, lo, hi in (big, small):
        slot = 2 * np.pi / count
        phase = rng.uniform(-0.3, 0.3, count) * slot
        tips = rng.uniform(lo, hi, count)
        widths = rng.uniform(0.38, 0.62, count)
        lean = rng.uniform(-0.35, 0.35, count)  # 舌の先の傾き（炎がなびく）
        for k in range(count):
            c = -np.pi + (k + 0.5) * slot + phase[k]
            d = np.angle(np.exp(1j * (th - c - lean[k] * slot * np.clip((r - valley) / 0.12, 0, 1))))
            half = widths[k] * slot
            peak = np.clip(1 - np.abs(d) / half, 0, 1) ** 1.5
            b = np.maximum(b, valley + (tips[k] - valley) * peak)
    b = b + (polar_noise(rng, r, th, 96, 4) - 0.5) * 0.018
    streak = polar_noise(rng, r, th, 160, 10)   # 半径の向きに伸びた炎の筋
    blot = polar_noise(rng, r, th, 36, 3)       # 大きなむら（明るい舌・暗い舌）
    edge = inner + (polar_noise(rng, r, th, 70, 2) - 0.5) * 0.05
    return r, th, b, streak, blot, edge


def flame_ring():
    r, th, b, streak, blot, edge = tongues()
    t = np.clip((r - edge) / np.maximum(b - edge, 1e-3), 0, 1)
    a = smooth(edge - 0.035, edge + 0.02, r) * (1 - smooth(b - 0.02, b + 0.004, r))
    a *= np.clip(0.55 + 0.6 * streak, 0, 1) * (0.8 + 0.2 * blot)
    # 輪の内の橙の円（うっすら）
    a = np.maximum(a, 0.2 * smooth(edge - 0.25, edge - 0.03, r) * (r < edge))
    stops = [(0.0, (0.99, 0.94, 0.55)), (0.16, (0.98, 0.77, 0.40)), (0.38, (0.95, 0.55, 0.33)),
             (0.68, (0.91, 0.36, 0.26)), (1.0, (0.74, 0.27, 0.22))]
    rgb = np.zeros(r.shape + (3,))
    for c in range(3):
        rgb[..., c] = np.interp(t, [s[0] for s in stops], [s[1][c] for s in stops])
    # 明るい筋（舌の根元〜半ばの黄のハイライト）
    hi = np.clip((streak - 0.55) * 2.2, 0, 1) * (1 - smooth(0.25, 0.65, t)) * (0.6 + 0.4 * blot)
    rgb = rgb * (1 - hi[..., None]) + np.array([0.99, 0.95, 0.57]) * hi[..., None]
    rgb[r < edge] = (0.91, 0.47, 0.28)
    rgb *= (0.88 + 0.22 * streak)[..., None]
    save("Fx_FlameRing", np.dstack([np.clip(rgb, 0, 1), a]))


def flame_ring_core():
    r, th, b, streak, blot, edge = tongues()
    # 舌の根元のまばらな明るい芯（加算。輪 1 周の白い線にならないよう、むらと筋で欠く）
    mid = edge + (b - edge) * 0.5
    a = smooth(edge - 0.02, edge + 0.015, r) * (1 - smooth(mid - 0.05, mid + 0.01, r))
    a *= np.clip((streak - 0.35) * 1.8, 0, 1) * np.clip((blot - 0.2) * 1.6, 0, 1)
    save("Fx_FlameRingCore", np.dstack([np.ones(r.shape + (3,)), a]))


def soft_disc(n=256):
    """平らに満ちた柔らかい円（中は一様、縁 45% でなめらかに消える）。"""
    r, _ = polar(n)
    a = 1 - smooth(0.55, 1.0, r)
    save("Fx_SoftDisc", np.dstack([np.ones(r.shape + (3,)), a]))


def thin_ring(n=1024):
    """細い輪（半径 0.95・幅 0.8%。外の細い線）。"""
    r, _ = polar(n)
    a = np.exp(-((r - 0.95) / 0.008) ** 2) * (1 - smooth(0.985, 1.0, r))
    save("Fx_ThinRing", np.dstack([np.ones(r.shape + (3,)), a]))


def burst(n=512, seed=7):
    """多数の棘の光芒（中心の柔らかい光 + 長短 2 組の棘）。"""
    rng = np.random.default_rng(seed)
    r, th = polar(n)
    a = np.exp(-(r / 0.14) ** 2)
    for count, lo, hi, w in ((14, 0.62, 1.0, 0.075), (18, 0.3, 0.6, 0.05)):
        ang = np.sort(rng.uniform(-np.pi, np.pi, count))
        for k in range(count):
            d = np.angle(np.exp(1j * (th - ang[k])))
            length = rng.uniform(lo, hi) * 0.98
            width = w * rng.uniform(0.7, 1.3) * (1 - np.clip(r / length, 0, 1))
            spike = np.clip(1 - np.abs(d) * np.maximum(r, 0.02) / np.maximum(width * 0.5, 1e-4), 0, 1) * (r < length)
            a = np.maximum(a, spike * (1 - smooth(length * 0.7, length, r)) * 0.95)
    a *= 1 - smooth(0.96, 1.0, r)
    save("Fx_Burst", np.dstack([np.ones(r.shape + (3,)), a]))


def spike(w=64, h=256):
    """立ちのぼる光の棘（下が太く上へ細る。芯が明るい）。画像の上 = 先。"""
    y, x = np.mgrid[0:h, 0:w]
    u = (x + 0.5) / w * 2 - 1
    t = 1 - (y + 0.5) / h  # 0 = 下、1 = 上
    width = 0.95 * (1 - t) ** 0.8 + 0.04
    core = np.exp(-(u / (width * 0.35)) ** 2)
    glow = np.exp(-(u / width) ** 2) * 0.45
    a = (core + glow) * smooth(0.0, 0.08, t) * (1 - smooth(0.85, 1.0, t))
    save("Fx_Spike", np.dstack([np.ones((h, w, 3)), np.clip(a, 0, 1)]))


def copy_blender(src, name):
    shutil.copyfile(os.path.join(BLENDER, src), os.path.join(OUT, name + ".png"))
    print(name, "<-", src)


def main():
    flame_ring()
    flame_ring_core()
    soft_disc()
    thin_ring()
    burst()
    spike()
    copy_blender("fx_crack_radial.png", "Fx_CrackRadial")
    copy_blender("fx_scorch.png", "Fx_Scorch")
    copy_blender("fx_star4.png", "Fx_Star4")


if __name__ == "__main__":
    main()
