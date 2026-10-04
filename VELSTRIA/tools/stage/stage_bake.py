#!/usr/bin/env python3
"""ステージ素材の取り込み（アプリ用に焼く）。仕様は docs/STAGE.md 3 章。

入力（git 管理外）: build/stage/art/<id>.png（stage_art.py）、build/stage/meshy/<id>/（stage_meshy.mjs）。
出力: App/Resources/Stage/ の StageTile_<id>.jpg・StageDecal_rune.jpg・StageProps.bin・StagePropsAtlas.jpg。

  python3 tools/stage/stage_bake.py tiles      # 地面タイル 7 種: シームレス化（オフセット合成）→ 1024px JPEG
  python3 tools/stage/stage_bake.py decal      # 祭壇の模様: 円の外接正方形で切り出し → 1024px JPEG
  python3 tools/stage/stage_bake.py props      # 小物 8 種: Blender で減面・新しい UV に色を焼き付け → 正規化
                                               #   → StageProps.bin + StagePropsAtlas.jpg
  python3 tools/stage/stage_bake.py preview    # 確認用画像 → build/stage/preview/（小物は .bin + アトラスを読み戻して描く）
  python3 tools/stage/stage_bake.py all        # 上の 4 つを順に

環境変数: STAGE_PROPS_UV=rebake|meshy（UV の作り方、下の UV_MODE）、STAGE_BAKE_JOBS（Blender の同時実行数、既定 4）、
STAGE_BUSH_REMESH（茂みのボクセルの大きさ / 対角、既定 0.02）。中間物は build/stage/props/（npz・焼いた色・Blender のログ・
report.json）。

numpy と Pillow が要る。無ければ build/stage/venv の Python で自分を起動し直す（venv の作り方は下の VENV_HELP）。
Blender は環境変数 BLENDER（既定 /Applications/Blender.app/Contents/MacOS/Blender）。Blender 側の処理は
tools/stage/stage_props_blender.py。検証は tools/stage/check_stage_assets.py。
"""
import json
import os
import struct
import subprocess
import sys
import zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # VELSTRIA/
VENV = ROOT / "build" / "stage" / "venv"
VENV_HELP = (
    "numpy / Pillow が必要。build/stage/venv を作る（Homebrew の python3 は pyexpat が壊れていることがあるので uv の Python）:\n"
    "  uv venv --python 3.12 build/stage/venv && uv pip install --python build/stage/venv/bin/python pillow numpy"
)

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    py = VENV / "bin" / "python"
    if py.exists() and Path(sys.prefix).resolve() != VENV.resolve() and not os.environ.get("STAGE_BAKE_REEXEC"):
        os.environ["STAGE_BAKE_REEXEC"] = "1"
        os.execv(str(py), [str(py), str(Path(__file__).resolve()), *sys.argv[1:]])
    sys.exit(VENV_HELP)

ART = ROOT / "build" / "stage" / "art"
MESHY = ROOT / "build" / "stage" / "meshy"
WORK = ROOT / "build" / "stage" / "props"
PREVIEW = ROOT / "build" / "stage" / "preview"
OUT = ROOT / "App" / "Resources" / "Stage"
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")
BLENDER_SCRIPT = Path(__file__).with_name("stage_props_blender.py")

TILES = ["grass", "grass_dark", "dirt", "paving", "rock", "moss", "riverbed"]
TILE_SIZE = 1024
JPEG_QUALITY = 90

DECAL_SIZE = 1024

# 小物（アトラスのセル順 = この順。左上から行優先で 4 列 × 2 行）。
# size: (寸法の種類, メートル)。width = X の幅、height = Y の高さ、footprint = 足跡（x/z）の長辺。
PROPS = [
    ("cliff_rock_a", 1000, ("width", 4.0)),
    ("cliff_rock_b", 900, ("height", 3.0)),
    ("boulder", 500, ("footprint", 2.0)),
    ("tree_round", 1100, ("height", 4.2)),
    ("tree_tall", 1050, ("height", 5.0)),
    ("bush", 450, ("footprint", 1.6)),
    ("ruin_pillar", 900, ("height", 2.6)),
    ("ruin_arch", 1400, ("width", 4.0)),
]
# 茂みは葉の板の集まりで、1000 三角形まで減らすと葉が三角形の破片になる → ボクセルで 1 つの塊にしてから減らす
# （値 = ボクセルの大きさ / 外接箱の対角）。色は元の葉から焼き付ける
REMESH = {"bush": float(os.environ.get("STAGE_BUSH_REMESH", "0.02"))}
# UV の作り方。rebake（既定）: 減面後のメッシュに新しい UV を作り、Meshy の base_color.png を元のメッシュから
# 焼き付けた絵をセルに入れる。meshy: Meshy の UV と base_color をそのまま使う（STAGE.md 3.3 の字義どおり）。
# Meshy の UV は 1 体あたり数千の小島に分かれていて、1/5〜1/10 の減面で三角形が複数の島にまたがり色が崩れる。
UV_MODE = os.environ.get("STAGE_PROPS_UV", "rebake")
BAKE_SIZE = 1024
ATLAS_W, ATLAS_H = 2048, 1024
CELL, PAD = 512, 8
INNER = CELL - 2 * PAD   # 496
NORMAL_SPLIT_ANGLE = 60.0


def log(msg):
    print(f"[stage_bake] {msg}", flush=True)


def save_jpeg(img, path, **kw):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp.jpg")
    img.convert("RGB").save(tmp, "JPEG", quality=JPEG_QUALITY, optimize=True, **kw)
    os.replace(tmp, path)
    log(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size} bytes)")


def load_rgb(path):
    if not path.exists():
        sys.exit(f"missing input: {path}")
    return Image.open(path).convert("RGB")


# ---------------------------------------------------------------- tiles

def periodic_noise_1d(n, seed, lo=1, hi=6):
    """周期 n の低周波ノイズ（-1…1）。周波数 lo…hi 周期/タイルの成分を乱数位相で足す（FFT なので周期的）。"""
    rng = np.random.default_rng(seed)
    spec = np.zeros(n, np.complex128)
    k = np.arange(lo, hi + 1)
    spec[k] = (rng.normal(size=len(k)) + 1j * rng.normal(size=len(k))) / k
    f = np.real(np.fft.ifft(spec))
    return f / (np.abs(f).max() + 1e-12)


def blur_axis(a, sigma, axis, wrap):
    """1 軸のガウスぼかし。wrap=True は周期境界、False は端で折り返し（reflect）。"""
    r = max(1, int(np.ceil(3.5 * sigma)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    m = np.moveaxis(np.asarray(a, np.float64), axis, 0)
    n = m.shape[0]
    p = np.pad(m, [(r, r)] + [(0, 0)] * (m.ndim - 1), mode="wrap" if wrap else "reflect")
    out = np.zeros_like(m)
    for i, w in enumerate(k):
        out += w * p[i:i + n]
    return np.moveaxis(out, 0, axis)


def blur2(a, sigma, wrap0, wrap1):
    """先頭 2 軸のガウスぼかし（軸ごとに周期 / 折り返し）。"""
    return blur_axis(blur_axis(a, sigma, 0, wrap0), sigma, 1, wrap1)


def min_path(cost, closed, starts=8):
    """cost（L × B）を上から下へ 1 行 1 列ずつ（横に ±1 まで）進む最小コストの道。各行の列番号（L,）を返す。
    closed=True は終点を始点の ±1 列に戻す（行方向が周期的なとき、道が 1 周してつながる）。始点の候補は先頭行の
    安い所から starts 個。"""
    L, B = cost.shape
    inf = np.inf
    if closed:
        order = np.argsort(cost[0])
        cands = []
        for c in order:
            if all(abs(int(c) - d) > B // (2 * starts) for d in cands):
                cands.append(int(c))
            if len(cands) >= starts:
                break
    else:
        cands = [None]
    best = None
    for s0 in cands:
        if s0 is None:
            acc = cost[0].astype(np.float64).copy()
        else:
            acc = np.full(B, inf)
            acc[s0] = cost[0, s0]
        back = np.zeros((L, B), np.int8)
        for y in range(1, L):
            left = np.concatenate([[inf], acc[:-1]])
            right = np.concatenate([acc[1:], [inf]])
            stack = np.stack([left, acc, right])
            k = np.argmin(stack, axis=0)
            acc = stack[k, np.arange(B)] + cost[y]
            back[y] = k - 1
        lo, hi = (0, B) if s0 is None else (max(0, s0 - 1), min(B, s0 + 2))
        end = lo + int(np.argmin(acc[lo:hi]))
        if best is None or acc[end] < best[0]:
            path = np.empty(L, np.int64)
            path[-1] = end
            for y in range(L - 1, 0, -1):
                path[y - 1] = path[y] + back[y, path[y]]
            best = (acc[end], path)
    return best[1]


# 継ぎ目を覆う帯の幅（周期 n に対する割合）。元の絵を n + 帯 の大きさに縮め、はみ出した帯を継ぎ目に重ねる
TILE_BAND = 0.125
TILE_LOW_SIGMA = 32.0   # 帯の中で全幅かけて混ぜる低周波（明るさのむら）と、切れ目で切り替える細部の境目（px）
TILE_FEATHER = 2.0      # 切れ目のぼかし（px）


def wrap_pass(a, n, seed, periodic_rows):
    """列方向を周期 n にする 1 段（a: (H, n + b) → (H, n)）。オフセット合成と同じ考え方で、半分ずらした絵の中央に
    来る元の絵の継ぎ目（列 n−1 → 列 0）を、元の絵の続き E = 列 n…n+b−1（列 n−1 の自然な続き）で覆う。
    出力の列 c（0 ≤ c < b）は E[c] から元の P[c] = 列 c へ切り替わる: 列 0 は E[0]（列 n−1 から自然に続く）、
    列 b−1 は P[b−1]（列 b へ自然に続く）。どの画素も元の絵の 1 か所（帯では 2 か所の混ぜ合わせ）から来るので、
    同じ模様が 2 回出ない（旧版は半分ずらした絵を端に、元の絵を中央に使ったため、中央の半分が 2 回ずつ並んだ）。
    切り替えは 2 つの帯域に分ける: 低周波（σ = TILE_LOW_SIGMA の明るさ・色のむら）は帯の全幅で滑らかに、
    細部は 2 枚の差が小さい所を通る最小コストの切れ目（縦に走る道、低周波ノイズで揺らす）で切り替えて
    TILE_FEATHER px ぼかす。periodic_rows: 行方向がすでに周期的（2 段目）なら、道を閉じ・ぼかしも周期境界にして
    行方向の周期性を保つ。"""
    H, W, _ = a.shape
    b = W - n
    low = blur2(a, TILE_LOW_SIGMA, periodic_rows, False)
    high = a - low
    p_l, p_h = low[:, :b], high[:, :b]
    e_l, e_h = low[:, n:], high[:, n:]
    diff = ((p_h - e_h) ** 2).sum(axis=2)
    diff = blur2(diff, 1.5, periodic_rows, False)
    diff /= diff.mean() + 1e-9
    m = int(np.ceil(4 * TILE_FEATHER)) + 1      # 切れ目は帯の両端から m px 離す（ぼかしが帯の端に届かない）
    bw = b - 2 * m
    centre = (bw - 1) / 2 + 0.3 * bw * periodic_noise_1d(H, seed)
    guide = ((np.arange(bw)[None, :] - centre[:, None]) / (bw / 2)) ** 2
    path = min_path(diff[:, m:m + bw] + 0.6 * guide, closed=periodic_rows) + m
    cols = np.arange(b)[None, :]
    w = blur2((cols > path[:, None]).astype(np.float64), TILE_FEATHER, periodic_rows, False)
    w[w < 1e-4] = 0.0
    w[w > 1 - 1e-4] = 1.0
    w[:, 0], w[:, -1] = 0.0, 1.0
    t = np.linspace(0.0, 1.0, b)
    ramp = (t * t * (3 - 2 * t))[None, :, None]
    band = e_l + ramp * (p_l - e_l) + e_h + w[..., None] * (p_h - e_h)
    out = a[:, :n].copy()
    out[:, :b] = band
    return out


def make_seamless(a, n, seed):
    """(n + b) 四方の絵 → n 四方のシームレスなタイル（docs/STAGE.md 3.1）。x の段 → y の段（転置して同じ処理）の
    分離型。x の段の結果は各行が x 方向に周期的で、y の段は各列（x ごと）の中で行を混ぜるだけ・切れ目の道は閉じて
    いて・ぼかしも x に周期境界なので、y の段で x の継ぎ目は戻らない。色の調整はしない（各画素は元の絵の
    2 か所の線形な混ぜ合わせ）。"""
    assert a.shape[0] == a.shape[1] and a.shape[0] > n
    t = a.astype(np.float64)
    t = wrap_pass(t, n, seed, periodic_rows=False)                                     # (n + b, n)
    t = wrap_pass(t.transpose(1, 0, 2), n, seed + 7919, periodic_rows=True).transpose(1, 0, 2)  # (n, n)
    return np.clip(np.rint(t), 0, 255).astype(np.uint8)


def tile_seed(tid):
    return zlib.crc32(tid.encode()) & 0x7FFFFFFF


def bake_tiles():
    for tid in TILES:
        src = load_rgb(ART / f"{tid}.png")
        if src.size[0] != src.size[1]:
            side = min(src.size)
            src = src.crop((0, 0, side, side))
        # 絵全体を周期 + 帯の大きさに縮める（帯の分は継ぎ目を覆うのに使い、出力には 1 回だけ現れる）
        band = int(round(TILE_BAND * TILE_SIZE / 16)) * 16
        small = src.resize((TILE_SIZE + band, TILE_SIZE + band), Image.Resampling.LANCZOS)
        out = make_seamless(np.asarray(small), TILE_SIZE, tile_seed(tid))
        save_jpeg(Image.fromarray(out), OUT / f"StageTile_{tid}.jpg")


# ---------------------------------------------------------------- decal

def bake_decal():
    """円形の台座（背景は平らな中間灰色）の外接矩形を求め、円がちょうど内接する正方形で切り出す。"""
    img = load_rgb(ART / "rune_circle.png")
    a = np.asarray(img).astype(np.int16)
    h, w, _ = a.shape
    k = 4
    border = np.concatenate([a[:k].reshape(-1, 3), a[-k:].reshape(-1, 3), a[:, :k].reshape(-1, 3), a[:, -k:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    diff = np.abs(a - bg).max(axis=2)
    fg = diff > 16
    # ぽつんとした雑音を数えないよう、前景が 4 画素以上ある行・列だけを見る
    rows = np.where(fg.sum(axis=1) >= 4)[0]
    cols = np.where(fg.sum(axis=0) >= 4)[0]
    if len(rows) == 0 or len(cols) == 0:
        sys.exit("decal: no foreground found")
    y0, y1, x0, x1 = rows[0], rows[-1] + 1, cols[0], cols[-1] + 1
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    side = max(x1 - x0, y1 - y0)
    box = (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2)
    log(f"decal: background {bg.tolist()}, bbox x {x0}..{x1} y {y0}..{y1}, square side {side} at ({cx}, {cy})")
    # 画像の外にはみ出す分は端の画素で埋める（transform は小数の箱を直接リサンプルできる）
    pad = int(max(0, -box[0], -box[1], box[2] - w, box[3] - h)) + 2
    if pad > 2:
        img = Image.fromarray(np.pad(np.asarray(img), ((pad, pad), (pad, pad), (0, 0)), mode="edge"))
        box = tuple(v + pad for v in box)
    out = img.resize((DECAL_SIZE, DECAL_SIZE), Image.Resampling.LANCZOS, box=box)
    save_jpeg(out, OUT / "StageDecal_rune.jpg")
    return {"bbox": [int(x0), int(y0), int(x1), int(y1)], "side": int(side)}


# ---------------------------------------------------------------- props

def run_blender(args, log_path):
    cmd = [BLENDER, "-b", "--factory-startup", "--python-exit-code", "1", "--python", str(BLENDER_SCRIPT), "--", *args]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(" ".join(cmd) + "\n\n" + proc.stdout + "\n" + proc.stderr)
    if proc.returncode != 0:
        tail = (proc.stdout + proc.stderr)[-3000:]
        raise RuntimeError(f"blender failed ({log_path}):\n{tail}")
    return proc.stdout


def blender_bake(pid, tris):
    glb = MESHY / pid / "model.glb"
    base = MESHY / pid / "base_color.png"
    for f in (glb, base):
        if not f.exists():
            sys.exit(f"missing input: {f}")
    out = WORK / f"{pid}.npz"
    args = ["bake", "--glb", str(glb), "--tris", str(tris), "--angle", str(NORMAL_SPLIT_ANGLE), "--out", str(out),
            "--mode", UV_MODE]
    if UV_MODE == "rebake":
        args += ["--base-color", str(base), "--bake-out", str(WORK / f"{pid}_color.png"), "--bake-size", str(BAKE_SIZE)]
        if pid in REMESH:
            args += ["--remesh", str(REMESH[pid])]
    stdout = run_blender(args, WORK / f"{pid}.blender.log")
    stats = {}
    for line in stdout.splitlines():
        if line.startswith("[stage_props] STATS "):
            stats = json.loads(line.split("STATS ", 1)[1])
    return out, stats


def best_yaw(p):
    """鉛直軸まわりの回転（1° 刻み、0…179°）で Z の幅が最小になる角度。180° ずらしても幅は同じなので半周で足りる。"""
    xz = p[:, [0, 2]]
    best = None
    for deg in range(180):
        t = np.radians(deg)
        z = -xz[:, 0] * np.sin(t) + xz[:, 1] * np.cos(t)
        ext = z.max() - z.min()
        if best is None or ext < best[1] - 1e-9:
            best = (deg, ext)
    return best[0]


def rot_y(a, deg):
    """+Y まわりに deg 度（RealityKit の右手系）: x' = x cos + z sin、z' = −x sin + z cos。"""
    t = np.radians(deg)
    c, s = np.cos(t), np.sin(t)
    x, y, z = a[:, 0], a[:, 1], a[:, 2]
    return np.stack([x * c + z * s, y, -x * s + z * c], axis=1)


def cell_rect(index):
    """アトラスのセル index の内側（画像の画素、左上原点）: (x0, y0, x1, y1)。"""
    col, row = index % 4, index // 4
    x0, y0 = col * CELL + PAD, row * CELL + PAD
    return x0, y0, x0 + INNER, y0 + INNER


def finish_prop(index, pid, size_rule, npz):
    """Blender の結果（Z-up・角ごとの配列）→ RealityKit の座標・向き・寸法・原点・アトラスの UV・頂点の共有。"""
    d = np.load(npz)
    co = d["co"].astype(np.float64)
    cn = d["corner_normal"].astype(np.float64)
    cuv = d["corner_uv"].astype(np.float64)
    cvert = d["corner_vert"]
    tri_loops = d["tri_loops"]

    # Blender（Z-up）→ RealityKit（Y-up）: (x, y, z) → (x, z, −y)。回転（行列式 +1）なので巻き順はそのまま
    to_rk = lambda a: np.stack([a[:, 0], a[:, 2], -a[:, 1]], axis=1)
    pos = to_rk(co)
    nrm = to_rk(cn)

    yaw = best_yaw(pos)
    pos = rot_y(pos, yaw)
    nrm = rot_y(nrm, yaw)

    lo, hi = pos.min(axis=0), pos.max(axis=0)
    ext = hi - lo
    kind, meters = size_rule
    measured = {"width": ext[0], "height": ext[1], "footprint": max(ext[0], ext[2])}[kind]
    scale = meters / measured
    pos *= scale
    lo, hi = pos.min(axis=0), pos.max(axis=0)
    pos -= np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])

    # 長さ 0 の角の法線（潰れかけの面）は、その角の三角形の面の法線で置き換える
    tri_p = pos[cvert[tri_loops]]
    face_n = np.cross(tri_p[:, 1] - tri_p[:, 0], tri_p[:, 2] - tri_p[:, 0])
    corner_face_n = np.zeros_like(nrm)
    corner_face_n[tri_loops.ravel()] = np.repeat(face_n, 3, axis=0)
    nlen = np.linalg.norm(nrm, axis=1)
    weak = nlen < 1e-6
    nrm[weak] = corner_face_n[weak]
    nlen = np.linalg.norm(nrm, axis=1)
    nrm[nlen < 1e-12] = (0.0, 1.0, 0.0)
    zero_normals = int(weak.sum())

    # 頂点 = (Blender の頂点, 角の法線, UV) の組。同じ組の角は 1 頂点にまとめる
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True).clip(1e-12)
    key = np.concatenate([cvert[:, None].astype(np.float64), np.round(nrm, 5), np.round(cuv, 7)], axis=1)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inverse = inverse.ravel()
    v_pos = pos[cvert[first]]
    v_nrm = nrm[first]
    v_uv = cuv[first]
    tris = inverse[tri_loops]

    # 潰れた三角形（面積ほぼ 0）は捨てる
    a, b, c = v_pos[tris[:, 0]], v_pos[tris[:, 1]], v_pos[tris[:, 2]]
    fn = np.cross(b - a, c - a)
    area2 = np.linalg.norm(fn, axis=1)
    keep = area2 > 1e-10
    dropped = int((~keep).sum())
    tris, fn = tris[keep], fn[keep]

    # 巻き順: 外から見て反時計回りが表 ⇔ (b−a)×(c−a) が頂点の法線と同じ向き
    vn = v_nrm[tris[:, 0]] + v_nrm[tris[:, 1]] + v_nrm[tris[:, 2]]
    agree = float(((fn * vn).sum(axis=1) > 0).mean())
    flipped = False
    if agree < 0.5:
        tris = tris[:, [0, 2, 1]]
        agree = 1.0 - agree
        flipped = True
    if agree < 0.95:
        raise SystemExit(f"{pid}: winding agrees with normals for only {agree:.1%} of triangles")

    # 使われなくなった頂点を詰める
    used = np.unique(tris)
    remap = np.full(len(v_pos), -1, np.int64)
    remap[used] = np.arange(len(used))
    v_pos, v_nrm, v_uv = v_pos[used], v_nrm[used], v_uv[used]
    tris = remap[tris]

    # UV: Blender の v は下端 0（glTF 取り込みが v_image = 1 − v_blender に反転済み）。
    # セルの内側（画像の画素）へ写してから RealityKit の向き（アトラスの下端 = 0）にする
    x0, y0, x1, y1 = cell_rect(index)
    u_img = np.clip(v_uv[:, 0], 0.0, 1.0)
    v_img = np.clip(1.0 - v_uv[:, 1], 0.0, 1.0)
    px = np.clip(x0 + u_img * INNER, x0, x1)
    py = np.clip(y0 + v_img * INNER, y0, y1)
    u_rk = px / ATLAS_W
    v_rk = 1.0 - py / ATLAS_H

    verts = np.zeros((len(v_pos), 8), np.float32)
    verts[:, 0:3] = v_pos
    verts[:, 3:6] = v_nrm / np.linalg.norm(v_nrm, axis=1, keepdims=True)
    verts[:, 6] = u_rk
    verts[:, 7] = v_rk
    # float32 にした後の値で境界を取り直し、最低点をちょうど 0 にする
    verts[:, 1] -= verts[:, 1].min()
    idx = tris.astype(np.uint32).ravel()
    bmin = verts[:, 0:3].min(axis=0)
    bmax = verts[:, 0:3].max(axis=0)
    info = {
        "id": pid, "yawDeg": yaw, "scale": round(float(scale), 6), "flipped": flipped,
        "windingAgree": round(agree, 4), "droppedDegenerate": dropped, "zeroNormalsFixed": zero_normals,
        "tris": int(len(idx) // 3), "verts": int(len(verts)),
        "size": [round(float(x), 4) for x in (bmax - bmin)],
    }
    return verts, idx, [float(x) for x in bmin], [float(x) for x in bmax], info


def cell_source(pid):
    """セルに入れる絵: rebake なら焼き付けた色（build/stage/props/<id>_color.png）、meshy なら Meshy の base_color。"""
    return WORK / f"{pid}_color.png" if UV_MODE == "rebake" else MESHY / pid / "base_color.png"


def pull_push_fill(img, known):
    """known でない画素を周りの色で埋める（pull-push: 2 倍ずつ縮めた平均で穴を埋めて戻す）。
    焼き付けの余白（16 px）より外の空き地を埋めて、縮小・ミップマップで島の外の色が混ざらないようにする。"""
    levels = [(img.astype(np.float64) * known[..., None], known.astype(np.float64))]
    while min(levels[-1][1].shape) > 1:
        c, w = levels[-1]
        h2, w2 = (c.shape[0] + 1) // 2, (c.shape[1] + 1) // 2
        c = np.pad(c, ((0, h2 * 2 - c.shape[0]), (0, w2 * 2 - c.shape[1]), (0, 0)))
        w = np.pad(w, ((0, h2 * 2 - w.shape[0]), (0, w2 * 2 - w.shape[1])))
        c = c.reshape(h2, 2, w2, 2, 3).sum(axis=(1, 3))
        w = w.reshape(h2, 2, w2, 2).sum(axis=(1, 3))
        levels.append((c, w))
    color = levels[-1][0] / np.maximum(levels[-1][1], 1e-9)[..., None]
    for c, w in reversed(levels[:-1]):
        up = np.repeat(np.repeat(color, 2, axis=0), 2, axis=1)[:c.shape[0], :c.shape[1]]
        own = c / np.maximum(w, 1e-9)[..., None]
        color = np.where((w > 0)[..., None], own, up)
    out = np.where(known[..., None], img, np.clip(np.rint(color), 0, 255))
    return out.astype(np.uint8)


def load_cell_source(pid):
    img = load_rgb(cell_source(pid))
    if UV_MODE != "rebake":
        return img
    a = np.asarray(img)
    unbaked = (a[..., 0] == 255) & (a[..., 1] == 0) & (a[..., 2] == 255)
    return Image.fromarray(pull_push_fill(a, ~unbaked))


def build_atlas():
    """2048×1024、512 px のセル 4 列 × 2 行。各セル = 絵を 496 px に縮小 + 周囲 8 px を端の画素の引き伸ばし。"""
    atlas = np.zeros((ATLAS_H, ATLAS_W, 3), np.uint8)
    for i, (pid, _, _) in enumerate(PROPS):
        src = load_cell_source(pid)
        inner = np.asarray(src.resize((INNER, INNER), Image.Resampling.LANCZOS))
        cell = np.pad(inner, ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge")
        col, row = i % 4, i // 4
        atlas[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL] = cell
    # UV の島が細かいので色差の間引き（4:2:0）はしない（4:4:4）
    save_jpeg(Image.fromarray(atlas), OUT / "StagePropsAtlas.jpg", subsampling=0)


def write_props_bin(entries, path):
    """docs/STAGE.md 3.3 のバイナリ。各ブロックはデータ先頭から 16 バイト境界に置く。"""
    blobs, records, off = [], [], 0

    def push(b):
        nonlocal off
        start = off
        blobs.append(b)
        off += len(b)
        pad = (-off) % 16
        if pad:
            blobs.append(b"\0" * pad)
            off += pad
        return start

    for pid, verts, idx, bmin, bmax in entries:
        vo = push(verts.astype("<f4").tobytes())
        io = push(idx.astype("<u4").tobytes())
        records.append({"id": pid, "vertexCount": int(len(verts)), "indexCount": int(len(idx)),
                        "vertexOffset": vo, "indexOffset": io,
                        "boundsMin": [round(x, 6) for x in bmin], "boundsMax": [round(x, 6) for x in bmax],
                        "tris": int(len(idx) // 3)})
    header = json.dumps({"atlas": {"width": ATLAS_W, "height": ATLAS_H}, "props": records},
                        separators=(",", ":")).encode("utf-8")
    head = b"VSP1" + struct.pack("<II", 1, len(header)) + header
    head += b"\0" * ((-len(head)) % 16)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with open(tmp, "wb") as f:
        f.write(head)
        for b in blobs:
            f.write(b)
    os.replace(tmp, path)
    log(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size} bytes)")
    return records


def bake_props():
    WORK.mkdir(parents=True, exist_ok=True)
    jobs = int(os.environ.get("STAGE_BAKE_JOBS", "4"))
    with ThreadPoolExecutor(max_workers=jobs) as ex:
        futures = {pid: ex.submit(blender_bake, pid, tris) for pid, tris, _ in PROPS}
        results = {pid: f.result() for pid, f in futures.items()}
    entries, infos = [], []
    for i, (pid, tris, size_rule) in enumerate(PROPS):
        npz, stats = results[pid]
        verts, idx, bmin, bmax, info = finish_prop(i, pid, size_rule, npz)
        info["blender"] = stats
        info["bmin"] = [round(x, 4) for x in bmin]
        info["bmax"] = [round(x, 4) for x in bmax]
        infos.append(info)
        entries.append((pid, verts, idx, bmin, bmax))
        log(f"{pid}: {info['tris']} tris (target {tris}), {info['verts']} verts, yaw {info['yawDeg']}°, "
            f"size {info['size']}, winding {info['windingAgree']:.3f}{' (flipped)' if info['flipped'] else ''}")
    build_atlas()
    write_props_bin(entries, OUT / "StageProps.bin")
    (WORK / "report.json").write_text(json.dumps(infos, ensure_ascii=False, indent=2) + "\n")
    return infos


# ---------------------------------------------------------------- preview

def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def preview_tiles():
    """各タイルを 3×3 に並べた画像（継ぎ目の目視用）。全体は半分に縮め、四隅が集まる所は原寸で切り出す。"""
    out = PREVIEW / "tiles"
    out.mkdir(parents=True, exist_ok=True)
    thumbs = []
    for tid in TILES:
        t = np.asarray(Image.open(OUT / f"StageTile_{tid}.jpg").convert("RGB"))
        big = np.tile(t, (3, 3, 1))
        Image.fromarray(big).resize((big.shape[1] // 2, big.shape[0] // 2), Image.Resampling.LANCZOS) \
            .save(out / f"{tid}_3x3.jpg", quality=88)
        n = t.shape[0]
        Image.fromarray(big[n - 256:n + 256, n - 256:n + 256]).save(out / f"{tid}_corner.png")
        thumbs.append((tid, Image.fromarray(big).resize((600, 600), Image.Resampling.LANCZOS)))
    sheet = Image.new("RGB", (600 * 4, 640 * 2), (30, 30, 30))
    d = ImageDraw.Draw(sheet)
    for k, (tid, im) in enumerate(thumbs):
        x, y = (k % 4) * 600, (k // 4) * 640
        sheet.paste(im, (x, y + 40))
        d.text((x + 10, y + 8), f"{tid} (3x3)", fill=(240, 240, 240), font=font(24))
    decal = OUT / "StageDecal_rune.jpg"
    if decal.exists():
        x, y = 3 * 600, 640
        sheet.paste(Image.open(decal).convert("RGB").resize((600, 600), Image.Resampling.LANCZOS), (x, y + 40))
        d.text((x + 10, y + 8), "StageDecal_rune", fill=(240, 240, 240), font=font(24))
    sheet.save(PREVIEW / "tiles_sheet.jpg", quality=88)
    log(f"wrote {(PREVIEW / 'tiles_sheet.jpg').relative_to(ROOT)} and {out.relative_to(ROOT)}/")


def preview_props():
    """StageProps.bin + StagePropsAtlas.jpg を Blender で読み戻して描く（GLB は使わない）→ 一覧 props_sheet.png。"""
    out = PREVIEW / "props"
    out.mkdir(parents=True, exist_ok=True)
    run_blender(["render", "--bin", str(OUT / "StageProps.bin"), "--atlas", str(OUT / "StagePropsAtlas.jpg"),
                 "--outdir", str(out), "--res", "512", "--azimuths", "25,205"], out / "render.blender.log")
    header = json.loads(read_header(OUT / "StageProps.bin"))
    recs = {p["id"]: p for p in header["props"]}
    cw, ch, top = 1024, 512, 44
    sheet = Image.new("RGB", (cw * 4, (ch + top) * 2), (24, 24, 24))
    d = ImageDraw.Draw(sheet)
    for k, (pid, target, size_rule) in enumerate(PROPS):
        x, y = (k % 4) * cw, (k // 4) * (ch + top)
        for v in range(2):
            sheet.paste(Image.open(out / f"{pid}_v{v}.png").convert("RGB"), (x + v * 512, y + top))
        thumb = MESHY / pid / "thumbnail.png"
        if thumb.exists():
            sheet.paste(Image.open(thumb).convert("RGB").resize((160, 160), Image.Resampling.LANCZOS), (x + cw - 166, y + top + 6))
        r = recs[pid]
        size = [b - a for a, b in zip(r["boundsMin"], r["boundsMax"])]
        d.text((x + 10, y + 8), f"{pid}  {r['tris']} tris / {r['vertexCount']} verts  "
               f"{size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} m", fill=(240, 240, 240), font=font(22))
    sheet.save(PREVIEW / "props_sheet.png")
    log(f"wrote {(PREVIEW / 'props_sheet.png').relative_to(ROOT)}")


def read_header(path):
    with open(path, "rb") as f:
        head = f.read(12)
        _, jlen = struct.unpack_from("<II", head, 4)
        return f.read(jlen).decode("utf-8")


def preview():
    PREVIEW.mkdir(parents=True, exist_ok=True)
    preview_tiles()
    preview_props()


# ---------------------------------------------------------------- main

def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd = argv[0]
    steps = {"tiles": bake_tiles, "decal": bake_decal, "props": bake_props, "preview": preview}
    if cmd == "all":
        for name in ("tiles", "decal", "props", "preview"):
            log(f"== {name}")
            steps[name]()
        return 0
    if cmd not in steps:
        sys.exit(f"unknown command: {cmd}")
    steps[cmd]()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
