"""VELSTRIA の音の素材を作る（CC0 の素材を落とし、重ね・切り出し・音量の揃え・残響を足して App/Resources/Audio へ書く）。

使い方:
    python tools/audio/build_audio.py            # 全部
    python tools/audio/build_audio.py ui music   # 一部（ui / music / skills）

- 素材は tools/audio/.cache に落とす（リポジトリに入れない。.gitignore）。出力は加工した完成品だけ。
- 使ってよい素材は CC0 だけ（Kenney の音の素材集・OpenGameArt の CC0 の曲）。MLBB の音は使わない。
- 出力: 効果音 = 44.1 kHz モノラル 16 bit の .caf（AudioService の効果音の形式そのまま）、
  BGM = 44.1 kHz ステレオ AAC の .m4a（流し読み）。
- 出典・ライセンス・URL は docs/audio/SOURCES.md に書き出す（アプリ内は CreditsView の「音楽・効果音」）。
必要なもの: Python 3.10+、numpy、scipy、imageio-ffmpeg（ffmpeg の実行ファイルを使う）。
"""
import glob
import io
import os
import re
import subprocess
import sys
import json
import urllib.parse
import urllib.request
import zipfile

import imageio_ffmpeg
import numpy as np
from scipy import signal

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CACHE = os.path.join(os.path.dirname(__file__), ".cache")
OUT = os.path.join(ROOT, "App", "Resources", "Audio")
DOC = os.path.join(ROOT, "docs", "audio", "SOURCES.md")
FF = imageio_ffmpeg.get_ffmpeg_exe()
SR = 44100

# MARK: 素材（すべて CC0 1.0）

KENNEY = "https://kenney.nl/media/pages/assets/"
SOURCES = {
    "interface": dict(kind="zip", url=KENNEY + "interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
                      title="Interface Sounds", author="Kenney", page="https://kenney.nl/assets/interface-sounds"),
    "impact": dict(kind="zip", url=KENNEY + "impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
                   title="Impact Sounds", author="Kenney", page="https://kenney.nl/assets/impact-sounds"),
    "rpg": dict(kind="zip", url=KENNEY + "rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
                title="RPG Audio", author="Kenney", page="https://kenney.nl/assets/rpg-audio"),
    "scifi": dict(kind="zip", url=KENNEY + "sci-fi-sounds/6b296f9ecf-1677589334/kenney_sci-fi-sounds.zip",
                  title="Sci-Fi Sounds", author="Kenney", page="https://kenney.nl/assets/sci-fi-sounds"),
    "digital": dict(kind="zip", url=KENNEY + "digital-audio/216eac4753-1677590265/kenney_digital-audio.zip",
                    title="Digital Audio", author="Kenney", page="https://kenney.nl/assets/digital-audio"),
    "jingles": dict(kind="zip", url=KENNEY + "music-jingles/f37e530b9e-1677590399/kenney_music-jingles.zip",
                    title="Music Jingles", author="Kenney", page="https://kenney.nl/assets/music-jingles"),
    "casino": dict(kind="zip", url=KENNEY + "casino-audio/2472606a04-1721639069/kenney_casino-audio.zip",
                   title="Casino Audio", author="Kenney", page="https://kenney.nl/assets/casino-audio"),
    "legend": dict(kind="file", url="https://opengameart.org/sites/default/files/A%20Legend%20Will%20Rise.mp3",
                   title="A Legend Will Rise", author="CodeManu",
                   page="https://opengameart.org/content/a-legend-will-rise-orchestral"),
    "fantasia": dict(kind="file", url="https://opengameart.org/sites/default/files/FantasyOrchestralTheme_1.mp3",
                     title="Fantasy Orchestral Theme", author="Joth",
                     page="https://opengameart.org/content/fantasy-orchestral-theme"),
    "treasure": dict(kind="file", url="https://opengameart.org/sites/default/files/treasure_hunter_0.mp3",
                     title="Treasure Hunter", author="TAD", page="https://opengameart.org/content/treasure-hunter"),
    "onceupon": dict(kind="file", url="https://opengameart.org/sites/default/files/once_upon_a_time_loop.wav",
                     title="Once Upon a Time (loop)", author="TAD",
                     page="https://opengameart.org/content/once-upon-a-time-loop"),
    "battle": dict(kind="file", url="https://opengameart.org/sites/default/files/Battle.mp3",
                   title="Battle Theme", author="Wolfgang_", page="https://opengameart.org/content/battle-theme-0"),
    "finalstand": dict(kind="file", url="https://opengameart.org/sites/default/files/final_stand.wav",
                       title="Final Stand", author="iamoneabe", page="https://opengameart.org/content/final-stand"),
    "introcue": dict(kind="file", url="https://opengameart.org/sites/default/files/intro-cue-norm.wav",
                     title="Intro Cue", author="Vehicle", page="https://opengameart.org/content/intro-cue"),
    "athome": dict(kind="file", url="https://opengameart.org/sites/default/files/cinematic-calm.wav",
                   title="At Home (orchestral)", author="Wolfgang_",
                   page="https://opengameart.org/content/at-home-orchestral"),
}
LICENSE = "CC0 1.0（https://creativecommons.org/publicdomain/zero/1.0/）"


def fetch(key):
    """素材を .cache に落として、zip なら展開したフォルダ、単体ならファイルのパスを返す。"""
    s = SOURCES[key]
    os.makedirs(CACHE, exist_ok=True)
    name = s["url"].rsplit("/", 1)[-1]
    path = os.path.join(CACHE, key + "_" + urllib.parse.unquote(name).replace(" ", "_"))
    if not os.path.exists(path):
        req = urllib.request.Request(s["url"], headers={"User-Agent": "Mozilla/5.0"})
        data = urllib.request.urlopen(req, timeout=120).read()
        with open(path, "wb") as f:
            f.write(data)
    if s["kind"] == "zip":
        d = path[:-4]
        if not os.path.isdir(d):
            zipfile.ZipFile(path).extractall(d)
        return d
    return path


def find(key, stem):
    """zip の素材集の中のファイル（拡張子なしの名前）。"""
    d = fetch(key)
    hits = [p for p in glob.glob(os.path.join(d, "**", stem + ".*"), recursive=True)
            if p.lower().endswith((".ogg", ".wav", ".mp3"))]
    if not hits:
        raise FileNotFoundError(f"{key}/{stem}")
    return sorted(hits)[0]


# MARK: 信号処理

def decode(path, channels=1):
    b = subprocess.run([FF, "-v", "quiet", "-i", path, "-f", "f32le", "-ac", str(channels), "-ar", str(SR), "-"],
                       capture_output=True, check=True).stdout
    x = np.frombuffer(b, dtype=np.float32).copy()
    return x.reshape(-1, channels) if channels > 1 else x


def trim(x, db=-48):
    thr = 10 ** (db / 20) * max(1e-9, np.abs(x).max())
    idx = np.nonzero(np.abs(x) > thr)[0]
    return x[idx[0]:idx[-1] + 1] if len(idx) else x


def db(x, d):
    return x * (10 ** (d / 20))


def pitch(x, ratio):
    """再生速度を変えて音程を変える（ratio > 1 で高く短く）。"""
    if abs(ratio - 1) < 1e-4:
        return x
    n = max(8, int(len(x) / ratio))
    return signal.resample(x, n).astype(np.float32)


def lowpass(x, hz):
    sos = signal.butter(4, hz, "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0).astype(np.float32)


def highpass(x, hz):
    sos = signal.butter(2, hz, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0).astype(np.float32)


def fade(x, fin=0.0, fout=0.01):
    x = x.copy()
    a, b = min(int(fin * SR), len(x) // 2), min(int(fout * SR), len(x) // 2)
    if a > 1:
        x[:a] *= np.linspace(0, 1, a, dtype=np.float32)[:, None] if x.ndim > 1 else np.linspace(0, 1, a, dtype=np.float32)
    if b > 1:
        ramp = np.linspace(1, 0, b, dtype=np.float32)
        x[-b:] *= ramp[:, None] if x.ndim > 1 else ramp
    return x


def reverb(x, seconds=0.6, mix=0.25, seed=1, damp=4000):
    """残響: 指数で減衰する雑音を畳み込む（暗めにして足す）。"""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    ir = rng.standard_normal(n).astype(np.float32) * np.exp(-np.linspace(0, 7, n)).astype(np.float32)
    ir = lowpass(ir, damp)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    wet = signal.fftconvolve(np.concatenate([x, np.zeros(n, np.float32)]), ir)[: len(x) + n].astype(np.float32)
    dry = np.concatenate([x, np.zeros(n, np.float32)])
    return dry * (1 - mix) + wet * mix


def noise_burst(seconds, lo, hi, attack=0.01, seed=3):
    """風切り音など: 帯域を絞った雑音の山（立ち上がり attack 秒、残りで減衰）。"""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    x = rng.standard_normal(n).astype(np.float32)
    sos = signal.butter(2, [lo, hi], "band", fs=SR, output="sos")
    x = signal.sosfilt(sos, x).astype(np.float32)
    t = np.linspace(0, seconds, n, dtype=np.float32)
    env = np.minimum(1, t / max(1e-4, attack)) * np.exp(-np.maximum(0, t - attack) * 6 / seconds)
    return x * env


def mix(layers, tail=0.0):
    """(開始秒, 音) の重ね。"""
    end = max(int(t * SR) + len(s) for t, s in layers) + int(tail * SR)
    out = np.zeros(end, np.float32)
    for t, s in layers:
        i = int(t * SR)
        out[i:i + len(s)] += s
    return out


def normalize(x, peak_db=-2.0):
    p = np.abs(x).max()
    return x if p < 1e-9 else x * (10 ** (peak_db / 20) / p)


# MARK: 書き出し

RECORDS = []


def write_sfx(name, x, sources, note, keep_head=False):
    """効果音: 44.1 kHz モノラル 16 bit の .caf。keep_head: 頭の無音を切らない（0 秒 = 鳴らす時刻のスキルの音。溜めが
    無音から始まっても、着弾の時刻を演出・sim の時刻からずらさない）。"""
    if keep_head:
        thr = 10 ** (-60 / 20) * max(1e-9, np.abs(x).max())
        idx = np.nonzero(np.abs(x) > thr)[0]
        x = x[:idx[-1] + 1] if len(idx) else x
        x = fade(normalize(x), 0.0, 0.012)
    else:
        x = fade(normalize(trim(x, -60)), 0.0, 0.012)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".caf")
    subprocess.run([FF, "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "pcm_s16le", "-f", "caf", path], input=x.astype(np.float32).tobytes(), check=True)
    RECORDS.append((name + ".caf", sources, note, len(x) / SR))
    print(f"  {name}.caf {len(x)/SR:.2f}s")


def write_music(name, key, note, rms_db=-17.0, fout=2.0):
    """BGM: 44.1 kHz ステレオ AAC 160 kbps の .m4a（音量を揃え、頭と終わりをなだらかにしてループのつなぎ目を目立たなくする）。"""
    x = decode(fetch(key), channels=2)
    x = x[int(0.0 * SR):]
    rms = np.sqrt(np.mean(x ** 2)) + 1e-9
    g = 10 ** (rms_db / 20) / rms
    g = min(g, 10 ** (-1.0 / 20) / (np.abs(x).max() + 1e-9))
    x = fade(x * g, 0.08, fout)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".m4a")
    subprocess.run([FF, "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "aac", "-b:a", "160k", path], input=x.astype(np.float32).tobytes(), check=True)
    RECORDS.append((name + ".m4a", [key], note, len(x) / SR))
    print(f"  {name}.m4a {len(x)/SR:.1f}s")


def K(key, stem):
    """素材集のファイルをモノラルで読む。"""
    return trim(decode(find(key, stem)), -55)


# MARK: 画面の効果音

def build_ui():
    print("ui")
    write_sfx("sfx_ui_tap", K("interface", "select_002"), ["interface"], "select_002")
    write_sfx("sfx_ui_confirm", K("interface", "confirmation_001"), ["interface"], "confirmation_001")
    write_sfx("sfx_ui_back", K("interface", "back_002"), ["interface"], "back_002")
    write_sfx("sfx_ui_tab", db(K("interface", "switch_002"), -2), ["interface"], "switch_002")
    write_sfx("sfx_ui_error", K("interface", "error_004"), ["interface"], "error_004")
    write_sfx("sfx_countdown", mix([(0, K("interface", "tick_004")), (0, db(K("interface", "bong_001"), -4))]), ["interface"],
              "tick_004 + bong_001 を重ねた（残り秒の秒読み）")
    write_sfx("sfx_purchase", mix([(0, K("casino", "chips-stack-1")), (0.05, db(K("interface", "confirmation_003"), -5))]),
              ["casino", "interface"], "chips-stack-1 + confirmation_003 を重ねた")
    write_sfx("sfx_reward", reverb(mix([(0, K("jingles", "jingles_PIZZI10")), (0.02, db(K("interface", "glass_001"), -8))]),
                                   0.7, 0.22, seed=11),
              ["jingles", "interface"], "jingles_PIZZI10 + glass_001、残響")
    write_sfx("sfx_victory", reverb(mix([(0, K("jingles", "jingles_HIT11")), (0.05, db(K("jingles", "jingles_PIZZI02"), -3))]),
                                    1.2, 0.3, seed=12),
              ["jingles"], "jingles_HIT11 + jingles_PIZZI02、残響（勝利）")
    write_sfx("sfx_defeat", reverb(mix([(0, lowpass(K("jingles", "jingles_HIT09"), 5000)),
                                        (0.08, db(K("jingles", "jingles_PIZZI01"), -4))]), 1.2, 0.3, seed=13),
              ["jingles"], "jingles_HIT09（こもらせた）+ jingles_PIZZI01、残響（敗北）")
    write_sfx("sfx_match_found", reverb(mix([(0, K("jingles", "jingles_HIT10")), (0.03, db(K("jingles", "jingles_PIZZI15"), -4))]),
                                        0.9, 0.25, seed=14),
              ["jingles"], "jingles_HIT10 + jingles_PIZZI15、残響（マッチ成立）")
    write_sfx("sfx_lock_in", mix([(0, K("jingles", "jingles_HIT07")), (0, db(lowpass(K("impact", "impactMetal_heavy_000"), 6000), -6)),
                                  (0.03, db(K("interface", "confirmation_002"), -8))]),
              ["jingles", "impact", "interface"], "jingles_HIT07 + impactMetal_heavy_000 + confirmation_002（ピック確定）")
    write_sfx("sfx_ban", mix([(0, K("jingles", "jingles_HIT13")), (0, db(pitch(K("impact", "impactPunch_heavy_000"), 0.8), -3)),
                              (0.02, db(lowpass(K("digital", "lowDown"), 2500), -9))]),
              ["jingles", "impact", "digital"], "jingles_HIT13 + impactPunch_heavy_000（低く）+ lowDown（バン）")
    write_sfx("sfx_match_start", reverb(mix([(0, K("jingles", "jingles_HIT03")),
                                             (0, db(lowpass(pitch(K("impact", "impactPlate_heavy_000"), 0.75), 3000), -4)),
                                             (0.12, db(K("jingles", "jingles_HIT15"), -5))]), 1.4, 0.32, seed=15),
              ["jingles", "impact"], "jingles_HIT03 + impactPlate_heavy_000（低く）+ jingles_HIT15、残響（試合開始の合図）")


# MARK: BGM

def build_music():
    print("music")
    write_music("bgm_home_legend", "legend", "ホームの選べる曲「伝説の夜明け」")
    write_music("bgm_home_fantasia", "fantasia", "ホームの選べる曲「幻想の序曲」")
    write_music("bgm_home_journey", "treasure", "ホームの選べる曲「宝探しの旅」")
    write_music("bgm_lobby", "onceupon", "ロビー・パーティ・ヒーロー選択（通常）")
    write_music("bgm_draft", "battle", "ヒーロー選択（ピック）")
    write_music("bgm_draft_tense", "finalstand", "ヒーロー選択の残り時間が少ない時")
    write_music("bgm_loading", "introcue", "ロード画面（試合開始へつなぐ）")
    write_music("bgm_result", "athome", "結果画面")


# MARK: 出典の一覧

RECORD_FILE = os.path.join(os.path.dirname(__file__), "outputs.json")


RECORD_V2 = os.path.join(os.path.dirname(__file__), "outputs_v2.json")
SONNISS_LICENSE = "https://sonniss.com/gdc-bundle-license/"
SONNISS_PAGE = "https://gdc.sonniss.com/"


def sonniss_packs(v2):
    """v2 の音に使った Sonniss の素材集（(年, 素材集) の並び）。"""
    packs = set()
    for r in v2.values():
        for s in r["sources"]:
            year, pack = s.split(" / ", 1)
            if year != "kenney":
                packs.add((year, pack))
    return sorted(packs)


def write_doc():
    """出力の記録（outputs.json・outputs_v2.json。一部だけ作り直しても残りを保つ）から docs/audio/SOURCES.md を書く。"""
    rec = json.load(open(RECORD_FILE, encoding="utf-8")) if os.path.exists(RECORD_FILE) else {}
    for name, srcs, note, dur in RECORDS:
        rec[name] = {"sources": srcs, "note": note, "seconds": round(dur, 2)}
    v2 = json.load(open(RECORD_V2, encoding="utf-8")) if os.path.exists(RECORD_V2) else {}
    # v2（skill_sounds_v2.py）で作り直した音・消した音（v1 の命中の音）は v1 の記録から外す
    rec = {k: v for k, v in rec.items() if k not in v2 and os.path.exists(os.path.join(OUT, k))}
    v2 = {k: v for k, v in v2.items() if os.path.exists(os.path.join(OUT, k))}
    json.dump(rec, open(RECORD_FILE, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1, sort_keys=True)
    os.makedirs(os.path.dirname(DOC), exist_ok=True)
    lines = ["# 音の素材の出典（自動生成: tools/audio/build_audio.py）", "",
             "アプリに入れている音のファイルは、下の CC0 の素材を加工（切り出し・重ね・音程・音量・残響・形式の変換）したもの。",
             "MLBB の音は使っていない。素材の原本・素材集の形ではリポジトリに入れない（tools/audio/.cache に落として加工する）。",
             f"ライセンス: すべて {LICENSE}。帰属表示は必須ではないが、アプリ内の「クレジット > 音楽・効果音」と下の表に記す。", "",
             "## 素材", "", "| 素材 | 作者 | ライセンス | URL |", "|---|---|---|---|"]
    for k, s in SOURCES.items():
        lines.append(f"| {s['title']} | {s['author']} | CC0 1.0 | {s['page']} |")
    lines += ["", "## 出力（App/Resources/Audio）", "", "| ファイル | 長さ | 素材 | 加工 |", "|---|---|---|---|"]
    for name in sorted(rec):
        r = rec[name]
        lines.append(f"| {name} | {r['seconds']:.2f} 秒 | {'・'.join(SOURCES[s]['title'] for s in r['sources'])} | {r['note']} |")
    if v2:
        lines += ["", "## Sonniss GDC Game Audio Bundle（ヒーロー固有の音: tools/audio/skill_sounds_v2.py）", "",
                  "Sonniss の GDC Game Audio Bundle（無料・商用可・帰属表示は不要。素材のまま再配布・販売しない、AI の学習に使わない）の",
                  "録音を、重ね・切り出し・音程・帯域・音量・残響で加工した完成品だけを置く（原本・素材集の形ではリポジトリに入れない）。",
                  f"ライセンス: {SONNISS_LICENSE}　配布: {SONNISS_PAGE}（同じ素材を archive.org の写し",
                  "sonniss-gdc-<年>-game-audio-bundle-normalized から、使う素材集だけ落とした。tools/audio/sonniss_fetch.py）。", "",
                  "| 素材集 | 作者 | ライセンス | URL |", "|---|---|---|---|"]
        for year, pack in sonniss_packs(v2):
            author, title = (re.split(r" [-–] ", pack, maxsplit=1) + [""])[:2]
            lines.append(f"| {title or pack}（GDC {year}） | {author.strip()} | Sonniss GDC | {SONNISS_PAGE} |")
        lines += ["", "### 出力（App/Resources/Audio、48 kHz）", "", "| ファイル | 長さ | 素材 | 加工 |", "|---|---|---|---|"]
        for name in sorted(v2):
            r = v2[name]
            src = "・".join(s.split(" / ", 1)[1] for s in r["sources"])
            lines.append(f"| {name} | {r['seconds']:.2f} 秒 | {src} | {r['note']} |")
    open(DOC, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    parts = sys.argv[1:] or ["ui", "music", "skills"]
    if "ui" in parts:
        build_ui()
    if "music" in parts:
        build_music()
    if "skills" in parts:
        try:
            import skill_sounds
            skill_sounds.build(sys.modules[__name__])
        except ModuleNotFoundError:
            print("skills: skill_sounds.py がまだ無い")
    write_doc()
