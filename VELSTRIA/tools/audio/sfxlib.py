"""音を作る道具（48 kHz モノラル。Sonniss の録音・Kenney の CC0 を層に重ね、打撃の時刻を揃え、種類ごとの音量（LUFS）に合わせる）。

ヒーロー・共通の音・武器・属性・画面の音のモジュール（tools/audio/heroes/*.py・sets/*.py）から使う。作り方は make_sounds.py。
素材: Sonniss GDC Game Audio Bundle（sonniss_lib.find が archive.org の写しから要る 1 ファイルだけ落とす。加工した完成品だけ置く）と Kenney。
"""
import json
import os
import subprocess
import sys

import numpy as np
import pyloudnorm as pyln
from scipy import signal

sys.path.insert(0, os.path.dirname(__file__))
import build_audio as B  # noqa: E402  （Kenney の素材・風切り音などの道具）
import sonniss_lib as S  # noqa: E402

SR = S.SR
OUT = B.OUT
RECORDS_DIR = os.path.join(os.path.dirname(__file__), "records")
# 種類ごとの音量（LUFS。MLBB の測定: 通常攻撃 -20〜-26、スキル -19〜-22、奥義 -20 で山が高い。ゲームの中の比をそのまま、全体は少し大きめ）
# MLBB の測定（ティグラル）: 通常攻撃 -20〜-26（平均 -23）、スキル -19.7〜-22、奥義 -20（山は一番高い）。スキルは通常攻撃とほぼ同じ大きさ
# 強化通常攻撃（atkx = 子龍の三連突き・ディロスの円撃など）は通常攻撃（-23 / 命中 -27）より大きく、スキルの山（-20.5〜）より小さい
TARGET = {"atk": -23.0, "atkhit": -27.0, "atkx": -21.0, "atkxhit": -24.0, "cast": -20.5, "ult": -19.0, "hit": -23.0,
          "passive": -25.0, "crit": -22.0, "event": -20.0, "world": -22.0, "ui": -27.0, "stinger": -18.0}
TAIL = {"atk": 0.45, "atkhit": 0.4, "atkx": 0.9, "atkxhit": 0.4, "cast": 2.0, "ult": 1.9, "hit": 0.7, "passive": 1.2,
        "crit": 0.6, "event": 2.5, "world": 3.0, "ui": 0.6, "stinger": 3.0}


# MARK: 道具

def sn(part, i=0, p=1.0, g=0.0, lp=None, hp=None, post=0.3, start=None, length=None, hit=False, pre=0.01):
    """Sonniss の素材のテイク（音程 p・音量 g dB・帯域）。start/length で切り出し（秒）。
    hit=True: 打撃の立ち上がり（包絡が最大の半分を越える所）を pre 秒の位置に揃える（置いた時刻 = 着弾の時刻になる）。
    hit="peak": 包絡の最大を揃える（振り → 着弾の素材は振りが半分を越えるので、着弾 = 最大で揃える）。"""
    x, path = S.take(part, i, post=post)
    if hit:
        x = onset_align(x, pre, peak=hit == "peak")
    if start is not None:
        x = x[int(start * SR):]
    if length is not None:
        x = B.fade(x[:int(length * SR)], 0.0, min(0.08, length / 3))
    if p != 1.0:
        x = B.pitch(x, p)
    if lp:
        x = lowpass(x, lp)
    if hp:
        x = highpass(x, hp)
    USED.add(S.pack_of(path))
    return B.db(x, g)


def kn(pack, name, p=1.0, g=0.0, lp=None, hp=None):
    """Kenney の素材（48 kHz へ）。"""
    x = B.K(pack, name)
    x = signal.resample_poly(x, 160, 147).astype(np.float32)
    if p != 1.0:
        x = B.pitch(x, p)
    if lp:
        x = lowpass(x, lp)
    if hp:
        x = highpass(x, hp)
    USED.add(("kenney", pack))
    return B.db(x, g)


def onset_align(x, pre, peak=False):
    """包絡（5 ms）が最大の半分を越える最初の所（peak なら最大）を pre 秒の位置へ（前の振りの音などは切る）。"""
    win = int(0.005 * SR)
    env = np.sqrt(np.convolve(x ** 2, np.ones(win) / win, mode="same"))
    i = int(np.argmax(env)) if peak else int(np.argmax(env > env.max() * 0.5))
    return x[max(0, i - int(pre * SR)):].copy()


def lowpass(x, hz):
    sos = signal.butter(4, hz, "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x).astype(np.float32)


def highpass(x, hz):
    sos = signal.butter(2, hz, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x).astype(np.float32)


def rise(x, seconds):
    """前を seconds 秒かけて立ち上げる（溜め）。"""
    n = min(len(x), int(seconds * SR))
    y = x.copy()
    y[:n] *= np.linspace(0, 1, n, dtype=np.float32) ** 2
    return y


def rev(x):
    """逆再生（打撃の尾を逆にすると、吸い込まれて着弾へ向かう溜めになる）。"""
    return x[::-1].copy()


def tail(x, a, b):
    """a 秒から b 秒へ全体を薄くして消す（MLBB の音の終わりに揃える）。"""
    n0, n1 = int(a * SR), int(b * SR)
    y = x[:n1].copy()
    if len(y) > n0:
        y[n0:] *= np.linspace(1, 0, len(y) - n0, dtype=np.float32) ** 1.5
    return y


def mix(layers):
    end = max(int(t * SR) + len(s) for t, s in layers)
    out = np.zeros(end, np.float32)
    for t, s in layers:
        i = int(t * SR)
        out[i:i + len(s)] += s
    return out


def reverb(x, seconds, amount, seed=1):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    ir = rng.standard_normal(n).astype(np.float32) * np.exp(-np.linspace(0, 6.5, n)).astype(np.float32)
    ir = lowpass(ir, 5000)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    wet = signal.fftconvolve(np.concatenate([x, np.zeros(n, np.float32)]), ir)[: len(x) + n].astype(np.float32)
    dry = np.concatenate([x, np.zeros(n, np.float32)])
    return dry * (1 - amount) + wet * amount


def trim_tail(x, db):
    thr = 10 ** (db / 20) * max(1e-9, np.abs(x).max())
    idx = np.nonzero(np.abs(x) > thr)[0]
    return x[:idx[-1] + 1] if len(idx) else x


def finish(x, kind, target=None, cap=None):
    """尾を残して切り（cap で種類の既定の長さを上書き）、音量（LUFS）をそろえ（target で上書き）、山を -1 dBFS に抑える。"""
    lim = int((TAIL[kind] if cap is None else cap) * SR)
    if len(x) > lim:
        x = B.fade(x[:lim], 0.0, 0.3)
    # 頭は切らない（0 秒 = 鳴らす時刻 = 発動・命中の時刻。溜めが無音から始まっても時刻をずらさない）。尾の無音だけ切る
    x = B.fade(trim_tail(x, -65), 0.0, 0.02)
    goal = TARGET[kind] if target is None else target
    loud = lufs(x)
    for _ in range(3):
        # 目標の音量にして、山が -1 dBFS を越える分は打撃の立ち上がりだけ抑える（6 dB まで。それ以上は全体を下げる）
        now = lufs(x)
        if not np.isfinite(now):
            break
        x = x * (10 ** ((goal - now) / 20))
        over = 20 * np.log10(np.abs(x).max() / CEILING + 1e-12)
        if over <= 0.05:
            break
        if over > MAX_LIMIT_DB:
            x = x * (10 ** (-(over - MAX_LIMIT_DB) / 20))
        x = limit(x)
    peak = np.abs(x).max()
    if peak > CEILING:
        x = x * (CEILING / peak)
    return x.astype(np.float32), loud


CEILING = 10 ** (-1 / 20)
MAX_LIMIT_DB = 6.0


def lufs(x):
    meter = pyln.Meter(SR, block_size=0.1)
    pad = np.concatenate([x, np.zeros(int(0.15 * SR), np.float32)]).astype(np.float64)
    return meter.integrated_loudness(pad)


def limit(x, release=0.06):
    """山の抑え（先読み 2 ms・戻り 60 ms）。打撃の立ち上がりだけを CEILING に収める。"""
    from scipy.ndimage import maximum_filter1d
    look = int(0.002 * SR)
    pk = maximum_filter1d(np.abs(x), size=2 * look + 1)
    g = np.minimum(1.0, CEILING / np.maximum(pk, 1e-9))
    r = float(np.exp(-1 / (release * SR)))
    out = np.empty_like(g)
    cur = 1.0
    for i in range(len(g)):
        gi = g[i]
        cur = gi if gi < cur else r * cur + (1 - r) * gi
        out[i] = cur
    return (x * out).astype(np.float32)


USED = set()
RECORDS = {}


def save(module):
    """このモジュールで書いた音の記録を records/<module>.json に書き、次のモジュールのために空にする。"""
    os.makedirs(RECORDS_DIR, exist_ok=True)
    with open(os.path.join(RECORDS_DIR, f"{module}.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(RECORDS, f, ensure_ascii=False, indent=1, sort_keys=True)
    RECORDS.clear()


def write(name, x, kind, note, target=None, cap=None):
    x, before = finish(x, kind, target, cap)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".caf")
    subprocess.run([S.FF, "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "pcm_s16le",
                    "-f", "caf", path], input=x.tobytes(), check=True)
    RECORDS[name + ".caf"] = {"seconds": round(len(x) / SR, 2), "kind": kind, "note": note,
                              "sources": sorted({f"{a} / {b}" for a, b in USED})}
    USED.clear()
    print(f"  {name}.caf {len(x)/SR:.2f}s ({kind})")
