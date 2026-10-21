#!/usr/bin/env python3
"""Blender で描いたコマ（fx_render.py の 16 bit PNG）を、実行時に読む画像へ詰める。

- コマ送り（sheet）: cols × rows の格子に並べた 1 枚（左上から行優先）。各コマの外周 2 px は完全に透明。
- 1 枚の模様（image）・継ぎ目なしの模様（tile）: そのまま 1 枚。
色の形式（JOBS の color）:
  white    RGB は 255（白）、形はアルファ。色は実行時の tint で付ける（従来の tools/vfx_sprites と同じ）
  colored  RGB = 色（アルファで割った値）、アルファ = 形。実行時は tint を白にして色をそのまま出す（爆炎・陰影のある煙・岩）
明るさは 1 つのシートの全コマで同じ倍率で正規化する（時間の減衰を残す）。

usage:
  python pack.py --frames "$TEMP/vfxwork/frames" [--only fireball] [--preview "$TEMP/vfxwork/preview"]
出力: App/Resources/FX/Sheets/fx_<name>.png（sheet）・App/Resources/FX/Textures/fx_<name>.png（image / tile）、
      目録 tools/vfx_assets/manifest.json（Meshes の fxm_<name>.bin も載せる）。App/Resources 以下はバンドル直下へ
      平らに入るので、ほかの画像と名前がぶつからないよう fx_ / fxm_ を付ける。
"""
import argparse
import hashlib
import json
import math
import os

import cv2
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.normpath(os.path.join(HERE, "..", "..", "App", "Resources", "FX"))
BORDER = 2

# name → 種類・格子（cols, rows）・色・明るさの扱い
#   level: "peak"（全コマの 99.95 パーセンタイル → 1）か、固定の倍率（float）
#   source: "lum"（黒地の発光 → 明るさ）か "alpha"（透過の地 → アルファ）
JOBS = {
    "fireball": dict(kind="sheet", grid=(5, 5), color="colored", source="lum", level="peak", gain=1.15),
    "smoke_hd": dict(kind="sheet", grid=(4, 4), color="colored", source="alpha", level=1.0),
    "spikes": dict(kind="sheet", grid=(4, 4), color="white", source="lum", level="peak", gain=1.1),
    "rock_tumble": dict(kind="sheet", grid=(4, 4), color="colored", source="alpha", level=1.0),
    "dust_ring": dict(kind="sheet", grid=(4, 4), color="colored", source="alpha", level=1.0),
    "crack_s": dict(kind="image", color="white", source="lum", level="peak", halo=0.22),
    "crack_radial": dict(kind="image", color="white", source="lum", level="peak", halo=0.18),
    "scorch": dict(kind="image", color="white", source="lum", level="peak"),
    "star4": dict(kind="image", color="white", source="lum", level="peak", halo=0.45),
    "swoosh": dict(kind="image", color="white", source="lum", level="peak"),
    "blade": dict(kind="image", color="white", source="lum", level="peak"),
    "moon_crest": dict(kind="image", color="white", source="lum", level="peak", halo=0.3),
    "comet": dict(kind="image", color="white", source="lum", level="peak"),
    "comet_glow": dict(kind="image", color="white", source="lum", level=1.0),
    "lava": dict(kind="tile", color="white", source="lum", level="peak"),
    "flame_noise": dict(kind="tile", color="white", source="lum", level="peak"),
}


def load(path):
    """16 bit の PNG → float32 RGBA（0〜1、cv2 は BGR(A) で読む）。"""
    img = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if img is None:
        raise SystemExit("読めない: " + path)
    img = img.astype(np.float32) / (65535.0 if img.dtype == np.uint16 else 255.0)
    if img.shape[2] == 3:
        img = np.concatenate([img, np.ones_like(img[..., :1])], axis=2)
    return img[..., [2, 1, 0, 3]]


def frame_rgba(img, job):
    """1 コマ → 直線のアルファの RGBA（float、まだ正規化前）。"""
    rgb = img[..., :3]
    if job["source"] == "lum":
        # 黒地の発光: 形 = 最も明るい色の成分（加算で足したときの明るさの上限）、色 = 発光 / 形
        a = rgb.max(axis=2)
        return rgb, a
    a = img[..., 3]
    return rgb, a


def finish(rgb, a, job, scale, size):
    a = np.clip(a * scale, 0.0, 1.0)
    if job.get("halo"):
        # 細い線の周りに柔らかい光を足す（ブルームの無い環境でも線が読める）
        k = max(3, int(size * 0.012) | 1)
        blur = cv2.GaussianBlur(a, (0, 0), sigmaX=k)
        a = np.clip(np.maximum(a, blur * job["halo"] * 2.2), 0.0, 1.0)
    if job["color"] == "white":
        out = np.zeros(a.shape + (4,), np.float32)
        out[..., :3] = 1.0
        out[..., 3] = a
        return out
    if job["source"] == "lum":
        # 発光の色をアルファで割って、直線のアルファの色にする（乗算すると元の発光に戻る）
        col = np.where(a[..., None] > 1e-4, (rgb * scale) / np.maximum(a[..., None], 1e-4), 0.0)
    else:
        col = rgb
    out = np.zeros(a.shape + (4,), np.float32)
    out[..., :3] = np.clip(col, 0.0, 1.0)
    out[..., 3] = a
    return out


def border_mask(n, edge=BORDER, soft=6):
    """コマの外周 edge px は 0、そこから soft px で 1 へ。"""
    x = np.arange(n, dtype=np.float32) + 0.5
    d = np.minimum(x, n - x)
    m = np.clip((d - edge) / soft, 0.0, 1.0)
    return np.minimum.outer(m, m)


def to8(img):
    return (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)


def save_png(path, rgba8):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(rgba8, "RGBA").save(path, optimize=True)


def preview(path, rgba, tint=(1.0, 0.78, 0.25)):
    """確認用: 草地色と暗色の上に重ねた画（加算と同じ見え方の明るさ）。リポジトリの外へ書く。"""
    h, w = rgba.shape[:2]
    out = np.zeros((h, w * 2, 3), np.float32)
    for k, bg in enumerate([(0.35, 0.42, 0.31), (0.1, 0.12, 0.14)]):
        col = rgba[..., :3] * np.array(tint if rgba[..., :3].min() > 0.99 else (1, 1, 1), np.float32)
        a = rgba[..., 3:4]
        out[:, k * w:(k + 1) * w] = np.array(bg, np.float32) * (1 - a) + col * a
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(to8(out), "RGB").save(path)


def pack(name, job, frames_dir, preview_dir):
    d = os.path.join(frames_dir, name)
    files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    imgs = [load(os.path.join(d, f)) for f in files]
    parts = [frame_rgba(i, job) for i in imgs]
    if job["level"] == "peak":
        allv = np.concatenate([a.ravel() for _, a in parts])
        peak = float(np.percentile(allv[allv > 1e-4], 99.95)) if (allv > 1e-4).any() else 1.0
        scale = job.get("gain", 1.0) / max(peak, 1e-4)
    else:
        scale = float(job["level"])
    size = imgs[0].shape[0]
    done = [finish(rgb, a, job, scale, size) for (rgb, a) in parts]
    if job["kind"] == "sheet":
        cols, rows = job["grid"]
        assert len(done) == cols * rows, "%s: コマ数 %d が格子 %dx%d と合わない" % (name, len(done), cols, rows)
        m = border_mask(size)
        sheet = np.zeros((rows * size, cols * size, 4), np.float32)
        for k, fr in enumerate(done):
            r, c = divmod(k, cols)
            fr = fr.copy()
            fr[..., 3] *= m
            sheet[r * size:(r + 1) * size, c * size:(c + 1) * size] = fr
        out8 = to8(sheet)
        # 透明な所の色は 0（ほかの道具が色を読んでも縁がにじまない）。白のシートは RGB 255 のまま
        if job["color"] == "colored":
            out8[out8[..., 3] == 0, :3] = 0
        path = os.path.join(APP, "Sheets", "fx_" + name + ".png")
        save_png(path, out8)
        info = dict(kind="sheet", file="Sheets/fx_%s.png" % name, columns=cols, rows=rows, frames=cols * rows,
                    frameSize=size, color=job["color"])
        img_for_preview = sheet
    else:
        fr = done[0]
        if job["kind"] == "image":
            fr[..., 3] *= border_mask(size, edge=1, soft=4)
        out8 = to8(fr)
        if job["color"] == "colored":
            out8[out8[..., 3] == 0, :3] = 0
        path = os.path.join(APP, "Textures", "fx_" + name + ".png")
        save_png(path, out8)
        info = dict(kind=job["kind"], file="Textures/fx_%s.png" % name, size=size, color=job["color"])
        img_for_preview = fr
    with open(path, "rb") as f:
        data = f.read()
    info["bytes"] = len(data)
    info["sha256"] = hashlib.sha256(data).hexdigest()
    if preview_dir:
        preview(os.path.join(preview_dir, name + "_preview.png"), img_for_preview)
    print("%-13s %-6s %7d bytes" % (name, info["kind"], info["bytes"]))
    return info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", required=True)
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--preview", default="")
    ap.add_argument("--manifest", default=os.path.join(HERE, "manifest.json"))
    a = ap.parse_args()
    manifest = {}
    if os.path.exists(a.manifest):
        with open(a.manifest, encoding="utf-8") as f:
            manifest = json.load(f)
    for name in (a.only or list(JOBS)):
        manifest.setdefault("images", {})[name] = pack(name, JOBS[name], a.frames, a.preview)
    meshes = os.path.join(APP, "Meshes")
    if os.path.isdir(meshes):
        mm = {}
        for f in sorted(os.listdir(meshes)):
            if f.startswith("fxm_") and f.endswith(".bin"):
                with open(os.path.join(meshes, f), "rb") as fh:
                    data = fh.read()
                n, ni = int.from_bytes(data[4:8], "little"), int.from_bytes(data[8:12], "little")
                mm[f[4:-4]] = dict(file="Meshes/" + f, vertices=n, triangles=ni // 3, bytes=len(data),
                                  sha256=hashlib.sha256(data).hexdigest())
        manifest["meshes"] = mm
    with open(a.manifest, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, sort_keys=True, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    main()
