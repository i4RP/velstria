#!/usr/bin/env python3
"""ヒーロー / スキンのポートレート画像の生成と取り込み。

仕様（画風・各ヒーローの造形）は tools/portraits/portraits.json。造形は
App/Battle/Heroes/HeroBlueprints.swift（3D モデル）に合わせてある。

  python3 tools/portraits/portraits.py prompt H001          # 生成プロンプトを表示
  python3 tools/portraits/portraits.py generate H001 [--extra "..."] [--tag a2]
  python3 tools/portraits/portraits.py select H001 a2       # 候補 H001_a2.png を採用版 H001.png にする
  python3 tools/portraits/portraits.py install              # 採用版を Assets.xcassets へ（640px JPEG）
  python3 tools/portraits/portraits.py sheet out.png [ID,ID,...|all] [セル px]  # 一覧画像（確認用）

生成は Codex CLI（ChatGPT ログイン）の画像生成ツールを使う。API キーは不要。
元画像（約 1254px PNG）は build/portraits/（git 管理外）に置き、アプリには縮小版だけを入れる。
同時実行数は環境変数 PORTRAIT_SLOTS（既定 4）で制限する。Codex のモデルは PORTRAIT_CODEX_MODEL
（既定 gpt-6-astra。~/.codex/config.toml の既定モデルに左右されないよう明示する）。
"""
import fcntl
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # VELSTRIA/
SPEC = Path(__file__).with_name("portraits.json")
RAW = ROOT / "build" / "portraits"
ASSETS = ROOT / "App" / "Resources" / "Assets.xcassets"
HERO_FOLDER = "HeroPortraits"
SKIN_FOLDER = "SkinPortraits"
PIXELS = 640
JPEG_QUALITY = 82


def spec():
    return json.loads(SPEC.read_text())


def entry(sid):
    s = spec()
    for h in s["heroes"]:
        if h["id"] == sid:
            return s, h, False
    for k in s["skins"]:
        if k["id"] == sid:
            return s, k, True
    sys.exit(f"unknown id: {sid}")


def build_prompt(sid, extra=""):
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
    """PORTRAIT_SLOTS 個のロックファイルで同時生成数を制限する。"""

    def __init__(self):
        self.n = max(1, int(os.environ.get("PORTRAIT_SLOTS", "4")))
        self.fd = None

    def __enter__(self):
        lock_dir = RAW / ".slots"
        lock_dir.mkdir(parents=True, exist_ok=True)
        while True:
            for i in range(self.n):
                fd = open(lock_dir / f"slot{i}", "w")
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    self.fd = fd
                    return self
                except BlockingIOError:
                    fd.close()
            time.sleep(2)

    def __exit__(self, *exc):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        self.fd.close()


def generate(sid, extra="", tag=None, attempts=3):
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
            cmd = ["codex", "exec", "--skip-git-repo-check", "--ephemeral",
                   "--dangerously-bypass-approvals-and-sandbox",
                   "-m", os.environ.get("PORTRAIT_CODEX_MODEL", "gpt-6-astra"),
                   "-c", 'model_reasoning_effort="low"', "-C", str(work)]
            if ref is not None:
                cmd += ["-i", str(ref)]
            # -i は複数値を取るのでプロンプトは stdin で渡す
            try:
                proc = subprocess.run(cmd, input=instruction, capture_output=True, text=True, timeout=900)
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
    path.write_text(json.dumps(obj, indent=2) + "\n")


def install():
    s = spec()
    groups = [(HERO_FOLDER, [h["id"] for h in s["heroes"]]), (SKIN_FOLDER, [k["id"] for k in s["skins"]])]
    missing = [i for _, ids in groups for i in ids if not (RAW / f"{i}.png").exists()]
    if missing:
        sys.exit("missing raw portraits: " + ", ".join(missing))
    for folder, ids in groups:
        base = ASSETS / folder
        if base.exists():
            shutil.rmtree(base)
        base.mkdir(parents=True)
        write_json(base / "Contents.json",
                   {"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": True}})
        for i in ids:
            d = base / f"{i}.imageset"
            d.mkdir()
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(JPEG_QUALITY),
                            "-z", str(PIXELS), str(PIXELS), str(RAW / f"{i}.png"), "--out", str(d / f"{i}.jpg")],
                           check=True, capture_output=True)
            write_json(d / "Contents.json", {
                "images": [{"filename": f"{i}.jpg", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            })
    total = sum(p.stat().st_size for p in ASSETS.glob("*Portraits/*.imageset/*.jpg"))
    print(f"installed {sum(len(ids) for _, ids in groups)} portraits ({total / 1024:.0f} KB)")


def sheet(out, ids=None, cols=6, cell=256):
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
        install()
    elif cmd == "sheet":
        out = argv[2] if len(argv) > 2 else str(RAW / "sheet.png")
        ids = argv[3].split(",") if len(argv) > 3 and argv[3] != "all" else None
        cell = int(argv[4]) if len(argv) > 4 else 256
        sheet(out, ids, cell=cell)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
