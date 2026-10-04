#!/usr/bin/env python3
"""ステージ（戦場）用 2D 素材の生成。地面テクスチャ・崖の質感・Meshy に渡すコンセプト画像。

仕様（画風・各素材のプロンプト）は tools/stage/stage_art.json。

  python3 tools/stage/stage_art.py list                         # 素材 ID の一覧
  python3 tools/stage/stage_art.py prompt grass                 # 生成プロンプトを表示
  python3 tools/stage/stage_art.py generate grass dirt [--tag a2] [--extra "..."]
  python3 tools/stage/stage_art.py select grass a2              # 候補 grass_a2.png を採用版 grass.png にする

生成は Codex CLI（ChatGPT ログイン）の画像生成ツールを使う（tools/portraits/portraits.py と同じ方式）。
原寸（約 1254px PNG）は build/stage/art/（git 管理外）。アプリへの取り込み（縮小・タイル化）は
tools/stage/stage_bake.py が行う。同時実行数は STAGE_ART_SLOTS（既定 4）。
"""
import fcntl
import json
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # VELSTRIA/
SPEC = Path(__file__).with_name("stage_art.json")
RAW = ROOT / "build" / "stage" / "art"
MODEL = os.environ.get("STAGE_ART_CODEX_MODEL", "gpt-6-astra")
SLOTS = int(os.environ.get("STAGE_ART_SLOTS", "4"))


def spec():
    return json.loads(SPEC.read_text())


def entry(sid):
    s = spec()
    for e in s["assets"]:
        if e["id"] == sid:
            return s, e
    sys.exit(f"unknown id: {sid}")


def build_prompt(sid, extra=""):
    s, e = entry(sid)
    style = s["styles"][e["kind"]]
    text = style + "\n\nSubject: " + e["prompt"]
    if extra:
        text += "\n\nAdditional direction: " + extra
    return text


class Slot:
    """同時実行数の制限（プロセスをまたいでファイルロックで数える）。"""

    def __enter__(self):
        RAW.mkdir(parents=True, exist_ok=True)
        while True:
            for i in range(SLOTS):
                f = open(RAW / f".slot{i}.lock", "w")
                try:
                    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    self.f = f
                    return self
                except BlockingIOError:
                    f.close()
            time.sleep(2)

    def __exit__(self, *a):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


def generate(sid, extra="", tag=None, attempts=3):
    RAW.mkdir(parents=True, exist_ok=True)
    out = RAW / (f"{sid}_{tag}.png" if tag else f"{sid}.png")
    prompt = build_prompt(sid, extra)
    instruction = (
        "Use your built-in image generation tool to create exactly ONE image from the prompt below"
        f". When it is done, copy the generated PNG file to {out} (overwrite if it exists)."
        " Do not modify the image and do not create any other files. Reply only with the output path."
        "\n\n=== IMAGE PROMPT ===\n" + prompt
    )
    # 作業ディレクトリは固定（Codex は -C の場所を ~/.codex/config.toml の trusted に登録するため）
    work = RAW / ".codex-work"
    work.mkdir(parents=True, exist_ok=True)
    tail = ""
    for attempt in range(1, attempts + 1):
        if out.exists():
            out.unlink()
        with Slot():
            cmd = ["codex", "exec", "--skip-git-repo-check", "--ephemeral",
                   "--dangerously-bypass-approvals-and-sandbox",
                   "-m", MODEL, "-c", 'model_reasoning_effort="low"', "-C", str(work)]
            try:
                proc = subprocess.run(cmd, input=instruction, capture_output=True, text=True, timeout=900)
                tail = f"exit {proc.returncode}: " + (proc.stdout + proc.stderr)[-600:]
            except subprocess.TimeoutExpired:
                tail = "timed out"
        data = out.read_bytes() if out.exists() else b""
        if data[:8] == b"\x89PNG\r\n\x1a\n":
            print(out, flush=True)
            return out
        print(f"[{sid}] attempt {attempt} failed ({tail})", file=sys.stderr, flush=True)
        time.sleep(5 * attempt)
    print(f"[{sid}] generation failed", file=sys.stderr)
    return None


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    if cmd == "list":
        for e in spec()["assets"]:
            print(f"{e['id']:20s} {e['kind']:10s} {e.get('use', '')}")
        return 0
    if cmd == "prompt":
        print(build_prompt(rest[0]))
        return 0
    if cmd == "generate":
        tag, extra, ids = None, "", []
        i = 0
        while i < len(rest):
            if rest[i] == "--tag":
                tag = rest[i + 1]; i += 2
            elif rest[i] == "--extra":
                extra = rest[i + 1]; i += 2
            else:
                ids.append(rest[i]); i += 1
        if ids == ["all"]:
            ids = [e["id"] for e in spec()["assets"]]
        results = {}
        threads = [threading.Thread(target=lambda s=s: results.__setitem__(s, generate(s, extra, tag))) for s in ids]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        failed = [s for s, r in results.items() if r is None]
        return 1 if failed else 0
    if cmd == "select":
        sid, tag = rest[0], rest[1]
        src = RAW / f"{sid}_{tag}.png"
        if not src.exists():
            sys.exit(f"missing: {src}")
        shutil.copyfile(src, RAW / f"{sid}.png")
        print(RAW / f"{sid}.png")
        return 0
    sys.exit(f"unknown command: {cmd}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
