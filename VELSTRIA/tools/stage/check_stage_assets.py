#!/usr/bin/env python3
"""ステージ素材（App/Resources/Stage/）の検証。仕様は docs/STAGE.md 3 章。stage_bake.py とは独立に書いてある
（表も自前で持つ）ので、焼く側の間違いをそのまま見逃さない。

  python3 tools/stage/check_stage_assets.py          # 失敗があれば一覧を出して終了コード 1

確かめること:
- StageTile_<id>.jpg: 1024×1024・JPEG 品質 90（量子化表）・4 辺シームレス
  （向かい合う端の行/列の平均絶対差 ÷ 内側の隣り合う行/列の平均絶対差 < 1.5）
- StageDecal_rune.jpg: 1024×1024、円が正方形に内接（前景の外接矩形が辺の 97% 以上・中心がずれていない）
- StagePropsAtlas.jpg: 2048×1024、各セルの周囲 8 px が端の画素の引き伸ばし
- StageProps.bin: マジック・版・JSON・16 バイト境界・各ブロックがファイル内で 4 バイト境界・重ならない、
  添字 < 頂点数、法線が単位長（±1e-2）、UV がそのセルの内側（496 px 四方）、boundsMin/Max = 頂点の範囲、
  最低点 y = 0（±1e-3）、足跡の中心が原点（< 1e-2）、三角形数が表の ±15%、実寸が ±2%、
  巻き順（(b−a)×(c−a) と頂点の法線が同じ向き）が 95% 超、水平で最も長い向きが X。

numpy と Pillow が要る。無ければ build/stage/venv の Python で自分を起動し直す。
"""
import json
import os
import struct
import sys
from io import BytesIO
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # VELSTRIA/
VENV = ROOT / "build" / "stage" / "venv"

try:
    import numpy as np
    from PIL import Image
except ImportError:
    py = VENV / "bin" / "python"
    if py.exists() and Path(sys.prefix).resolve() != VENV.resolve() and not os.environ.get("STAGE_CHECK_REEXEC"):
        os.environ["STAGE_CHECK_REEXEC"] = "1"
        os.execv(str(py), [str(py), str(Path(__file__).resolve()), *sys.argv[1:]])
    sys.exit("numpy / Pillow が必要（build/stage/venv。作り方は tools/stage/stage_bake.py の VENV_HELP）")

STAGE = ROOT / "App" / "Resources" / "Stage"
TILES = ["grass", "grass_dark", "dirt", "paving", "rock", "moss", "riverbed"]
# docs/STAGE.md 3.3 の表（並び = アトラスのセル順）。(id, 三角形, 寸法の種類, メートル)
PROPS = [
    ("cliff_rock_a", 1000, "width", 4.0),
    ("cliff_rock_b", 900, "height", 3.0),
    ("boulder", 500, "footprint", 2.0),
    ("tree_round", 1100, "height", 4.2),
    ("tree_tall", 1050, "height", 5.0),
    ("bush", 450, "footprint", 1.6),
    ("ruin_pillar", 900, "height", 2.6),
    ("ruin_arch", 1400, "width", 4.0),
]
ATLAS_W, ATLAS_H, CELL, PAD = 2048, 1024, 512, 8
INNER = CELL - 2 * PAD

FAILURES = []


def fail(msg):
    FAILURES.append(msg)
    print(f"  FAIL {msg}")


def check(cond, msg):
    if not cond:
        fail(msg)
    return cond


def q90_tables():
    """Pillow（libjpeg）が品質 90 で書く量子化表。"""
    buf = BytesIO()
    Image.new("RGB", (16, 16)).save(buf, "JPEG", quality=90)
    return Image.open(BytesIO(buf.getvalue())).quantization


def check_jpeg(path, size, q90):
    if not check(path.exists(), f"{path.name}: missing"):
        return None
    im = Image.open(path)
    check(im.format == "JPEG", f"{path.name}: not JPEG ({im.format})")
    check(im.size == size, f"{path.name}: size {im.size} != {size}")
    check(im.mode == "RGB", f"{path.name}: mode {im.mode}")
    q = getattr(im, "quantization", None) or {}
    check(q and all(list(q[k]) == list(q90[k]) for k in q90 if k in q), f"{path.name}: quantization is not quality 90")
    return np.asarray(im.convert("RGB")).astype(np.float64)


def seam_ratio(a, axis):
    """axis=1: 左右の端（列 0 と列 n−1）の差 ÷ 内側の隣り合う列の差の平均。axis=0 は上下。"""
    if axis == 0:
        a = a.transpose(1, 0, 2)
    seam = np.abs(a[:, 0] - a[:, -1]).mean()
    interior = np.abs(np.diff(a, axis=1)).mean()
    return seam / max(interior, 1e-9)


def check_tiles(q90):
    print("tiles")
    for tid in TILES:
        a = check_jpeg(STAGE / f"StageTile_{tid}.jpg", (1024, 1024), q90)
        if a is None:
            continue
        rx, ry = seam_ratio(a, 1), seam_ratio(a, 0)
        print(f"  {tid:11s} seam ratio x {rx:.3f}  y {ry:.3f}")
        check(rx < 1.5 and ry < 1.5, f"StageTile_{tid}.jpg: not seamless (ratio x {rx:.2f}, y {ry:.2f})")


def check_decal(q90):
    print("decal")
    a = check_jpeg(STAGE / "StageDecal_rune.jpg", (1024, 1024), q90)
    if a is None:
        return
    n = a.shape[0]
    corners = np.concatenate([a[:12, :12].reshape(-1, 3), a[:12, -12:].reshape(-1, 3),
                              a[-12:, :12].reshape(-1, 3), a[-12:, -12:].reshape(-1, 3)])
    bg = np.median(corners, axis=0)
    fg = np.abs(a - bg).max(axis=2) > 24
    rows = np.where(fg.sum(axis=1) >= 4)[0]
    cols = np.where(fg.sum(axis=0) >= 4)[0]
    if not check(len(rows) and len(cols), "StageDecal_rune.jpg: no foreground"):
        return
    w, h = cols[-1] - cols[0] + 1, rows[-1] - rows[0] + 1
    cx, cy = (cols[0] + cols[-1]) / 2, (rows[0] + rows[-1]) / 2
    print(f"  foreground {w}x{h} centre ({cx:.1f}, {cy:.1f}), background {bg.round().tolist()}")
    check(max(w, h) >= 0.97 * n, f"StageDecal_rune.jpg: circle spans only {max(w, h)} px")
    check(abs(cx - (n - 1) / 2) < 0.02 * n and abs(cy - (n - 1) / 2) < 0.02 * n,
          f"StageDecal_rune.jpg: circle not centred ({cx:.1f}, {cy:.1f})")


def check_atlas(q90):
    print("atlas")
    a = check_jpeg(STAGE / "StagePropsAtlas.jpg", (ATLAS_W, ATLAS_H), q90)
    if a is None:
        return
    worst = 0.0
    for i in range(8):
        col, row = i % 4, i // 4
        c = a[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL]
        inner = c[PAD:PAD + INNER, PAD:PAD + INNER]
        # 余白の各列/行 ≈ 内側の端の列/行（JPEG の誤差は許す）
        d = max(np.abs(c[PAD:PAD + INNER, :PAD] - inner[:, :1]).mean(),
                np.abs(c[PAD:PAD + INNER, PAD + INNER:] - inner[:, -1:]).mean(),
                np.abs(c[:PAD, PAD:PAD + INNER] - inner[:1, :]).mean(),
                np.abs(c[PAD + INNER:, PAD:PAD + INNER] - inner[-1:, :]).mean())
        worst = max(worst, d)
        check(d < 8.0, f"StagePropsAtlas.jpg: cell {i} padding is not edge-extended (mean diff {d:.1f})")
    print(f"  padding vs edge pixels: worst mean abs diff {worst:.2f}")


def check_props():
    print("props")
    path = STAGE / "StageProps.bin"
    if not check(path.exists(), "StageProps.bin: missing"):
        return
    blob = path.read_bytes()
    size = len(blob)
    if not check(blob[:4] == b"VSP1", f"StageProps.bin: magic {blob[:4]!r}"):
        return
    version, jlen = struct.unpack_from("<II", blob, 4)
    check(version == 1, f"StageProps.bin: version {version}")
    if not check(12 + jlen <= size, "StageProps.bin: JSON runs past end of file"):
        return
    header = json.loads(blob[12:12 + jlen].decode("utf-8"))
    base = (12 + jlen + 15) // 16 * 16
    check(all(b == 0 for b in blob[12 + jlen:base]), "StageProps.bin: padding after JSON is not zero")
    check(header.get("atlas") == {"width": ATLAS_W, "height": ATLAS_H}, f"StageProps.bin: atlas {header.get('atlas')}")
    recs = header.get("props", [])
    check([r.get("id") for r in recs] == [p[0] for p in PROPS], f"StageProps.bin: prop ids/order {[r.get('id') for r in recs]}")
    ranges = []
    print(f"  file {size} bytes, JSON {jlen} bytes, data at {base}")
    print(f"  {'id':13s} {'tris':>5s} {'target':>6s} {'verts':>6s}  size x/y/z (m)          wind   check")
    for k, (pid, target, kind, meters) in enumerate(PROPS):
        r = next((r for r in recs if r.get("id") == pid), None)
        if not check(r is not None, f"{pid}: missing record"):
            continue
        nv, ni, vo, io = r["vertexCount"], r["indexCount"], r["vertexOffset"], r["indexOffset"]
        ok = True
        ok &= check(nv > 0 and ni > 0 and ni % 3 == 0, f"{pid}: counts {nv}/{ni}")
        ok &= check(vo % 4 == 0 and io % 4 == 0, f"{pid}: offsets not 4-byte aligned ({vo}, {io})")
        ok &= check(0 <= vo and base + vo + nv * 32 <= size, f"{pid}: vertex block outside file")
        ok &= check(0 <= io and base + io + ni * 4 <= size, f"{pid}: index block outside file")
        if "tris" in r:
            check(r["tris"] * 3 == ni, f"{pid}: tris {r['tris']} != indexCount/3")
        if not ok:
            continue
        ranges += [(base + vo, base + vo + nv * 32, f"{pid} vertices"), (base + io, base + io + ni * 4, f"{pid} indices")]
        v = np.frombuffer(blob, "<f4", nv * 8, base + vo).reshape(nv, 8).astype(np.float64)
        idx = np.frombuffer(blob, "<u4", ni, base + io).astype(np.int64)
        if not check(np.isfinite(v).all(), f"{pid}: non-finite vertex data"):
            continue
        if not check(idx.max() < nv, f"{pid}: index {idx.max()} >= vertexCount {nv}"):
            continue
        pos, nrm, uv = v[:, 0:3], v[:, 3:6], v[:, 6:8]
        nl = np.linalg.norm(nrm, axis=1)
        check(np.abs(nl - 1).max() <= 1e-2, f"{pid}: normal length off by {np.abs(nl - 1).max():.4f}")
        col, row = k % 4, k // 4
        x0, y0 = col * CELL + PAD, row * CELL + PAD
        px, py = uv[:, 0] * ATLAS_W, (1.0 - uv[:, 1]) * ATLAS_H     # 画像の画素（左上原点）
        eps = 1e-3
        check(px.min() >= x0 - eps and px.max() <= x0 + INNER + eps and py.min() >= y0 - eps and py.max() <= y0 + INNER + eps,
              f"{pid}: UV outside cell {k} inner area (x {px.min():.2f}..{px.max():.2f} of {x0}..{x0 + INNER}, "
              f"y {py.min():.2f}..{py.max():.2f} of {y0}..{y0 + INNER})")
        lo, hi = pos.min(axis=0), pos.max(axis=0)
        check(np.abs(lo - np.array(r["boundsMin"])).max() < 1e-4 and np.abs(hi - np.array(r["boundsMax"])).max() < 1e-4,
              f"{pid}: bounds {r['boundsMin']}..{r['boundsMax']} != data {lo.tolist()}..{hi.tolist()}")
        check(abs(lo[1]) <= 1e-3, f"{pid}: min y {lo[1]:.5f} != 0")
        check(abs((lo[0] + hi[0]) / 2) < 1e-2 and abs((lo[2] + hi[2]) / 2) < 1e-2,
              f"{pid}: footprint centre ({(lo[0] + hi[0]) / 2:.4f}, {(lo[2] + hi[2]) / 2:.4f})")
        ext = hi - lo
        tris = ni // 3
        check(abs(tris - target) <= 0.15 * target, f"{pid}: {tris} tris, target {target} (±15%)")
        measured = {"width": ext[0], "height": ext[1], "footprint": max(ext[0], ext[2])}[kind]
        check(abs(measured - meters) <= 0.02 * meters, f"{pid}: {kind} {measured:.3f} m, expected {meters} m (±2%)")
        check(ext[0] >= ext[2] - 1e-6, f"{pid}: longest horizontal extent is not X ({ext[0]:.3f} < {ext[2]:.3f})")
        t = idx.reshape(-1, 3)
        a, b, c = pos[t[:, 0]], pos[t[:, 1]], pos[t[:, 2]]
        fn = np.cross(b - a, c - a)
        area = np.linalg.norm(fn, axis=1) / 2
        live = area > 1e-12
        vn = nrm[t[:, 0]] + nrm[t[:, 1]] + nrm[t[:, 2]]
        agree = float(((fn * vn).sum(axis=1) > 0)[live].mean())
        check(agree > 0.95, f"{pid}: winding agrees with normals for {agree:.1%} of triangles")
        check((~live).mean() < 0.01, f"{pid}: {(~live).sum()} degenerate triangles")
        print(f"  {pid:13s} {tris:5d} {target:6d} {nv:6d}  {ext[0]:5.2f} {ext[1]:5.2f} {ext[2]:5.2f}"
              f"            {agree:.3f}")
    ranges.sort()
    for (s0, e0, n0), (s1, e1, n1) in zip(ranges, ranges[1:]):
        check(e0 <= s1, f"StageProps.bin: {n0} overlaps {n1}")


def main():
    q90 = q90_tables()
    check_tiles(q90)
    check_decal(q90)
    check_atlas(q90)
    check_props()
    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s)")
        return 1
    print("\nOK: all stage asset checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
