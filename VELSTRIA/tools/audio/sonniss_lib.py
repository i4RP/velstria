"""Sonniss の素材（tools/audio/.cache/sonniss）を読む・テイクに切り分ける（skill_sounds_v2 から使う。単体で実行すると中身を見る）。

python tools/audio/sonniss_lib.py "Metal Shield Block" "Iron - Thick"   # 名前の一部で探し、テイクの区切りを出す
"""
import glob
import os
import subprocess
import sys

import imageio_ffmpeg
import numpy as np

FF = imageio_ffmpeg.get_ffmpeg_exe()
SR = 48000
ROOT = os.path.join(os.path.dirname(__file__), ".cache", "sonniss")


def find(part):
    """ファイル名・素材集の名前の一部で探す（1 つに決まらなければ例外）。"""
    hits = [p for p in glob.glob(os.path.join(ROOT, "*", "*", "*")) if part.lower() in p.lower() and p.lower().endswith((".flac", ".wav"))]
    if len(hits) != 1:
        raise LookupError(f"{part}: {len(hits)} 件 {[os.path.basename(h) for h in hits][:5]}")
    return hits[0]


def pack_of(path):
    """(年, 素材集) — 出典の記録用。"""
    rel = os.path.relpath(path, ROOT).replace("\\", "/").split("/")
    return rel[0], rel[1]


_cache = {}


def load(part):
    """モノラル 48 kHz で読む（左右は混ぜる）。"""
    path = find(part)
    if path not in _cache:
        b = subprocess.run([FF, "-v", "quiet", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                           capture_output=True, check=True).stdout
        _cache[path] = np.frombuffer(b, np.float32).copy()
    return _cache[path], path


def takes(x, thr_db=-32.0, gap=0.12, min_len=0.04):
    """音の塊（テイク）の区切り（開始, 終了 秒）。包絡が最大から thr_db 下を超えた所を塊とし、gap 秒より短い隙間はつなぐ。"""
    win = int(0.01 * SR)
    env = np.sqrt(np.convolve(x ** 2, np.ones(win) / win, mode="same"))
    thr = env.max() * 10 ** (thr_db / 20)
    on = env > thr
    segs, i, n = [], 0, len(x)
    while i < n:
        if on[i]:
            j = i
            while j < n and (on[j] or (j + int(gap * SR) < n and on[j:j + int(gap * SR)].any())):
                j += 1
            if (j - i) / SR >= min_len:
                segs.append((i / SR, j / SR))
            i = j
        else:
            i += 1
    return segs


def take(part, index=0, pre=0.005, post=0.25, thr_db=-32.0):
    """index 番目のテイク（前に少し、後ろに余韻を残す）。戻り値 (音, ファイルのパス)。"""
    x, path = load(part)
    segs = takes(x, thr_db)
    if not segs:
        return x, path
    a, b = segs[min(index, len(segs) - 1)]
    s = max(0, int((a - pre) * SR))
    e = min(len(x), int((b + post) * SR))
    return x[s:e].copy(), path


if __name__ == "__main__":
    for part in sys.argv[1:]:
        try:
            x, path = load(part)
        except LookupError as e:
            print(e)
            continue
        print("==", os.path.basename(path), f"{len(x)/SR:.2f}s")
        for i, (a, b) in enumerate(takes(x)):
            seg = x[int(a * SR):int(b * SR)]
            peak = 20 * np.log10(np.abs(seg).max() + 1e-9)
            spec = np.abs(np.fft.rfft(seg[: min(len(seg), 16384)] * np.hanning(min(len(seg), 16384))))
            fr = np.fft.rfftfreq(min(len(seg), 16384), 1 / SR)
            cent = (spec * fr).sum() / (spec.sum() + 1e-9)
            print(f"  [{i}] {a:6.2f}-{b:6.2f}s ({b-a:.2f}s) peak {peak:5.1f}dB  centroid {cent:6.0f}Hz")
