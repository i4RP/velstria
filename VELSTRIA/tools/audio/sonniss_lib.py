"""Sonniss の素材を読む・テイクに切り分ける（sfxlib から使う。単体で実行すると中身を見る・探す）。

python tools/audio/sonniss_lib.py "Metal Shield Block" "Iron - Thick"   # 名前の一部で探し（無ければ落とし）、テイクの区切りを出す
python tools/audio/sonniss_lib.py --search "thunder|lightning"          # 写しの全ファイルの目録から探す（落とさない）

置き場所: 環境変数 SONNISS_CACHE（既定は tools/audio/.cache/sonniss。worktree どうしで同じ所を指せば共有できる）。
手元に無い素材は、写しの目録（sonniss_index.py が作る <置き場所>/index_all.tsv）から 1 つに決まれば、その 1 ファイルだけ
archive.org の sonniss-gdc-<年>-game-audio-bundle-normalized から落とす。原本はリポジトリに入れない。
"""
import glob
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

import imageio_ffmpeg
import numpy as np

FF = imageio_ffmpeg.get_ffmpeg_exe()
SR = 48000
ROOT = os.environ.get("SONNISS_CACHE") or os.path.join(os.path.dirname(__file__), ".cache", "sonniss")
INDEX = os.path.join(ROOT, "index_all.tsv")


def item(year):
    return f"sonniss-gdc-{year}-game-audio-bundle-normalized"


def index_rows():
    """写しの目録の行（年, 大きさ, 年の下の相対パス）。"""
    if not os.path.exists(INDEX):
        return []
    rows = []
    for line in open(INDEX, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t", 2)
        if len(parts) == 3:
            rows.append((parts[0], int(parts[1]), parts[2]))
    return rows


def fetch(year, name):
    """写しの 1 ファイルを置き場所へ落とす（あれば何もしない）。戻り値はパス。"""
    dst = os.path.join(ROOT, year, *name.split("/"))
    if not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        url = f"https://archive.org/download/{item(year)}/" + urllib.parse.quote(name)
        tmp = f"{dst}.{os.getpid()}.part"  # 同時に落とす担当どうしでぶつからない
        urllib.request.urlretrieve(url, tmp)
        os.replace(tmp, dst)
    return dst


def find(part):
    """ファイル名・素材集の名前の一部で探す。手元に 1 つならそれ、無ければ目録で 1 つに決まる物を落とす（それ以外は例外）。
    「年/素材集/名前」の形で渡せば、目録でその通りの 1 ファイルを選べる。"""
    low = part.lower()
    local = [p for p in glob.glob(os.path.join(ROOT, "*", "*", "*"))
             if low in p.replace("\\", "/").lower() and p.lower().endswith((".flac", ".wav"))]
    if len(local) == 1:
        return local[0]
    if len(local) > 1:
        raise LookupError(f"{part}: 手元に {len(local)} 件 {[os.path.basename(h) for h in local][:5]}")
    rows = [r for r in index_rows() if low in f"{r[0]}/{r[2]}".lower()]
    if len(rows) != 1:
        raise LookupError(f"{part}: 目録に {len(rows)} 件 {[r[2][:80] for r in rows][:5]}")
    return fetch(rows[0][0], rows[0][2])


def search(pattern, cap_mb=25):
    """目録を正規表現で探す（落とさない）。"""
    pat = re.compile(pattern, re.I)
    return [(y, sz, nm) for y, sz, nm in index_rows() if pat.search(nm) and sz / 1e6 <= cap_mb]


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
    if sys.argv[1:2] == ["--search"]:
        for y, sz, nm in search(sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 25):
            print(f"{y} {sz / 1e6:5.1f}MB {nm}")
        sys.exit(0)
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
