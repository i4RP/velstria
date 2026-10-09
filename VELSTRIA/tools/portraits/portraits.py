#!/usr/bin/env python3
"""ヒーロー / スキンのポートレートと装備アイコンの画像の生成と取り込み。

仕様（画風・各ヒーローの造形）は tools/portraits/portraits.json。造形は
App/Battle/Heroes/HeroBlueprints.swift（3D モデル）に合わせてある。
装備アイコン（EQ101〜EQ408）の仕様は tools/portraits/item_icons.json（画風・Tier 別の格・カテゴリ別の色・各装備の造形）。

  python3 tools/portraits/portraits.py prompt H001          # 生成プロンプトを表示
  python3 tools/portraits/portraits.py generate H001 [--extra "..."] [--tag a2]
  python3 tools/portraits/portraits.py select H001 a2       # 候補 H001_a2.png を採用版 H001.png にする
  python3 tools/portraits/portraits.py install [heroes,skins,items]  # 採用版を Assets.xcassets へ（JPEG、既定は全部）
  python3 tools/portraits/portraits.py sheet out.png [ID,ID,...|all|items] [セル px]  # 一覧画像（確認用）

生成は Codex CLI（ChatGPT ログイン）の画像生成ツールを使う。API キーは不要。
元画像（約 1254px PNG）は build/portraits/（git 管理外）に置き、アプリには縮小版だけを入れる。
同時実行数は環境変数 PORTRAIT_SLOTS（既定 4）で制限する。Codex のモデルは PORTRAIT_CODEX_MODEL
（既定 gpt-6-astra。~/.codex/config.toml の既定モデルに左右されないよう明示する）。

macOS と Windows の両方で動く。JPEG 化は macOS では従来どおり ffmpeg（黒地へ合成）+ sips、sips の無い OS では
Pillow（python -m pip install Pillow）。一覧画像は ffmpeg があれば ffmpeg、無ければ Pillow。
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

try:
    import fcntl  # macOS / Linux
except ImportError:  # Windows
    fcntl = None
    import msvcrt

ROOT = Path(__file__).resolve().parents[2]  # VELSTRIA/
SPEC = Path(__file__).with_name("portraits.json")
ITEM_SPEC = Path(__file__).with_name("item_icons.json")
RAW = ROOT / "build" / "portraits"
ASSETS = ROOT / "App" / "Resources" / "Assets.xcassets"
HERO_FOLDER = "HeroPortraits"
SKIN_FOLDER = "SkinPortraits"
ITEM_FOLDER = "ItemIcons"
PIXELS = 640
ITEM_PIXELS = 384  # 最大表示 70pt × 3x = 210px に余裕を持たせる
JPEG_QUALITY = 82


def spec():
    return json.loads(SPEC.read_text(encoding="utf-8"))


def item_spec():
    return json.loads(ITEM_SPEC.read_text(encoding="utf-8"))


def entry(sid):
    s = spec()
    for h in s["heroes"]:
        if h["id"] == sid:
            return s, h, False
    for k in s["skins"]:
        if k["id"] == sid:
            return s, k, True
    sys.exit(f"unknown id: {sid}")


def item_entry(sid):
    s = item_spec()
    for it in s["items"]:
        if it["id"] == sid:
            return s, it
    return None


def build_item_prompt(s, it):
    cat = s["categories"][it["category"]]
    return (s["style"].format(background=cat["background"])
            + "\n\n" + s["tiers"][str(it["tier"])]
            + "\n\n" + cat["accent"]
            + f"\n\nItem '{it['name']}': {it['description']}")


def build_prompt(sid, extra=""):
    found = item_entry(sid)
    if found:
        text = build_item_prompt(*found)
        if extra:
            text += "\n\nAdditional direction: " + extra
        return text
    s, e, is_skin = entry(sid)
    if is_skin:
        _, hero, _ = entry(e["hero"])
        text = (s["skin_style"].format(background=e["background"])
                + f"\n\nCharacter (base design, for reference): {hero['description']}"
                + f"\n\nAlternate skin '{e['name']}': {e['description']}")
    else:
        text = s["style"].format(background=e["background"]) + "\n\nCharacter: " + e["description"]
    if extra:
        text += "\n\nAdditional direction: " + extra
    return text


class Slot:
    """PORTRAIT_SLOTS 個のロックファイルで同時生成数を制限する。

    macOS / Linux は flock、Windows は msvcrt.locking（先頭 1 バイトのロック）。どちらもプロセスが
    落ちれば OS がロックを外すので、ロックファイルが残っても詰まらない。
    """

    def __init__(self):
        self.n = max(1, int(os.environ.get("PORTRAIT_SLOTS", "4")))
        self.fd = None

    @staticmethod
    def _lock(fd):
        if fcntl:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        else:
            fd.seek(0)
            msvcrt.locking(fd.fileno(), msvcrt.LK_NBLCK, 1)

    @staticmethod
    def _unlock(fd):
        if fcntl:
            fcntl.flock(fd, fcntl.LOCK_UN)
        else:
            fd.seek(0)
            msvcrt.locking(fd.fileno(), msvcrt.LK_UNLCK, 1)

    def __enter__(self):
        lock_dir = RAW / ".slots"
        lock_dir.mkdir(parents=True, exist_ok=True)
        while True:
            for i in range(self.n):
                fd = open(lock_dir / f"slot{i}", "a+")  # "w" だと他プロセスがロック中のファイルを切り詰めにいく
                try:
                    self._lock(fd)
                    self.fd = fd
                    return self
                except OSError:  # flock は BlockingIOError、msvcrt は PermissionError
                    fd.close()
            time.sleep(2)

    def __exit__(self, *exc):
        self._unlock(self.fd)
        self.fd.close()


def generate(sid, extra="", tag=None, attempts=3):
    if item_entry(sid):
        e, is_skin = None, False
    else:
        _, e, is_skin = entry(sid)
    RAW.mkdir(parents=True, exist_ok=True)
    out = RAW / (f"{sid}_{tag}.png" if tag else f"{sid}.png")
    prompt = build_prompt(sid, extra)
    ref = RAW / f"{e['hero']}.png" if is_skin else None
    if ref is not None and not ref.exists():
        sys.exit(f"reference portrait missing: {ref} (generate and select {e['hero']} first)")
    instruction = (
        "Use your built-in image generation tool to create exactly ONE image from the prompt below"
        + (" (the attached image is the identity reference)" if ref else "")
        + f". When it is done, copy the generated PNG file to {out} (overwrite if it exists)."
        " Do not modify the image and do not create any other files. Reply only with the output path."
        "\n\n=== IMAGE PROMPT ===\n" + prompt
    )
    # 作業ディレクトリは固定（Codex は -C の場所を ~/.codex/config.toml の trusted に登録するため、毎回別だと増え続ける）
    work = RAW / ".codex-work"
    work.mkdir(parents=True, exist_ok=True)
    for attempt in range(1, attempts + 1):
        if out.exists():
            out.unlink()
        with Slot():
            # Windows の npm 版は codex.cmd なので、PATHEXT を見る shutil.which で実体を引く
            cmd = [shutil.which("codex") or "codex", "exec", "--skip-git-repo-check", "--ephemeral",
                   "--dangerously-bypass-approvals-and-sandbox",
                   "-m", os.environ.get("PORTRAIT_CODEX_MODEL", "gpt-6-astra"),
                   "-c", 'model_reasoning_effort="low"', "-C", str(work)]
            if ref is not None:
                cmd += ["-i", str(ref)]
            # -i は複数値を取るのでプロンプトは stdin で渡す
            try:
                proc = subprocess.run(cmd, input=instruction, capture_output=True, text=True,
                                      encoding="utf-8", errors="replace", timeout=900)
                tail = f"exit {proc.returncode}: " + (proc.stdout + proc.stderr)[-800:]
            except subprocess.TimeoutExpired:
                tail = "timed out"
        data = out.read_bytes() if out.exists() else b""
        if data[:8] == b"\x89PNG\r\n\x1a\n" and (ref is None or data != ref.read_bytes()):
            print(out)
            return out
        print(f"[{sid}] attempt {attempt} failed ({tail})", file=sys.stderr)
        time.sleep(5 * attempt)
    sys.exit(f"[{sid}] generation failed")


def select(sid, tag):
    src = RAW / f"{sid}_{tag}.png"
    if not src.exists():
        sys.exit(f"missing candidate: {src}")
    shutil.copyfile(src, RAW / f"{sid}.png")
    print(RAW / f"{sid}.png")


def write_json(path, obj):
    path.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def to_jpeg(src, dst, pixels):
    """src を pixels 四方に縮小し、品質 JPEG_QUALITY の JPEG にする。

    生成画像は縁が半透明のことがある。JPEG 化で透明部が白く埋まらないよう、先に黒地へ合成する。
    macOS は従来どおり ffmpeg（合成）+ sips、sips の無い OS（Windows など）は Pillow。
    """
    if shutil.which("sips") and shutil.which("ffmpeg"):
        flat = RAW / ".flat.png"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-filter_complex",
                        "[0:v]split[a][b];[a]format=rgb24,drawbox=c=black:t=fill[bg];[bg][b]overlay=format=auto,format=rgb24",
                        "-frames:v", "1", str(flat)], check=True, capture_output=True)
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(JPEG_QUALITY),
                        "-z", str(pixels), str(pixels), str(flat), "--out", str(dst)],
                       check=True, capture_output=True)
        flat.unlink()
        return
    try:
        from PIL import Image
    except ImportError:
        sys.exit("JPEG conversion needs sips + ffmpeg (macOS) or Pillow (python -m pip install Pillow)")
    with Image.open(src) as im:
        im = im.convert("RGBA")
        flat = Image.new("RGB", im.size, (0, 0, 0))
        flat.paste(im, mask=im.getchannel("A"))
        flat.resize((pixels, pixels), Image.LANCZOS).save(dst, "JPEG", quality=JPEG_QUALITY, optimize=True)


def install(names=("heroes", "skins", "items")):
    s = spec()
    all_groups = {
        "heroes": (HERO_FOLDER, [h["id"] for h in s["heroes"]], PIXELS),
        "skins": (SKIN_FOLDER, [k["id"] for k in s["skins"]], PIXELS),
        "items": (ITEM_FOLDER, [it["id"] for it in item_spec()["items"]], ITEM_PIXELS),
    }
    unknown = [n for n in names if n not in all_groups]
    if unknown:
        sys.exit("unknown group: " + ", ".join(unknown))
    groups = [all_groups[n] for n in names]
    missing = [i for _, ids, _ in groups for i in ids if not (RAW / f"{i}.png").exists()]
    if missing:
        sys.exit("missing raw images: " + ", ".join(missing))
    for folder, ids, pixels in groups:
        base = ASSETS / folder
        if base.exists():
            shutil.rmtree(base)
        base.mkdir(parents=True)
        write_json(base / "Contents.json",
                   {"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": True}})
        for i in ids:
            d = base / f"{i}.imageset"
            d.mkdir()
            to_jpeg(RAW / f"{i}.png", d / f"{i}.jpg", pixels)
            write_json(d / "Contents.json", {
                "images": [{"filename": f"{i}.jpg", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            })
    total = sum(p.stat().st_size for folder, _, _ in groups for p in (ASSETS / folder).glob("*.imageset/*.jpg"))
    print(f"installed {sum(len(ids) for _, ids, _ in groups)} images ({total / 1024:.0f} KB)")


def sheet(out, ids=None, cols=6, cell=256):
    if ids == ["items"]:
        ids = [it["id"] for it in item_spec()["items"]]
    s = spec()
    ids = ids or [h["id"] for h in s["heroes"]] + [k["id"] for k in s["skins"]]
    missing = [i for i in ids if not (RAW / f"{i}.png").exists()]
    if missing:
        print("warning: no raw portrait for " + ", ".join(missing), file=sys.stderr)
    files = [RAW / f"{i}.png" for i in ids if i not in missing]
    if not files:
        sys.exit("no portraits")
    cols = min(cols, len(files))
    rows = (len(files) + cols - 1) // cols
    if not shutil.which("ffmpeg"):
        from PIL import Image
        board = Image.new("RGB", (cols * cell, rows * cell), (0, 0, 0))
        for n, f in enumerate(files):
            with Image.open(f) as im:
                board.paste(im.convert("RGB").resize((cell, cell), Image.LANCZOS),
                            ((n % cols) * cell, (n // cols) * cell))
        board.save(out)
        print(f"{out} ({len(files)} portraits, {cols}x{rows})")
        return
    args = ["ffmpeg", "-y", "-loglevel", "error"]
    for f in files:
        args += ["-i", str(f)]
    chains = [f"[{n}:v]scale={cell}:{cell}[v{n}]" for n in range(len(files))]
    layout = "|".join(f"{(n % cols) * cell}_{(n // cols) * cell}" for n in range(len(files)))
    inputs = "".join(f"[v{n}]" for n in range(len(files)))
    graph = ";".join(chains) + f";{inputs}xstack=inputs={len(files)}:layout={layout}:fill=black[out]"
    if len(files) == 1:
        graph = f"[0:v]scale={cell}:{cell}[out]"
    subprocess.run(args + ["-filter_complex", graph, "-map", "[out]", "-frames:v", "1", str(out)], check=True)
    print(f"{out} ({len(files)} portraits, {cols}x{rows})")


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):  # Windows の既定（cp932）で表示できない記号があっても落ちないように
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd = argv[1]
    flags = [a for a in argv[2:] if a.startswith("-")]
    unknown = [a for a in flags if a not in ("--extra", "--tag")]
    if unknown or (cmd != "generate" and flags):
        sys.exit(f"unknown option: {' '.join(unknown or flags)}\n{__doc__}")
    if cmd == "prompt":
        print(build_prompt(argv[2]))
    elif cmd == "generate":
        sid = argv[2]
        extra = argv[argv.index("--extra") + 1] if "--extra" in argv else ""
        tag = argv[argv.index("--tag") + 1] if "--tag" in argv else None
        generate(sid, extra, tag)
    elif cmd == "select":
        select(argv[2], argv[3])
    elif cmd == "install":
        install(tuple(argv[2].split(",")) if len(argv) > 2 else ("heroes", "skins", "items"))
    elif cmd == "sheet":
        out = argv[2] if len(argv) > 2 else str(RAW / "sheet.png")
        ids = argv[3].split(",") if len(argv) > 3 and argv[3] != "all" else None
        cell = int(argv[4]) if len(argv) > 4 else 256
        sheet(out, ids, cell=cell)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
