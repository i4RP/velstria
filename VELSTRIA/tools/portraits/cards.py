#!/usr/bin/env python3
"""ロード画面（試合開始直前）のヒーローカード絵（HeroCards）と、その顔を切り抜いたアイコン（HeroFaces）を作る。

  python3 tools/portraits/cards.py generate [ID,...]   # Codex でカード絵（縦長 2:3）を生成 → build/cards/<ID>.png
  python3 tools/portraits/cards.py faces [ID,...]      # Vision で顔を検出して正方形に切り抜く → build/cards/face/<ID>.png
  python3 tools/portraits/cards.py install             # Assets.xcassets の HeroCards（768px 高）/ HeroFaces（256px）へ

参照画像はポートレートの原画（build/portraits/<ID>.png）。無ければ環境変数 CARD_REF_DIRS（: 区切り）から探す。
並列数は CARD_JOBS（既定 5）。
"""
import json
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = Path(__file__).with_name("portraits.json")
FACE_SWIFT = Path(__file__).with_name("face.swift")
ASSETS = ROOT / "App" / "Resources" / "Assets.xcassets"
WORK = ROOT / "build" / "cards"
FACE = WORK / "face"
REF_DIRS = [ROOT / "build" / "portraits"] + [Path(p) for p in os.environ.get("CARD_REF_DIRS", "").split(":") if p]
ACTIVE = [f"H0{n}" for n in range(25, 35)]
JOBS = int(os.environ.get("CARD_JOBS", "5"))
# Vision が顔を見つけられない絵（目元を覆う・横顔・髭）の切り抜き: (中心 x, 中心 y, 一辺) を幅に対する割合で
FACE_OVERRIDE = {
    "H032": (0.45, 0.19, 0.40),
    "H034": (0.53, 0.19, 0.42),
}

STYLE = (
    "Vertical 2:3 portrait-orientation character card art for VELSTRIA, a premium fantasy mobile MOBA game "
    "(like a loading-screen hero card). Hand-painted splash-art quality: painterly semi-realistic digital painting, "
    "dramatic rim lighting, strong value contrast. Composition: dynamic three-quarter body shot from the head down to "
    "about the thighs, the character fills the card; the face is clearly visible, large, front or 3/4 view toward the "
    "viewer, placed in the upper third of the card (top of the head about 8% below the top edge), never hidden by "
    "the weapon, hair or effects. Signature weapon and effects visible around the body. Background: {background}, "
    "darker toward the bottom quarter (name text is overlaid there). Tasteful all-ages costume for a 9+ rated game: "
    "no cleavage, no bare chest or midriff on female characters. Absolutely no text, letters, logos, watermark, "
    "border, frame or UI elements. Full-bleed image."
)


def heroes():
    return {h["id"]: h for h in json.loads(SPEC.read_text())["heroes"]}


def ref_for(hid):
    for d in REF_DIRS:
        p = d / f"{hid}.png"
        if p.exists():
            return p
    sys.exit(f"reference portrait missing for {hid} (set CARD_REF_DIRS)")


def generate(hid, attempts=3):
    h = heroes()[hid]
    ref = ref_for(hid)
    out = WORK / f"{hid}.png"
    prompt = STYLE.format(background=h["background"]) + "\n\nCharacter: " + h["description"]
    instruction = (
        "Use your built-in image generation tool to create exactly ONE image (portrait orientation, 1024x1536) from "
        "the prompt below. The attached image is the identity reference: keep the same character, face, hair, "
        "costume, colors and weapon, but re-compose as described. When it is done, copy the generated PNG file to "
        f"{out} (overwrite if it exists). Do not modify the image and do not create any other files. Reply only "
        "with the output path.\n\n=== IMAGE PROMPT ===\n" + prompt
    )
    work = WORK / ".codex-work"
    work.mkdir(parents=True, exist_ok=True)
    for attempt in range(1, attempts + 1):
        out.unlink(missing_ok=True)
        cmd = [shutil.which("codex") or "codex", "exec", "--skip-git-repo-check", "--ephemeral",
               "--dangerously-bypass-approvals-and-sandbox",
               "-m", os.environ.get("PORTRAIT_CODEX_MODEL", "gpt-6-astra"),
               "-c", 'model_reasoning_effort="low"', "-C", str(work), "-i", str(ref)]
        try:
            proc = subprocess.run(cmd, input=instruction, capture_output=True, text=True, timeout=900)
            tail = (proc.stdout + proc.stderr)[-600:]
        except subprocess.TimeoutExpired:
            tail = "timed out"
        if out.exists() and out.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n":
            print(out, flush=True)
            return
        print(f"[{hid}] attempt {attempt} failed: {tail}", file=sys.stderr, flush=True)
    print(f"[{hid}] generation failed", file=sys.stderr)


def faces(ids):
    FACE.mkdir(parents=True, exist_ok=True)
    args = []
    for hid in ids:
        args += [str(WORK / f"{hid}.png"), str(FACE / f"{hid}.png")]
    subprocess.run(["swift", str(FACE_SWIFT)] + args, check=True)
    for hid in ids:
        if hid not in FACE_OVERRIDE:
            continue
        cx, cy, side = FACE_OVERRIDE[hid]
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(WORK / f"{hid}.png"), "-vf",
                        f"crop=iw*{side}:iw*{side}:iw*{cx - side / 2}:iw*{cy}-iw*{side / 2}",
                        str(FACE / f"{hid}.png")], check=True)


def imageset(folder, name, src, height, square):
    d = ASSETS / folder / f"{name}.imageset"
    d.mkdir(parents=True, exist_ok=True)
    flat = WORK / f".{folder}-{name}.png"
    scale = f"scale={height}:{height}" if square else f"scale=-2:{height}"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=black:s=4096x4096", "-i", str(src),
                    "-filter_complex", f"[1:v]{scale}:flags=lanczos[f];[0:v][f]scale2ref[bg][f2];[bg][f2]overlay=format=auto",
                    "-frames:v", "1", str(flat)], check=True)
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "72", str(flat), "--out",
                    str(d / f"{name}.jpg")], check=True, capture_output=True)
    flat.unlink()
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.jpg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def install(ids):
    for folder in ("HeroCards", "HeroFaces"):
        (ASSETS / folder).mkdir(exist_ok=True)
        (ASSETS / folder / "Contents.json").write_text(json.dumps({
            "info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": True}}, indent=2) + "\n")
    for hid in ids:
        if (WORK / f"{hid}.png").exists():
            imageset("HeroCards", hid, WORK / f"{hid}.png", 768, False)
        if (FACE / f"{hid}.png").exists():
            imageset("HeroFaces", hid, FACE / f"{hid}.png", 256, True)
        print(hid)


if __name__ == "__main__":
    cmd = sys.argv[1]
    ids = sys.argv[2].split(",") if len(sys.argv) > 2 else ACTIVE
    WORK.mkdir(parents=True, exist_ok=True)
    if cmd == "generate":
        with ThreadPoolExecutor(JOBS) as ex:
            list(ex.map(generate, ids))
    elif cmd == "faces":
        faces(ids)
    elif cmd == "install":
        install(ids)
