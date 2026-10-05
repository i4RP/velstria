#!/usr/bin/env python3
"""ヒーローのポートレートから、3D 生成の入力にする全身 T ポーズの参照画像を作る（Codex CLI の画像生成）。

  python3 tools/heroref/fullbody.py prompt H004
  python3 tools/heroref/fullbody.py generate H004 H010 --tag t1        # all で 24 体
  python3 tools/heroref/fullbody.py select H004 t1                     # 採用版 build/heroref/H004/fullbody.png
  python3 tools/heroref/fullbody.py sheet --tag t1                     # 一覧 build/heroref/sheet_t1.png

- 仕様は tools/heroref/fullbody.json（共通の template ＋ ヒーロー別の keep / costume / wear / remove）。
- 参照画像は原寸のポートレート（$HEROREF_PORTRAITS/<ID>.png → build/portraits/<ID>.png の順）、無ければアプリ内の 640px JPEG。
- 出力は build/heroref/<ID>/fullbody_<tag>.png（git 管理外）。採用版 fullbody.png を tools/tripo.mjs が concept として使う。
- Codex は ChatGPT ログインで動かす（API キー不要）。-i は複数値を取るのでプロンプトは stdin で渡す。モデルは -m で明示する。
  -C の作業ディレクトリは固定（毎回変えると ~/.codex/config.toml の trusted が増え続ける）。
"""
import argparse
import concurrent.futures as cf
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # VELSTRIA/
SPEC = Path(__file__).with_name("fullbody.json")
OUT = Path(os.environ.get("HEROREF_BUILD_DIR", ROOT / "build" / "heroref"))
WORK = Path(os.environ.get("HEROREF_CODEX_WORK", Path.home() / ".cache" / "velstria-heroref" / "codex-work"))
MODEL = os.environ.get("HEROREF_CODEX_MODEL", "gpt-6-astra")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def spec():
    return json.loads(SPEC.read_text())


def hero(sid):
    for h in spec()["heroes"]:
        if h["id"] == sid:
            return h
    sys.exit(f"unknown hero: {sid}")


def all_ids():
    return [h["id"] for h in spec()["heroes"]]


def portrait(sid):
    cands = []
    if os.environ.get("HEROREF_PORTRAITS"):
        cands.append(Path(os.environ["HEROREF_PORTRAITS"]) / f"{sid}.png")
    cands += [ROOT / "build" / "portraits" / f"{sid}.png",
              ROOT / "App" / "Resources" / "Assets.xcassets" / "HeroPortraits" / f"{sid}.imageset" / f"{sid}.jpg"]
    for c in cands:
        if c.exists():
            return c
    sys.exit(f"portrait missing for {sid}: " + ", ".join(map(str, cands)))


def build_prompt(sid, extra=""):
    h = hero(sid)
    text = "\n".join(spec()["template"]).format(**{k: h[k] for k in ("keep", "costume", "wear", "remove")})
    if extra:
        text += "\nAdditional direction: " + extra
    return text


def generate_one(sid, tag, extra="", attempts=3):
    out = OUT / sid / f"fullbody_{tag}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    ref = portrait(sid)
    instruction = (
        "Use your built-in image generation tool to create exactly ONE image from the prompt below"
        " (the attached image is the identity and costume reference)."
        f" When it is done, copy the generated PNG file to {out} (overwrite if it exists)."
        " Do not modify the image and do not create any other files. Reply only with the output path."
        "\n\n=== IMAGE PROMPT ===\n" + build_prompt(sid, extra))
    WORK.mkdir(parents=True, exist_ok=True)
    tail = ""
    for attempt in range(1, attempts + 1):
        if out.exists():
            out.unlink()
        cmd = ["codex", "exec", "--skip-git-repo-check", "--ephemeral", "--dangerously-bypass-approvals-and-sandbox",
               "-m", MODEL, "-c", 'model_reasoning_effort="low"', "-C", str(WORK), "-i", str(ref)]
        t0 = time.time()
        try:
            proc = subprocess.run(cmd, input=instruction, capture_output=True, text=True, timeout=900)
            tail = f"exit {proc.returncode}: " + (proc.stdout + proc.stderr)[-600:]
        except subprocess.TimeoutExpired:
            tail = "timed out"
        data = out.read_bytes() if out.exists() else b""
        if data[:8] == PNG_MAGIC and data != ref.read_bytes():
            print(f"[{sid}] {out} ({time.time() - t0:.0f}s)", flush=True)
            return out
        print(f"[{sid}] attempt {attempt} failed ({tail})", file=sys.stderr, flush=True)
        time.sleep(5 * attempt)
    print(f"[{sid}] generation failed", file=sys.stderr, flush=True)
    return None


def cmd_generate(a):
    ids = all_ids() if a.ids == ["all"] else a.ids
    for i in ids:
        hero(i), portrait(i)
    with cf.ThreadPoolExecutor(max(1, a.slots)) as ex:
        results = list(ex.map(lambda i: generate_one(i, a.tag, a.extra), ids))
    failed = [i for i, r in zip(ids, results) if r is None]
    if failed:
        sys.exit("failed: " + " ".join(failed))


def cmd_select(a):
    src = OUT / a.id / f"fullbody_{a.tag}.png"
    if not src.exists():
        sys.exit(f"missing candidate: {src}")
    dst = OUT / a.id / "fullbody.png"
    shutil.copyfile(src, dst)
    (OUT / a.id / "fullbody.source").write_text(a.tag + "\n")
    print(dst)


def cmd_sheet(a):
    ids = a.ids or all_ids()
    name = "fullbody.png" if a.tag in (None, "selected") else f"fullbody_{a.tag}.png"
    files = [OUT / i / name for i in ids if (OUT / i / name).exists()]
    if not files:
        sys.exit("no images")
    cols = min(len(files), a.cols)
    rows = (len(files) + cols - 1) // cols
    out = OUT / f"sheet_{a.tag or 'selected'}.png"
    # 画像ごとに縮小して xstack で格子に並べる（image2 の連番 + tile は画素形式の違う PNG が混ざると崩れる）
    inputs, chains, labels, layout = [], [], [], []
    for k, f in enumerate(files):
        inputs += ["-i", str(f)]
        chains.append(f"[{k}:v]scale={a.size}:{a.size},format=rgb24[v{k}]")
        labels.append(f"[v{k}]")
        layout.append(f"{(k % cols) * a.size}_{(k // cols) * a.size}")
    if len(files) == 1:
        graph = chains[0].replace(f"[v0]", "[out]")
    else:
        graph = ";".join(chains) + ";" + "".join(labels) + \
            f"xstack=inputs={len(files)}:layout={'|'.join(layout)}:fill=white[out]"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", graph, "-map", "[out]",
                    "-frames:v", "1", str(out)], check=True)
    print(out, " ".join(f.parent.name for f in files))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prompt")
    p.add_argument("id")
    p.add_argument("--extra", default="")
    g = sub.add_parser("generate")
    g.add_argument("ids", nargs="+")
    g.add_argument("--tag", default="t1")
    g.add_argument("--extra", default="")
    g.add_argument("--slots", type=int, default=int(os.environ.get("HEROREF_SLOTS", "4")))
    s = sub.add_parser("select")
    s.add_argument("id")
    s.add_argument("tag")
    sh = sub.add_parser("sheet")
    sh.add_argument("ids", nargs="*")
    sh.add_argument("--tag")
    sh.add_argument("--cols", type=int, default=6)
    sh.add_argument("--size", type=int, default=360)
    a = ap.parse_args()
    if a.cmd == "prompt":
        print(build_prompt(a.id, a.extra))
    elif a.cmd == "generate":
        cmd_generate(a)
    elif a.cmd == "select":
        cmd_select(a)
    elif a.cmd == "sheet":
        cmd_sheet(a)


if __name__ == "__main__":
    main()
