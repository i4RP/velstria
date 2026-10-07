#!/usr/bin/env python3
"""Effekseer 用の共通テクスチャ（アルファ付き PNG）を生成する。外部ライブラリ不要。

RGB は白、形はアルファで持つ（加算合成でも黒い四角が出ない。色は効果側の頂点色で付ける）。
出力: Effects/Effekseer/Texture/Fx_*.png
usage: python3 tools/effekseer/textures.py
"""
import math
import os
import random
import struct
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "Effects", "Effekseer", "Texture")


def write_png(path, w, h, alpha):
    """alpha: h 行 × w 列の 0..1。RGB は白。"""
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        row = alpha[y]
        for x in range(w):
            a = max(0.0, min(1.0, row[x]))
            raw += bytes((255, 255, 255, int(a * 255 + 0.5)))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def grid(w, h, fn):
    return [[fn((x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1) for x in range(w)] for y in range(h)]


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# --- 形 -------------------------------------------------------------------------------

def glow(u, v):  # やわらかい光の玉
    r = math.hypot(u, v)
    return math.exp(-r * r * 5.0) * (1 - smooth(0.85, 1.0, r))


def core(u, v):  # 芯の強い光（中心が白く、すそが長い）
    r = math.hypot(u, v)
    return (math.exp(-r * r * 22.0) * 1.0 + math.exp(-r * r * 4.5) * 0.45) * (1 - smooth(0.8, 1.0, r))


def ring(u, v):  # 細い輪（衝撃波・魔法陣の外周）
    r = math.hypot(u, v)
    return smooth(0.80, 0.90, r) * (1 - smooth(0.93, 0.99, r)) + 0.35 * math.exp(-((r - 0.9) ** 2) * 90) * (1 - smooth(0.97, 1.0, r))


def ring_soft(u, v):  # 内側へ尾を引く輪（広がる衝撃波）
    r = math.hypot(u, v)
    return (smooth(0.55, 0.93, r) ** 2) * (1 - smooth(0.93, 1.0, r))


def star(u, v):  # 4 方向へ伸びる光（フレア）
    r = math.hypot(u, v)
    h = math.exp(-abs(v) * 28) * (1 - smooth(0.0, 1.0, abs(u)))
    vv = math.exp(-abs(u) * 28) * (1 - smooth(0.0, 1.0, abs(v)))
    return min(1.0, h + vv + math.exp(-r * r * 14) * 0.9)


def streak(u, v):  # 横に長い光の筋（左→右へ細く）
    x = (u + 1) / 2
    body = math.exp(-(v * v) * 38 * (0.35 + 0.65 * x))
    return body * smooth(0.0, 0.12, x) * (0.25 + 0.75 * x ** 1.3) * (1 - smooth(0.92, 1.0, x))


def arrow(u, v):  # 矢じり形（右向き）
    x = (u + 1) / 2
    half = 0.5 * (1 - x) if x > 0.45 else 0.08
    inside = abs(v) < (half + 0.04)
    edge = 1 - smooth(half - 0.02, half + 0.1, abs(v))
    shaft = math.exp(-(v * v) * 80) * smooth(0.0, 0.5, x)
    head = edge * smooth(0.4, 0.5, x) * (1 - smooth(0.95, 1.0, x))
    return min(1.0, max(shaft * (1 - smooth(0.85, 1.0, x)), head if inside else 0.0))


def crescent(u, v):  # 三日月の斬撃（右向きに開く）
    r1 = math.hypot(u + 0.25, v)
    r2 = math.hypot(u + 0.62, v)
    body = smooth(0.55, 0.9, r1) * (1 - smooth(0.9, 1.02, r1))
    cut = smooth(0.78, 1.0, r2)
    tip = 1 - smooth(0.0, 1.0, abs(v)) ** 3
    return min(1.0, body * cut * (0.4 + 0.6 * tip) * 1.6)


def diamond(u, v):  # 菱形の破片
    d = abs(u) * 1.0 + abs(v) * 2.4
    return smooth(1.0, 0.55, d) ** 0.9


def smoke(u, v):  # もやっとした煙・塵（ノイズ入り）
    r = math.hypot(u, v)
    n = (math.sin(u * 7.1 + v * 3.3) + math.sin(u * -5.3 + v * 9.7) + math.sin(u * 13.7 - v * 11.1)) / 3
    return max(0.0, (1 - smooth(0.25, 0.95, r)) * (0.65 + 0.35 * n))


def rune(u, v):  # 魔法陣: 外周 2 本の輪 + 目盛り + 内側の多角形
    r = math.hypot(u, v)
    a = math.atan2(v, u)
    out = 0.0
    out += math.exp(-((r - 0.96) ** 2) * 1400)
    out += 0.8 * math.exp(-((r - 0.86) ** 2) * 1800)
    out += 0.5 * math.exp(-((r - 0.55) ** 2) * 1800)
    # 目盛り（外周と第 2 の輪の間）
    tick = (1 - smooth(0.0, 0.07, abs(((a * 24 / (2 * math.pi)) % 1.0) - 0.5) - 0.38)) if False else 0.0
    ang = (a / (2 * math.pi)) % 1.0
    t = abs(((ang * 36) % 1.0) - 0.5)
    tick = (1 - smooth(0.0, 0.12, t)) * smooth(0.87, 0.89, r) * (1 - smooth(0.93, 0.95, r))
    out += 0.7 * tick
    # 三角形 2 枚（六芒星）
    for k in (0, 1):
        s = 0.0
        for i in range(3):
            th = a - (i * 2 * math.pi / 3 + k * math.pi / 3 + math.pi / 6)
            d = abs(r * math.cos(th) - 0.5 * 0.56)  # 正三角形の一辺までの距離（内接円半径 0.28 の近似）
            s = max(s, math.exp(-d * d * 1600) if r < 0.6 else 0.0)
        out += 0.6 * s
    out += 0.18 * (1 - smooth(0.0, 0.5, r))
    return min(1.0, out) * (1 - smooth(0.985, 1.0, r))


def wheel(u, v):  # 光輪（二重の輪 + 切れ込み）
    r = math.hypot(u, v)
    a = math.atan2(v, u)
    body = smooth(0.55, 0.62, r) * (1 - smooth(0.9, 0.97, r))
    notch = 1.0 - 0.85 * (1 - smooth(0.0, 0.2, abs(math.sin(a * 4)) - 0.75)) * smooth(0.66, 0.7, r) * (1 - smooth(0.82, 0.86, r))
    edge = math.exp(-((r - 0.93) ** 2) * 600) * 0.9
    inner = math.exp(-((r - 0.58) ** 2) * 900) * 0.8
    return min(1.0, body * 0.55 * notch + edge + inner + 0.1 * math.exp(-r * r * 3))


def spark_lines(u, v):  # 放射状の細い線（ヒットの飛び散り）
    r = math.hypot(u, v)
    a = math.atan2(v, u)
    s = abs(math.sin(a * 6))
    return (s ** 28) * smooth(0.12, 0.3, r) * (1 - smooth(0.7, 1.0, r)) + math.exp(-r * r * 30) * 0.8


def hex_shield(u, v):  # 六角の殻（障壁）
    r = math.hypot(u, v)
    a = math.atan2(v, u)
    k = math.cos(math.pi / 6) / math.cos(((a + math.pi / 6) % (math.pi / 3)) - math.pi / 6)
    d = abs(r - 0.8 * k)
    return math.exp(-d * d * 500) * (1 - smooth(0.9, 1.0, r)) + 0.12 * smooth(0.2, 0.8, r) * (1 - smooth(0.8, 0.95, r))


def petal(u, v):  # 花びら（先がとがった涙形。右向き）
    x = (u + 1) / 2
    w = 0.42 * math.sin(math.pi * min(1.0, x * 1.05)) ** 0.9 * (1 - 0.25 * x)
    return (1 - smooth(w - 0.06, w + 0.02, abs(v))) * smooth(0.0, 0.08, x) * (1 - smooth(0.96, 1.0, x)) * (0.75 + 0.25 * (1 - abs(v) / max(w, 0.05)))


def butterfly(u, v):  # 蝶（左右 2 枚の羽 + 細い胴）
    x = abs(u)
    up = math.hypot(x - 0.42, v + 0.30) < 0.34 * (1 + 0.15 * math.cos(math.atan2(v + 0.3, x - 0.42) * 2))
    lo = math.hypot(x - 0.32, v - 0.30) < 0.24
    wing = 0.0
    if up: wing = 0.85 - 0.5 * math.hypot(x - 0.42, v + 0.30) / 0.34
    if lo: wing = max(wing, 0.8 - 0.5 * math.hypot(x - 0.32, v - 0.30) / 0.24)
    body = math.exp(-(u * u) * 500) * (1 - smooth(0.55, 0.62, abs(v)))
    edge = 0.0
    return min(1.0, max(wing, 0.0) * smooth(0.04, 0.12, x) + body * 0.9 + edge)


def bolt(u, v):  # 稲妻（縦のぎざぎざ。上から下）
    y = (v + 1) / 2
    cx = 0.25 * math.sin(y * 9.0) + 0.12 * math.sin(y * 23.0 + 1.0)
    d = abs(u - cx)
    core = math.exp(-d * d * 900) + 0.35 * math.exp(-d * d * 60)
    return min(1.0, core) * smooth(0.0, 0.06, y) * (1 - smooth(0.94, 1.0, y)) * (1 - smooth(0.9, 1.0, abs(u)))


def crack(u, v):  # 地面の亀裂（中心から放射状に枝分かれ）
    r = math.hypot(u, v)
    a = math.atan2(v, u)
    out = 0.0
    for k in range(7):
        base = k * 2 * math.pi / 7 + 0.4
        wob = 0.12 * math.sin(r * 14 + k * 3.1) + 0.06 * math.sin(r * 31 + k)
        d = math.sin(a - base - wob) * r
        along = math.cos(a - base - wob)
        if along > 0:
            out = max(out, math.exp(-d * d * 1400) * (1 - smooth(0.3, 0.97, r)) * (0.6 + 0.4 * (1 - r)))
    return min(1.0, out + 0.5 * math.exp(-r * r * 40)) * (1 - smooth(0.96, 1.0, r))


def blob(u, v):  # 粘液のかたまり（歪んだ円 + ハイライト）
    r = math.hypot(u, v)
    a = math.atan2(v, u)
    R = 0.72 + 0.12 * math.sin(a * 3 + 0.7) + 0.07 * math.sin(a * 5 + 2.0)
    body = 1 - smooth(R - 0.08, R, r)
    hl = math.exp(-((u + 0.25) ** 2 + (v + 0.28) ** 2) * 28) * 0.5
    return min(1.0, body * (0.7 + 0.3 * (1 - r)) + hl * body)


def chain(u, v):  # 鎖（横向きに連なる輪）
    x = (u + 1) / 2
    k = (x * 4) % 1.0
    cx = (k - 0.5) * 0.5
    ring_ = math.exp(-((math.hypot(cx * 1.6, v * 2.2) - 0.42) ** 2) * 160)
    return min(1.0, ring_) * smooth(0.0, 0.05, x) * (1 - smooth(0.95, 1.0, x))


def shard(u, v):  # 細長い破片（上下がとがる菱形・縦長）
    d = abs(u) * 3.0 + abs(v) * 0.9
    return smooth(1.0, 0.7, d) * (0.6 + 0.4 * (1 - abs(u)))


def spiral(u, v):  # 渦（巻く腕 3 本）
    r = math.hypot(u, v)
    a = math.atan2(v, u)
    s = math.sin(a * 3 - r * 9)
    return max(0.0, s) ** 2 * smooth(0.05, 0.25, r) * (1 - smooth(0.7, 1.0, r)) * 0.95 + 0.1 * math.exp(-r * r * 20)


def beam(u, v):  # 幅のある光線（左右へ長い・上下はなめらか）
    x = (u + 1) / 2
    return math.exp(-v * v * 9.0) * smooth(0.0, 0.08, x) * (1 - smooth(0.92, 1.0, x)) * (0.55 + 0.45 * math.exp(-v * v * 40))


TEXTURES = {
    "Fx_Glow": (128, 128, glow),
    "Fx_Core": (128, 128, core),
    "Fx_Ring": (256, 256, ring),
    "Fx_RingSoft": (256, 256, ring_soft),
    "Fx_Star": (128, 128, star),
    "Fx_Streak": (256, 64, streak),
    "Fx_Arrow": (256, 64, arrow),
    "Fx_Crescent": (256, 256, crescent),
    "Fx_Diamond": (64, 64, diamond),
    "Fx_Smoke": (128, 128, smoke),
    "Fx_Rune": (512, 512, rune),
    "Fx_Wheel": (256, 256, wheel),
    "Fx_Sparks": (128, 128, spark_lines),
    "Fx_Hex": (256, 256, hex_shield),
    "Fx_Petal": (128, 64, petal),
    "Fx_Butterfly": (128, 128, butterfly),
    "Fx_Bolt": (64, 256, bolt),
    "Fx_Crack": (256, 256, crack),
    "Fx_Blob": (128, 128, blob),
    "Fx_Chain": (256, 64, chain),
    "Fx_Shard": (64, 128, shard),
    "Fx_Spiral": (256, 256, spiral),
    "Fx_Beam": (256, 64, beam),
}


def main():
    for name, (w, h, fn) in TEXTURES.items():
        write_png(os.path.join(OUT, name + ".png"), w, h, grid(w, h, fn))
        print("wrote", name)


if __name__ == "__main__":
    main()
