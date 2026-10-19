"""ヒーロー固有の音 v2（48 kHz モノラル・素材の層 3〜5・揺らぎ・種類ごとの音量（LUFS）をそろえる）。

python tools/audio/skill_sounds_v2.py H029        # ヒーローを指定して作り直す（v1 の同じヒーローの音を置き換える）
素材: Sonniss GDC Game Audio Bundle（tools/audio/sonniss_fetch.py で落とす。加工した完成品だけ置く）と Kenney（CC0）。
参照: MLBB の効果音だけの画面収録（手元だけ。製品には使わない）を tools/audio の profile で測った層・時刻・長さ・音量の比
（docs/audio/MLBB_H0xx.md）。時刻は演出の at: と sim の時刻の定数（FX_H0xx.swift）に合わせる。
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
RECORD = os.path.join(os.path.dirname(__file__), "outputs_v2.json")
# 種類ごとの音量（LUFS。MLBB の測定: 通常攻撃 -20〜-26、スキル -19〜-22、奥義 -20 で山が高い。ゲームの中の比をそのまま、全体は少し大きめ）
# MLBB の測定（ティグラル）: 通常攻撃 -20〜-26（平均 -23）、スキル -19.7〜-22、奥義 -20（山は一番高い）。スキルは通常攻撃とほぼ同じ大きさ
TARGET = {"atk": -23.0, "atkhit": -27.0, "cast": -20.5, "ult": -19.0, "hit": -23.0, "passive": -25.0}
TAIL = {"atk": 0.45, "atkhit": 0.4, "cast": 2.0, "ult": 1.9, "hit": 0.7, "passive": 1.2}


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


# MARK: H029 ボルグ（ティグラル）— 聖騎士の槌と盾。金属の重さ・地響き・炎の波
# MLBB（docs/audio/MLBB_H029.md）: 通常攻撃 0.35〜0.45 秒で全帯域が着弾で揃う（体の芯 > 金属 -3〜4 dB）。
# S1 は叩きつけ（+0.05 で芯と金属）→ 低い地鳴り（+0.2）→ 炎の弾け（+0.6）、全体 1.8 秒。S2 は突進の出だしに金属と風、
# 地響き（+0.35）、炎の尾（+0.3）、1.2 秒。再使用は槌の金属（+0.05〜0.15）と低音（+0.2）0.7 秒。
# 奥義は 0.8 秒かけて全帯域がふくらみ、1.0 秒で低音の山（崩落）、0.6 秒の尾。

def h029():
    hero = "H029"
    # 通常攻撃（4 種）: sim の命中（attackReleased）の瞬間に鳴る。振りの終わり（0.03 秒前から）→ 鈍い着弾 + 槌の金属の鳴り + 低い芯
    for k, (ti, mi, p) in enumerate([(0, 1, 1.0), (3, 3, 0.97), (6, 4, 1.03), (9, 6, 0.99)], start=1):
        x = mix([(0, sn("SWING IMPACTS Quick Heavy", ti, p=p, post=0.1, hp=90, hit="peak", pre=0.04)),
                 (0.03, sn("Iron - Thick - HIT - Hammer", mi, p=0.85, g=-5, hp=700, post=0.3, hit=True)),
                 (0.04, sn("heavy_metal_impact_metal_plate_medium", p=0.85, g=-11, hp=1500, length=0.3, hit=True)),
                 (0.03, sn("10 Hit Deep Thud", p=1.1 * p, g=-4, lp=180, length=0.3, hit=True))])
        write(f"skill_{hero}_atk_{k}", x, "atk", "重い武器の振り → 鈍い着弾 + 槌の金属の鳴り")
    # 通常攻撃の命中（3 種）: 盾・鎧に当たる金属の鈍い音（控えめ）
    for k, i in enumerate([0, 2, 4], start=1):
        write(f"skill_{hero}_atkhit_{k}", sn("Metal Shield Block Hits", i, p=0.9, lp=6000, post=0.2, hit=True), "atkhit", "鎧に当たる金属")

    # S1 聖槌波: 0.25 の叩きつけ（芯・金属・地響き）→ 0.5 まで低音がふくらむ → 0.58 の 2 波は小さく → 0.92 の 3 波で
    # 芯と低音がもう一度（MLBB の +0.65 の山）→ 1.3 で消える。振りかぶりの音は小さく（MLBB は叩きつけの前がほぼ無音）
    s1 = mix([
        (0.0, rise(sn("Titan D", p=0.9, g=-20, length=0.45), 0.35)),
        (0.25, sn("stone_impact_hammer", p=0.82, g=-5, lp=3500, hit=True)),
        (0.25, sn("Sledgehammer_Hit", p=0.9, g=-13, lp=4000, hit=True)),
        (0.25, sn("4 x Punch, Body", 1, p=0.7, g=-1, hp=110, lp=1500, hit=True, length=0.11)),
        (0.25, sn("GROUND IMPACT Large", g=-11, lp=3000, hit=True)),
        (0.25, sn("Haunted Metal Vol 1_60", g=-2, lp=160, length=1.4, hit=True)),
        (0.25, sn("Trailer Hit Cavernous", g=-2, lp=150, length=1.05)),
        (0.32, rise(sn("Ruin B", g=-14, lp=700, length=0.6), 0.12)),
        (0.4, rise(sn("GROUND IMPACT Large", g=-10, hp=3000, start=0.35, length=0.6), 0.1)),
        (0.583, sn("Bluezone_BC0297_stone_impact_015", p=0.8, g=-17, lp=2500, hit=True)),
        (0.917, sn("Bluezone_BC0297_stone_impact_041", p=0.78, g=-10, lp=3000, hit=True)),
        (0.917, sn("4 x Punch, Body", 2, p=0.72, g=-7, hp=110, lp=1500, hit=True, length=0.11)),
        (0.94, sn("Explosive Hit 10", g=-9, length=0.5, hit=True)),
        (0.75, rise(sn("Fire_Spell_Dragon", g=-16, hp=3000, start=0.3, length=0.55), 0.15)),
    ])
    write(f"skill_{hero}_s1_cast", tail(reverb(s1, 0.5, 0.1, 3), 1.2, 1.6), "cast", "叩きつけ（槌・岩・地響き）→ 低音のふくらみ → 3 波目の芯と地鳴り")
    for k, i in enumerate([0, 1, 2], start=1):
        x = mix([(0, sn("Bluezone_BC0297_stone_impact_015" if k != 2 else "Bluezone_BC0297_stone_impact_041", p=0.85 + 0.05 * k, g=-2, hit=True)),
                 (0, sn("Fire_Spell_Dragon", g=-12, hp=1500, length=0.4))])
        write(f"skill_{hero}_s1_hit_{k}", x, "hit", "岩の着弾 + 炎")

    # S2 聖槌突撃: 出だしに盾の金属・体の芯・突進の風（MLBB は最初の 0.3 秒に山）→ 0.3 で盾の擦れ → 低音が 0.5 まで →
    # 0.67 の押し運びの打撃は小さく → 1.0 で消える
    s2 = mix([
        (0.0, sn("Metal Shield Block Hits", 1, p=0.85, g=-4, lp=7000, hit=True)),
        (0.0, sn("4 x Punch, Body", 2, p=0.75, g=0, hp=110, lp=1500, hit=True, length=0.11)),
        (0.0, sn("Justice B", p=0.95, g=-8, start=0.38, length=0.7, lp=2500)),
        (0.03, rise(sn("Haunted Metal Vol 1_02", g=0, lp=220, length=1.05), 0.15)),
        (0.3, sn("Metal Shield Block Hits", 3, p=0.8, g=-4, lp=7000, hit=True)),
        (0.1, rise(sn("Fire_Spell_Dragon", g=-4, hp=3000, start=0.25, length=0.6), 0.12)),
        (0.67, sn("METAL SWING HIT", p=0.9, g=-14, length=0.3, lp=6000, hit="peak", pre=0.03)),
    ])
    write(f"skill_{hero}_s2_cast", reverb(s2, 0.8, 0.14, 4), "cast", "盾の金属 + 体の芯 + 突進の風 → 盾の擦れ・地響き → 小さな押し運びの打撃")
    # 再使用（打ち上げ）: 振り上げの風（0）→ 0.2 で槌の金属と体の芯（MLBB の山 -15）→ 低音の尾 0.5 秒
    r1 = mix([
        (0.0, rise(sn("SWING IMPACTS Quick Heavy", 12, p=1.08, g=-2, hp=200, hit="peak", pre=0.2, length=0.35), 0.1)),
        (0.2, sn("Iron - Thick - HIT - Hammer", 1, p=0.8, g=0, lp=6000, hit=True)),
        (0.2, sn("Sledgehammer_Hit", p=0.85, g=-8, lp=6000, hit=True)),
        (0.2, sn("4 x Punch, Body", 1, p=0.8, g=7, hp=100, lp=2000, hit=True, length=0.11)),
        (0.2, sn("Boom 036", g=-10, lp=300, length=0.8, hit="peak", pre=0.02)),
    ])
    write(f"skill_{hero}_s2_r1_cast", reverb(r1, 0.5, 0.1, 5), "cast", "振り上げの風 → 槌の金属 + 体の芯 + 低音（打ち上げ）")
    for k, i in enumerate([2, 3, 4], start=1):
        x = mix([(0, sn("Metal Shield Block Hits", i, p=0.8, g=-1, hit=True)), (0, sn("4 x Punch, Body", k - 1, g=-7, lp=3000, hit=True, length=0.11))])
        write(f"skill_{hero}_s2_hit_{k}", x, "hit", "盾の打撃 + 体への衝撃")

    # 奥義 崩落聖域: 0.15 で槌を掲げる一撃（MLBB の出だしの山）→ 0.4〜0.95 の吸い込み（地鳴り・渦の風・気の流れ・逆再生の打撃）→
    # 1.0 で崩落（重い一撃・金属・岩、低音の山は 1.1〜1.2）→ 1.6 で消える
    suck = rev(sn("Haunted Metal Vol 1_18", g=-8, lp=4000, hp=120, length=1.0))
    ult = mix([
        (0.22, sn("Smash B", g=-12, length=0.5, hit=True)),
        (0.22, sn("Explosive Hit 10", g=-5, length=0.6, hit=True)),
        (0.23, sn("Metal Shield Block Hits", 2, p=0.75, g=-8, hit=True)),
        (0.1, rise(sn("MAGIC AIR Large Whoosh", p=1.2, g=-4, hp=2500, length=0.4), 0.08)),
        (0.0, rise(sn("energy flow, astonishment", g=-2, start=0.7, length=1.05, hp=150), 0.9)),
        (0.0, rise(sn("MAGIC AIR Large Whoosh", p=0.85, g=0, length=1.0, hp=150), 0.9)),
        (0.2, rise(sn("Wind, Rush, Whoosh", g=8, hp=2500, length=0.8), 0.25)),
        (0.2, rise(sn("MAGIC AIR Large Whoosh", p=1.1, g=-2, hp=2500, start=0.2, length=0.8), 0.3)),
        (0.3, rise(sn("LFE Rumble 3", g=4, lp=120, length=0.72), 0.5)),
        (0.0, rise(B.db(suck, 8), 0.6)),
        (0.85, sn("Justice B", p=0.9, g=-8, hit="peak", pre=0.12, length=0.2)),
        (1.0, sn("Smash B", g=2, hp=70, length=0.55, hit=True)),
        (1.0, sn("4 x Punch, Body", 1, p=0.68, g=0, hp=110, lp=1500, hit=True, length=0.11)),
        (1.0, sn("Haunted Metal Vol 1_02", g=-12, lp=400, length=0.8, hit=True)),
        (1.0, sn("GROUND IMPACT Large", g=-3, lp=2500, length=0.45, hit=True)),
        (1.0, sn("Iron - Thick - HIT - Hammer", 6, p=0.75, g=0, post=0.2, hit=True)),
    ])
    write(f"skill_{hero}_ult_cast", tail(reverb(ult, 0.6, 0.12, 6), 1.5, 1.85), "ult", "掲げる一撃 → 吸い込み（地鳴り・渦・気・逆再生の打撃）→ 崩落（重い一撃・金属・岩）")
    for k, part in enumerate(["heavy_metal_impact_metal_plate_medium", "heavy_metal_impact_steel_barrel_01",
                              "heavy_metal_impact_large_tank_01_03"], start=1):
        x = mix([(0, sn(part, p=0.9, g=-1, length=0.7, hit=True)), (0, sn("Bluezone_BC0297_stone_impact_015", p=0.75, g=-8, hit=True))])
        write(f"skill_{hero}_ult_hit_{k}", x, "hit", "重い金属の着弾 + 岩")

    # パッシブ（盾の加護）: 盾の金属のきらめき + 柔らかい光の音
    pas = mix([(0, sn("Ice_Spell_Ice_Spell_Buff_Positive", p=0.8, g=-6, lp=7000, length=0.9)),
               (0.02, sn("Metal Shield Block Hits", 3, p=1.2, g=-12, hp=1500, length=0.4, hit=True))])
    write(f"skill_{hero}_passive", pas, "passive", "盾の加護（光の音 + 盾のきらめき）")
    return hero


# MARK: H034 ゴルム（フランコ）— 鎖と斧鉤。鉄の鎖の連なり・肉への重い打撃・地を打つ鈍い地響き
# MLBB（docs/audio/MLBB_H034.md）: S1 は投げ（風切りと鎖の放り出し、全帯域 -24〜-28）→ 飛ぶ間の鎖の連なり（0.1 秒おきの鳴り）
# → 命中の重い打撃（低音 -20）→ 0.4 秒後の引き寄せ（鎖の金属・擦れ -20）。投げの部分 -21、命中と引き寄せ -19 LUFS。
# S2 は叩きつけから 0.07 秒で芯（体 -17.6）、+0.17 で低音（-19）が 0.5 秒続き、0.8 秒で消える（-19.8 LUFS）。
# 奥義は掴みの擦れの一閃（-10.7 LUFS の一番大きな音）→ 0.3 秒おきの重い打撃（1 撃 -13〜-15 LUFS）。
# パッシブは 0.5 秒かけて低音がふくらむ回復の音（1.1 秒、-21.5 LUFS）。通常攻撃は録画に単独の音が無い（塔の弾と重なる）ので
# ティグラルの通常攻撃と同じ物差し（0.4 秒・-23 LUFS）で、斧鉤の肉と鉄の打撃にする。
# sim の時刻（Kit_H034.Tune）: 鉤は 0.33 で投げ、最大 0.54 秒飛ぶ。命中から 0.45 秒そのまま、0.25 秒で引き寄せ。
# S2 は 0.27 で叩きつけ。奥義は 0.25 で掴み、0.25 + 0.32n 秒に 6 撃（1 撃ごとに命中の音）。

def h034():
    hero = "H034"
    # 通常攻撃（4 種）: 命中の瞬間（attackReleased）に、斧鉤が肉と鉄に食い込む打撃 + 低い芯 + 鎖の小さな鳴り
    for k, (hi, ci, p) in enumerate([(0, 0, 1.0), (1, 2, 0.96), (2, 4, 1.04), (4, 5, 0.99)], start=1):
        x = mix([(0, sn("Two-Handed Axe Flesh Hit", hi, p=0.92 * p, g=0, post=0.15, hit="peak", pre=0.04)),
                 (0.03, sn("10 Hit Deep Thud", p=1.15 * p, g=-6, lp=180, length=0.3, hit=True)),
                 (0.04, sn("Dog_Chain-Hits", ci, p=0.85, g=-12, hp=1500, length=0.3, hit=True))])
        write(f"skill_{hero}_atk_{k}", x, "atk", "斧鉤の打撃（肉と鉄）+ 低い芯 + 鎖の鳴り")
    # 通常攻撃の命中（3 種）: 肉を打つ鈍い音（控えめ）
    for k, part in enumerate(["PUNCH_SMACK_LETTUCE", "FLOG Leather", "PUNCH_PERCUSSIVE_HEAVY"], start=1):
        x = mix([(0, sn(part, k if part == "FLOG Leather" else 0, p=0.85, g=0, post=0.15, hit=True)),
                 (0.0, sn("IMPACT_LOW_THUD", p=0.9, g=-6, hit=True))])
        write(f"skill_{hero}_atkhit_{k}", x, "atkhit", "肉を打つ鈍い音")

    # S1 鎖鉤: 0〜0.33 の振りかぶり（鎖を回す音がふくらむ）→ 0.33 で投げ（風切り・鎖の放り出し）→ 飛ぶ間の鎖の連なり
    s1 = mix([
        (0.0, rise(sn("Jingle_Chain-Sustained", 0, p=0.8, g=-14, length=0.4), 0.3)),
        (0.12, rise(sn("ROPE WHOOSH Fast Light", 3, p=0.6, g=-10, hp=200), 0.12)),
        (0.33, sn("ROPE WHOOSH Fast Light", 0, p=0.75, g=-2, hp=150, hit="peak", pre=0.03)),
        (0.33, sn("Chains_Metal_Dropping", 0, p=0.9, g=-6, hp=400, length=0.25, hit=True)),
        (0.34, sn("10 Hit Deep Thud", p=1.3, g=-16, lp=200, length=0.25, hit=True)),
        (0.38, sn("Movement_Distant_Short", 1, p=1.05, g=-6, hp=600, length=0.55)),
        (0.4, sn("Rattle, Pass By", p=1.1, g=-14, hp=800, start=0.1, length=0.5)),
        (0.38, sn("Heavy_Chain-Foley_On_Wood", 1, p=1.1, g=-4, lp=2500, length=0.6)),
        (0.4, sn("Jingle_Chain-Sustained", 10, p=1.0, g=-6, hp=2500, length=0.55)),
        (0.36, rise(sn("Sub Drop 2", g=-12, lp=140, length=0.6), 0.1)),
    ])
    write(f"skill_{hero}_s1_cast", tail(reverb(s1, 0.4, 0.08, 7), 0.9, 1.05), "cast", "鎖を回す → 投げ（風切り・鎖の放り出し）→ 飛ぶ鎖の連なり",
          target=-21.0)
    # 命中（引き寄せの 0.45 秒前）: 鉤が肉に刺さる重い打撃 + 鉄の鉤 → 0.45 で鎖を引く（金属の連なり・擦れ・体を引く風）
    for k, (pi, ci) in enumerate([(0, 0), (1, 1), (2, 0)], start=1):
        x = mix([
            (0, sn("PUNCH_SIMPLE_CLEAN_DEEP", p=0.8 + 0.04 * k, g=0, hit=True)),
            (0, sn("Heavy Body Crunch", 1, p=0.9, g=-8, length=0.3, hit=True)),
            (0, sn("IMPACT METAL Scratchy Short Punch", p=0.85 + 0.05 * k, g=-8, lp=7000, length=0.3, hit=True)),
            (0.01, sn("Explosive Hit 10", g=-4, length=0.5, hit=True)),
            (0.05, sn("Trailer Hit Cavernous", g=3, lp=150, length=0.3)),
            (0.45, sn("Chains_Metal_Dropping", ci, p=1.0, g=8, hp=500, length=0.5, hit=True)),
            (0.45, sn("Heavy_Chain-Foley_On_Wood", 0, p=1.0, g=4, length=0.35, hit="peak", pre=0.03)),
            (0.45, sn("GRAB_BLOCK_THROW", p=0.8, g=0, hit=True)),
            (0.45, sn("WHIP Snap Crack", p=0.8, g=0, hp=1500, hit="peak", pre=0.02, length=0.25)),
            (0.47, sn("Movement_Distant_Very-Short", p=1.0, g=2, hp=800, length=0.3)),
        ])
        write(f"skill_{hero}_s1_hit_{k}", tail(x, 0.85, 1.05), "hit", "鉤が刺さる重い打撃 + 鉄 → 0.45 秒後に鎖を引く", target=-20.0,
              cap=1.1)

    # S2 鉄鎖旋: 0〜0.27 の短い振り上げ → 0.27 で斧鉤を地に叩きつける（体の芯・低音・土・鉄）→ 低音が 0.5 秒 → 0.8 で消える
    s2 = mix([
        (0.0, rise(sn("Swing 3 Large", p=0.8, g=-2, hp=1200, hit="peak", pre=0.22, length=0.3), 0.12)),
        (0.27, sn("10 Hit Deep Thud", p=0.95, g=5, lp=600, hp=90, length=0.4, hit=True)),
        (0.27, sn("Explosive Hit 10", g=-12, length=0.4, hit=True)),
        (0.27, sn("RL_bodyfall_Dirt", p=0.8, g=-2, length=0.2, hit=True)),
        (0.27, sn("IMPACT METAL Short Slam", p=0.8, g=-10, lp=5000, length=0.12, hit=True)),
        (0.28, sn("GROUND IMPACT Large", g=-14, hp=2500, length=0.5, hit=True)),
        (0.3, rise(sn("Fire_Spell_Dragon", g=-22, hp=3000, start=0.3, length=0.3), 0.05)),
        (0.3, sn("Trailer Hit Cavernous", g=-7, lp=150, length=0.6)),
    ])
    write(f"skill_{hero}_s2_cast", tail(reverb(s2, 0.4, 0.08, 8), 0.75, 1.05), "cast", "短い振り上げ → 叩きつけ（体の芯・低音・土・鉄）→ 低音の尾",
          target=-19.8)
    for k, part in enumerate(["PUNCH_PERCUSSIVE_HEAVY", "IMPACT_LOW_THUD", "PUNCH_DESIGNED_LIGHT"], start=1):
        x = mix([(0, sn(part, p=0.85, g=0, hit=True)), (0, sn("RL_bodyfall_Dirt", p=0.9 + 0.05 * k, g=-16, length=0.25, hit=True))])
        write(f"skill_{hero}_s2_hit_{k}", x, "hit", "衝撃が体に当たる鈍い音 + 土", target=-25.0)

    # 奥義 狩猟鎖獄: 0.25 で掴みかかる一閃（鞭の擦れ・鎖・掴みの打撃。MLBB で一番大きい）→ 拘束の間の掴み合いの擦れと低いうなり
    ult = mix([
        (0.05, rise(sn("ROPE WHOOSH Fast Light", 1, p=0.7, g=-18, hp=200), 0.12)),
        (0.3, sn("Jingle_Chain-Sustained", 0, p=1.1, g=-6, hp=3000, length=0.45)),
        (0.25, sn("WHIP Snap Crack", p=0.75, g=0, hit="peak", pre=0.02)),
        (0.25, sn("GRAB_BLOCK_THROW", p=0.85, g=-2, hit=True)),
        (0.25, sn("Chains_Metal_Dropping", 0, p=0.85, g=-4, hp=400, length=0.4, hit=True)),
        (0.26, sn("Explosive Hit 10", g=-6, length=0.5, hit=True)),
        (0.3, sn("Choking, Tension", p=0.9, g=-4, hp=150, start=0.2, length=1.75)),
        (0.42, sn("LowSwings31", p=1.0, g=-8, hp=300, hit="peak", pre=0.1, length=0.16)),
        (0.74, sn("DesignedSwings12", p=0.95, g=-8, hp=300, hit="peak", pre=0.1, length=0.16)),
        (1.06, sn("LowSwings31", p=1.05, g=-8, hp=300, hit="peak", pre=0.1, length=0.16)),
        (1.38, sn("DesignedSwings12", p=1.0, g=-8, hp=300, hit="peak", pre=0.1, length=0.16)),
        (1.5, sn("Swing 3 Large", p=0.7, g=-8, hp=300, hit="peak", pre=0.08, length=0.15)),
        (1.68, sn("RL_bodyfall_Dirt", p=0.75, g=-6, length=0.25, hit=True)),
        (1.68, sn("10 Hit Deep Thud", p=1.05, g=-10, lp=500, length=0.3, hit=True)),
        (0.3, sn("Heavy Body Crunch", 1, p=0.9, g=-6, hp=150, length=1.75)),
    ])
    write(f"skill_{hero}_ult_cast", tail(reverb(ult, 0.5, 0.1, 9), 1.75, 2.05), "ult", "掴みかかる一閃（鞭・鎖・掴み）→ 拘束の擦れと低いうなり",
          target=-16.0, cap=2.1)
    # 1 撃ごと（6 撃。1 撃 -13〜-15 LUFS）: 拳と斧鉤の重い打撃・骨に響く砕け・低音の芯・鎖の跳ね
    for k, (pi, ci) in enumerate([(0, 0), (1, 1), (2, 0)], start=1):
        x = mix([
            (0, sn("PUNCH_SIMPLE_CLEAN_DEEP", p=0.72 + 0.05 * k, g=0, hp=90, hit=True)),
            (0, sn("IMPACT DARK Epic Punch", p=0.9 + 0.04 * k, g=-4, hp=110, hit="peak", pre=0.02, length=0.45)),
            (0, sn("Heavy Body Crunch", pi, p=0.85, g=-8, length=0.3, hit=True)),
            (0.01, sn("Smash_Gore_Juicy_Smash", 0, p=0.8 + 0.05 * k, g=-8, length=0.4, hit=True)),
            (0.02, sn("Melee_Deep_Wound", p=0.9, g=-10, length=0.3, hit=True)),
            (0.0, sn("Explosive Hit 10", p=1.0 + 0.05 * k, g=-10, length=0.3, hit=True)),
            (0.02, sn("Dog_Chain-Hits", 3 + k, p=0.8, g=-14, hp=1500, length=0.25, hit=True)),
        ])
        write(f"skill_{hero}_ult_hit_{k}", x, "hit", "拳と斧鉤の重い打撃 + 砕け + 低音の芯 + 鎖の跳ね", target=-14.5)

    # パッシブ（闘気がたまり始める）: 0.5 秒かけて低音がふくらむ（逆再生の低い打撃）+ 手の金の光のきらめき
    pas = mix([(0, rise(rev(sn("Trailer Hit Cavernous", g=8, lp=160, length=0.55)), 0.2)),
               (0.42, sn("Trailer Hit Cavernous", g=2, lp=250, length=0.65)),
               (0.0, rise(sn("Ice_Spell_Ice_Spell_Buff_Positive", p=0.8, g=-16, hp=2000, length=1.1), 0.1)),
               (0.3, sn("energy flow, astral travel", p=0.9, g=-9, hp=1500, start=3.0, length=0.8))])
    write(f"skill_{hero}_passive", tail(pas, 0.95, 1.15), "passive", "闘気（低音のふくらみ + 光のきらめき）", target=-22.0)
    return hero


HEROES = {"H029": h029, "H034": h034}


def main(ids):
    for h in ids:
        print(h)
        hero = HEROES[h]()
        # v1 の同じヒーローの命中の音（揺らぎの番号なし）は消す（揺らぎと一緒に読まれないように）
        for f in os.listdir(OUT):
            if f.startswith(f"skill_{hero}_") and f.endswith("_hit.caf"):
                os.remove(os.path.join(OUT, f))
    old = json.load(open(RECORD, encoding="utf-8")) if os.path.exists(RECORD) else {}
    old.update(RECORDS)
    json.dump(old, open(RECORD, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1, sort_keys=True)
    B.write_doc()


if __name__ == "__main__":
    main(sys.argv[1:] or list(HEROES))
