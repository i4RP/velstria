#!/usr/bin/env python3
"""ホーム画面の中央ショーケース用のヒーローアート（HeroSplash）と人物マスク（HeroSplashMatte）の作成と取り込み。

対象は tools/portraits/portraits.json のヒーロー 24 体とスキン 12 点。絵そのものは portraits.py が作った
ポートレートの原画（build/portraits/<ID>.png、約 1254px）を使い、ここでは大きめの JPEG と切り抜きマスクを作るだけ。

  python3 tools/portraits/splash.py sources              # ID ごとに元画像を決めて黒地へ合成（build/splash/flat/）
  python3 tools/portraits/splash.py find H003 <フォルダ>   # 名前の分からない原画を探して build/splash/raw/H003.png へコピー
  python3 tools/portraits/splash.py matte [ID,ID,...]    # Vision で人物マスクを作る（matte.swift。1 回の起動で全画像）
  python3 tools/portraits/splash.py sheet [ID,...|all] [セル px]  # 確認用の一覧（左 = 原画、右 = 原画 × マスクをマゼンタ地に）
  python3 tools/portraits/splash.py variants ID[,ID,...] # マスクの作り方の候補を並べた比較画像（MATTE_PAD を決める用）
  python3 tools/portraits/splash.py install              # Assets.xcassets の HeroSplash / HeroSplashMatte へ
  python3 tools/portraits/splash.py all                  # sources → matte → sheet → install

元画像の決め方（sources）: アプリに入っているポートレート（HeroPortraits / SkinPortraits の 640px JPEG）と違う絵を
ショーケースに出さないよう、原画とアプリ内の JPEG を ssim で照合する（どちらも 160px に縮めて比べる。JPEG の荒れに
左右されず、同じ絵は 0.93 以上、構図の似た別候補は 0.4〜0.6、別の絵は 0.15 未満になる）。<ID>.png が一致しなければ
候補（<ID>_*.png）も調べ、どれも一致しなければアプリ内の JPEG を lanczos で拡大して使う（結果は build/splash/sources.json）。
原画を探す場所は build/portraits/ と build/splash/raw/。別の作業ツリーの原画を使うときは環境変数 SPLASH_RAW_DIRS
（: 区切り）で足す。別セッションが描き直して原画が build/portraits/ に無い ID は、find で Codex の生成物置き場
（~/.codex/generated_images）などから一致する PNG を探せる（フォルダ以下の *.png を総当たりで照合する）。

マスク（matte）: macOS 14 以降の Vision（VNGenerateForegroundInstanceMaskRequest）で前景を求め、512px に縮めて
わずかにぼかす（白 = 人物、黒 = 背景の 8bit グレースケール PNG）。Vision は人物が画像の端で切れていると腕・武器・盾を
取りこぼすことがあり、絵を縮めて周りに余白を足してから求めると拾えることが多い（余白の幅と色で結果が変わる）。
作ったら必ず sheet の一覧を目で確認し、欠けや背景の残りが大きい ID は variants で候補を見比べて MATTE_PAD に書く。
どの候補でも駄目な ID は NO_MATTE に足す（UI はマスクが無ければ絵全体を通常合成する）。

中間ファイルは build/splash/（git 管理外）。並列数は環境変数 SPLASH_JOBS（既定 4）。
"""
import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # VELSTRIA/
SPEC = Path(__file__).with_name("portraits.json")
MATTE_SWIFT = Path(__file__).with_name("matte.swift")
ASSETS = ROOT / "App" / "Resources" / "Assets.xcassets"
WORK = ROOT / "build" / "splash"
FOUND = WORK / "raw"      # find で見つけた原画の置き場（<ID>.png）
FLAT = WORK / "flat"      # 元画像を黒地へ合成したもの（原画の大きさ。拡大した ID は 1024px）
MATTE = WORK / "matte"    # 512px に縮めてぼかしたマスク（アプリに入れる形）
VARIANT = WORK / "variants"
SOURCES = WORK / "sources.json"
SPLASH_FOLDER = "HeroSplash"
MATTE_FOLDER = "HeroSplashMatte"
PORTRAIT_FOLDERS = ("HeroPortraits", "SkinPortraits")
SPLASH_PIXELS = 1024
MATTE_PIXELS = 512
JPEG_QUALITY = 66  # 1 点 250KB 前後（細密な塗りなので 84 だと 500KB 前後になる）
SSIM_PIXELS = 160         # 照合するときの大きさ
SSIM_MATCH = 0.85         # これ以上なら「アプリ内のポートレートと同じ絵」とみなす
MATTE_BLUR = 1.2          # 512px に縮めた後のぼかし（sigma、px）
MATTE_CANVAS = 1152       # 余白を足すときのキャンバス。絵は MATTE_CANVAS - 2 × 余白 に縮めて中央に置く
JOBS = max(1, int(os.environ.get("SPLASH_JOBS", "4")))

# Vision に渡す前に足す余白 (幅 px, 色)。書いていない ID は余白なし（絵をそのまま渡す）。
# 2026-10 の絵で variants を見比べて決めた。絵を描き直した ID は決め直すこと。
MATTE_PAD = {
    "H004": (192, "black"),   # 余白なしだと杖先の水流と手の水球が落ちる
    "H005": (192, "black"),   # 左端の槍の上半分
    "H007": (192, "black"),   # 左の岩の拳が丸ごと落ちる
    "H010": (192, "black"),   # 右手の炎
    "H011": (192, "black"),   # 杖のランタンの中身
    "H014": (128, "gray"),    # 余白なしだと頭しか残らない
    "H017": (192, "black"),   # 右下の外套
    "CO007": (192, "black"),  # 拳（H007 と同じ）
    "CO031": (128, "black"),  # 拳。192 だと左上の背景まで入る
    "CO055": (320, "black"),  # 氷の拳はこの幅でだけ拾える
    "CO049": (192, "gray"),   # 氷の盾は灰色の余白でだけ全体が入る
    "CO043": (192, "black"),  # 左上の槌の頭
    "CO067": (192, "gray"),   # 槌の頭。黒の余白だと上の背景が広く残る
}
# variants が並べる候補（先頭の None = 余白なし）
VARIANT_PADS = [None, (64, "black"), (128, "black"), (192, "black"), (320, "black"),
                (128, "gray"), (192, "gray"), (192, "white")]

# 一覧で確認した結果、マスクを入れない ID と理由。install は該当 ID の HeroSplashMatte を作らない。
NO_MATTE = {
}

FLATTEN = "split[a][b];[a]format=rgb24,drawbox=c=black:t=fill[bg];[bg][b]overlay=format=auto,format=rgb24"


def all_ids():
    s = json.loads(SPEC.read_text())
    return [h["id"] for h in s["heroes"]] + [k["id"] for k in s["skins"]]


def pick_ids(arg):
    ids = all_ids()
    if not arg or arg == "all":
        return ids
    chosen = arg.split(",")
    unknown = [i for i in chosen if i not in ids]
    if unknown:
        sys.exit("unknown id: " + ", ".join(unknown))
    return chosen


def raw_dirs():
    dirs = [ROOT / "build" / "portraits", FOUND]
    dirs += [Path(p) for p in os.environ.get("SPLASH_RAW_DIRS", "").split(":") if p]
    return [d for d in dirs if d.is_dir()]


def app_portrait(sid):
    for folder in PORTRAIT_FOLDERS:
        p = ASSETS / folder / f"{sid}.imageset" / f"{sid}.jpg"
        if p.exists():
            return p
    sys.exit(f"no app portrait for {sid}")


def ffmpeg(*args):
    return subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *args],
                          check=True, capture_output=True, text=True)


# ---- 元画像 ----

def ssim(app_jpg, raw_png):
    """原画（黒地へ合成）とアプリ内 JPEG の ssim（0…1）。どちらも SSIM_PIXELS に縮めて比べる。"""
    n = SSIM_PIXELS
    graph = f"[1:v]{FLATTEN},scale={n}:{n}:flags=area[b];[0:v]scale={n}:{n}:flags=area,format=rgb24[a];[a][b]ssim"
    proc = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(app_jpg), "-i", str(raw_png),
                           "-filter_complex", graph, "-frames:v", "1", "-f", "null", "-"],
                          capture_output=True, text=True)
    m = re.search(r"All:([0-9.]+)", proc.stderr)
    return float(m.group(1)) if m else 0.0


def choose_source(sid):
    """(種類, パス, ssim)。種類は raw = 採用版の原画 / candidate = 候補の原画 / upscale = アプリ内 JPEG の拡大。"""
    app = app_portrait(sid)
    best = 0.0
    for d in raw_dirs():  # まず採用版（<ID>.png）
        p = d / f"{sid}.png"
        if p.exists():
            v = ssim(app, p)
            if v >= SSIM_MATCH:
                return "raw", p, v
            best = max(best, v)
    for d in raw_dirs():  # 採用版が別の絵なら、候補から同じ絵を探す
        for p in sorted(d.glob(f"{sid}_*.png")):
            v = ssim(app, p)
            if v >= SSIM_MATCH:
                return "candidate", p, v
            best = max(best, v)
    return "upscale", app, best


def prepare(sid):
    kind, path, value = choose_source(sid)
    out = FLAT / f"{sid}.png"
    if kind == "upscale":
        n = SPLASH_PIXELS
        ffmpeg("-i", str(path), "-vf", f"scale={n}:{n}:flags=lanczos,format=rgb24", "-frames:v", "1", str(out))
    else:
        # 生成画像は縁が半透明のことがある。JPEG 化は透明部を白で埋めるので、先に黒地へ合成する（portraits.py の install と同じ）
        ffmpeg("-i", str(path), "-filter_complex", f"[0:v]{FLATTEN}", "-frames:v", "1", str(out))
    return sid, {"kind": kind, "path": str(path), "ssim": round(value, 4)}


def sources():
    FLAT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(JOBS) as pool:
        result = dict(pool.map(prepare, all_ids()))
    SOURCES.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    for sid, r in result.items():
        print(f"{sid}\t{r['kind']}\t{r['ssim']:.4f}\t{r['path']}")
    odd = [sid for sid, r in result.items() if r["kind"] != "raw"]
    print(f"{len(result)} sources ({len(odd)} not from a selected raw: {', '.join(odd) or '-'})")
    upscaled = [sid for sid, r in result.items() if r["kind"] == "upscale"]
    if upscaled:  # ssim は見つかった原画のうち最も近いものの値（別の絵なので使っていない）
        print("warning: no matching raw image, upscaled the 640px app portrait: " + ", ".join(upscaled), file=sys.stderr)


def find(sid, folder):
    """folder 以下の *.png からアプリ内ポートレートと同じ絵を探し、build/splash/raw/<ID>.png へコピーする。"""
    app = app_portrait(sid)
    files = sorted(Path(folder).expanduser().rglob("*.png"))
    if not files:
        sys.exit(f"no png under {folder}")
    with ThreadPoolExecutor(JOBS) as pool:
        scores = list(pool.map(lambda p: ssim(app, p), files))
    value, path = max(zip(scores, files), key=lambda t: t[0])
    if value < SSIM_MATCH:
        sys.exit(f"[{sid}] no match in {len(files)} files (best {value:.4f}: {path})")
    FOUND.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, FOUND / f"{sid}.png")
    print(f"{sid}\t{value:.4f}\t{path} -> {FOUND / f'{sid}.png'}")


def need_flat(ids):
    missing = [i for i in ids if not (FLAT / f"{i}.png").exists()]
    if missing:
        sys.exit("missing flattened images (run `sources` first): " + ", ".join(missing))


# ---- マスク ----

def matte_tool():
    """matte.swift をビルドして返す（ソースより新しい実行ファイルがあれば使い回す）。"""
    tool = WORK / "matte-tool"
    if not tool.exists() or tool.stat().st_mtime < MATTE_SWIFT.stat().st_mtime:
        WORK.mkdir(parents=True, exist_ok=True)
        subprocess.run(["xcrun", "swiftc", "-O", str(MATTE_SWIFT), "-o", str(tool)], check=True)
    return tool


def vision(jobs, out_dir):
    """jobs = [(名前, 絵, 余白 | None)]。out_dir/<名前>.png に 512px のマスクを書き、作れた名前の一覧を返す。

    余白つきの入力は out_dir/.in/、Vision の出力そのまま（入力と同じ大きさ）は out_dir/.raw/ に置く。
    """
    stage, raw = out_dir / ".in", out_dir / ".raw"
    for d in (stage, raw):
        d.mkdir(parents=True, exist_ok=True)
    crops = {}

    def stage_one(job):
        name, art, pad = job
        for stale in (raw / f"{name}.png", out_dir / f"{name}.png"):
            stale.unlink(missing_ok=True)
        if pad is None:
            shutil.copyfile(art, stage / f"{name}.png")
            crops[name] = ""
            return
        margin, color = pad
        inner, canvas = MATTE_CANVAS - 2 * margin, MATTE_CANVAS
        ffmpeg("-i", str(art), "-vf",
               f"scale={inner}:{inner}:flags=area,pad={canvas}:{canvas}:{margin}:{margin}:{color}",
               "-frames:v", "1", str(stage / f"{name}.png"))
        crops[name] = f"crop={inner}:{inner}:{margin}:{margin},"

    with ThreadPoolExecutor(JOBS) as pool:
        list(pool.map(stage_one, jobs))
    # swift の起動は重いので、全画像を 1 回の起動で処理する
    proc = subprocess.run([str(matte_tool()), str(raw)] + [str(stage / f"{name}.png") for name, _, _ in jobs],
                          capture_output=True, text=True)
    print(proc.stdout, end="")
    if proc.returncode not in (0, 1):  # 1 = 一部の画像で失敗（行ごとの状態を見る）
        sys.exit(f"matte tool failed (Vision が使えない環境?): {proc.stderr.strip()}")
    made = [name for name, _, _ in jobs if (raw / f"{name}.png").exists()]

    def soften(name):
        n = MATTE_PIXELS
        ffmpeg("-i", str(raw / f"{name}.png"), "-vf",
               f"{crops[name]}scale={n}:{n}:flags=area,gblur=sigma={MATTE_BLUR},format=gray",
               "-frames:v", "1", "-compression_level", "9", "-pred", "mixed", str(out_dir / f"{name}.png"))

    with ThreadPoolExecutor(JOBS) as pool:
        list(pool.map(soften, made))
    return made


def matte(ids):
    need_flat(ids)
    made = vision([(i, FLAT / f"{i}.png", MATTE_PAD.get(i)) for i in ids], MATTE)
    lacking = [i for i in ids if i not in made]
    print(f"{len(made)} mattes" + (f" (no matte: {', '.join(lacking)})" if lacking else ""))


def pad_label(pad):
    return "余白なし" if pad is None else f"{pad[0]}px {pad[1]}"


def variants(ids):
    """ID ごとに「原画 + VARIANT_PADS の各候補」を 3 列で並べた build/splash/variants_<ID>.png を作る。"""
    need_flat(ids)
    jobs = [(f"{i}@{n}", FLAT / f"{i}.png", pad) for i in ids for n, pad in enumerate(VARIANT_PADS)]
    made = set(vision(jobs, VARIANT))
    for i in ids:
        tiles = [(FLAT / f"{i}.png", None)]
        for n in range(len(VARIANT_PADS)):
            tiles.append((FLAT / f"{i}.png", VARIANT / f"{i}@{n}.png" if f"{i}@{n}" in made else ""))
        out = WORK / f"variants_{i}.png"
        grid(out, tiles, cols=3, cell=400)
        print(out)
    labels = ["原画"] + [pad_label(p) for p in VARIANT_PADS]
    for r in range(0, len(labels), 3):
        print("   " + " | ".join(labels[r:r + 3]))


# ---- 確認用の一覧 ----

def grid(out, tiles, cols, cell):
    """tiles = [(絵, マスク)] を cols 列で並べる。マスクが None なら絵そのまま、あれば絵 × マスクをマゼンタ地に合成、
    "" なら（マスクなし）マゼンタだけ。"""
    args, chains, k = [], [], 0
    for n, (art, mask) in enumerate(tiles):
        args += ["-i", str(art)]
        a, k = k, k + 1
        if mask is None:
            chains.append(f"[{a}:v]scale={cell}:{cell},format=rgb24[x{n}]")
            continue
        args += ["-i", str(mask)] if mask else ["-f", "lavfi", "-i", f"color=c=black:s={cell}x{cell}"]
        m, k = k, k + 1
        chains += [f"[{a}:v]scale={cell}:{cell},format=rgb24[p{n}]",
                   f"[{m}:v]scale={cell}:{cell},format=gray[m{n}]",
                   f"[p{n}][m{n}]alphamerge[f{n}]",
                   f"color=c=magenta:s={cell}x{cell},format=rgb24[g{n}]",
                   f"[g{n}][f{n}]overlay=format=auto:shortest=1,format=rgb24[x{n}]"]
    if len(tiles) == 1:
        graph = ";".join(chains) + ";[x0]null[out]"
    else:
        layout = "|".join(f"{(n % cols) * cell}_{(n // cols) * cell}" for n in range(len(tiles)))
        names = "".join(f"[x{n}]" for n in range(len(tiles)))
        graph = ";".join(chains) + f";{names}xstack=inputs={len(tiles)}:layout={layout}:fill=black[out]"
    ffmpeg(*args, "-filter_complex", graph, "-map", "[out]", "-frames:v", "1", str(out))


def sheet(ids, cell=300):
    """左 = 原画、右 = 原画 × マスクをマゼンタ地に合成、の組を並べた build/splash/sheet_N.png（1 枚は約 1800×900px）。"""
    need_flat(ids)
    cols, rows = max(1, 1800 // (2 * cell)), max(1, 900 // cell)
    for old in WORK.glob("sheet_*.png"):
        old.unlink()
    for page, start in enumerate(range(0, len(ids), cols * rows), 1):
        chunk = ids[start:start + cols * rows]
        tiles = []
        for sid in chunk:
            m = MATTE / f"{sid}.png"
            tiles += [(FLAT / f"{sid}.png", None), (FLAT / f"{sid}.png", m if m.exists() else "")]
        out = WORK / f"sheet_{page}.png"
        grid(out, tiles, cols=cols * 2, cell=cell)
        print(out)
        for r in range(0, len(chunk), cols):
            print("   " + "  ".join(s + ("（NO_MATTE）" if s in NO_MATTE else "") for s in chunk[r:r + cols]))


# ---- 取り込み ----

def write_json(path, obj):
    path.write_text(json.dumps(obj, indent=2) + "\n")


def install():
    ids = all_ids()
    need_flat(ids)
    namespace = {"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": True}}
    for folder in (SPLASH_FOLDER, MATTE_FOLDER):
        base = ASSETS / folder
        if base.exists():
            shutil.rmtree(base)
        base.mkdir(parents=True)
        write_json(base / "Contents.json", namespace)

    def imageset(folder, sid, ext):
        d = ASSETS / folder / f"{sid}.imageset"
        d.mkdir()
        write_json(d / "Contents.json", {
            "images": [{"filename": f"{sid}.{ext}", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        })
        return d / f"{sid}.{ext}"

    def splash(sid):
        n = SPLASH_PIXELS
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(JPEG_QUALITY), "-z", str(n), str(n),
                        str(FLAT / f"{sid}.png"), "--out", str(imageset(SPLASH_FOLDER, sid, "jpg"))],
                       check=True, capture_output=True)

    with ThreadPoolExecutor(JOBS) as pool:
        list(pool.map(splash, ids))
    skipped = []
    for sid in ids:
        src = MATTE / f"{sid}.png"
        if sid in NO_MATTE or not src.exists():
            skipped.append(sid)
            continue
        shutil.copyfile(src, imageset(MATTE_FOLDER, sid, "png"))
    for folder, ext in ((SPLASH_FOLDER, "jpg"), (MATTE_FOLDER, "png")):
        sizes = [p.stat().st_size for p in (ASSETS / folder).glob(f"*.imageset/*.{ext}")]
        if sizes:
            print(f"{folder}: {len(sizes)} images, {sum(sizes) / 1024:.0f} KB "
                  f"(min {min(sizes) / 1024:.0f} / max {max(sizes) / 1024:.0f} KB)")
        else:
            print(f"{folder}: 0 images")
    if skipped:
        print("no matte: " + ", ".join(skipped))


def main(argv):
    if len(argv) < 2 or any(a.startswith("-") for a in argv[1:]):
        sys.exit(__doc__)
    cmd, rest = argv[1], argv[2:]
    if cmd == "find" and len(rest) == 2:
        pick_ids(rest[0])
        find(rest[0], rest[1])
    elif cmd == "sources" and not rest:
        sources()
    elif cmd == "matte" and len(rest) <= 1:
        matte(pick_ids(rest[0] if rest else None))
    elif cmd == "sheet" and len(rest) <= 2:
        sheet(pick_ids(rest[0] if rest else None), cell=int(rest[1]) if len(rest) > 1 else 300)
    elif cmd == "variants" and len(rest) == 1:
        variants(pick_ids(rest[0]))
    elif cmd == "install" and not rest:
        install()
    elif cmd == "all" and not rest:
        sources()
        matte(all_ids())
        sheet(all_ids())
        install()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
