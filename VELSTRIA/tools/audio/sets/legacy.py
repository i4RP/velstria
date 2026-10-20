"""旧 24 体（H001〜H024）のスキルの音（発動 3 つ・命中 2 種 × 3 つ）。合成・電子音の汎用の発動の音の代わり。

旧 24 体のスキルは演出（Effekseer）が固有で、音は無かった（汎用の発動の音）。名前の属性（城門の聖・星弦・月・潮・黒雷・岩脈・風・機巧・
焔・鉄翼・玻璃・獣・霧・戦鐘・白環・深淵鎖・花星・砦砕・光矢・時砂・蒼爪・雷槍・夢織）と武器から、属性の本物の録音の層と
武器の組の音（sets/weapons.py が作った wpn_<組>_*）を重ねる。
- S1 の発動: 武器の振り・発射（0 秒）+ 属性の放ち
- S2 の発動: 属性の放ち（別の録音・音程）+ 風切り
- 奥義の発動: 属性の溜め（0〜0.55 秒）→ 0.55 秒に武器の会心 + 属性の炸裂
- 命中（S1・S2・奥義 × 2 種）: 属性の当たり（奥義は炸裂の短いもの + 低い芯）
時刻は前寄せ（旧 24 体の判定の遅れはスキルごとにまちまちなので、命中の音が着弾の時刻に鳴る）。
"""
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import sfxlib as L  # noqa: E402


def own(name, p=1.0, g=0.0, length=None):
    """もう作った音（App/Resources/Audio/<name>.caf。武器の組など）を層として読む。"""
    path = os.path.join(L.OUT, name + ".caf")
    b = subprocess.run([L.S.FF, "-v", "quiet", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(L.SR), "-"],
                       capture_output=True, check=True).stdout
    x = np.frombuffer(b, np.float32).copy()
    if length is not None:
        x = L.B.fade(x[:int(length * L.SR)], 0.0, min(0.05, length / 3))
    if p != 1.0:
        x = L.B.pitch(x, p)
    return L.B.db(x, g)


# MARK: 属性の層（cast = 放ち、hit = 当たり（2 種）、swell = 溜め、burst = 炸裂）。i = 揺らぎ、p = 音程

def holy():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("Bell_Waiter_Fienup_001", p=[0.9, 1.1][i] * p, g=-4, hit=True, length=0.6)),
                               (0.0, sn("Whoosh,Sound Design,Airy,Full,Soft,Buffet,Medium", p=1.2 * p, g=-10, hp=800, length=0.4))]),
        hit=lambda i, p: mix([(0.0, sn("Impact,Sound Design,Hit,Chime,Resonant Hit", p=[1.0, 1.2][i] * p, g=-2, hit=True, length=0.5)),
                              (0.0, sn("punch_general_body_impact_03", p=0.8 * p, g=-10, hit=True))]),
        swell=lambda p: rise(sn("Bowed Cymbal 2_Mids Lows_Fienup_009", p=p, g=0, start=0.5, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("80,TheGong", p=1.1 * p, g=0, hit=True, length=1.0)),
                             (0.0, sn("Smash B", p=1.0, g=-6, lp=3000, length=0.5, hit=True))]))


def crystal():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("Wine Glass Hit Higher Pitch", p=[1.0, 1.2][i] * p, g=-2, hit=True, length=0.5)),
                               (0.0, sn("GLASMisc_Reverse Glass Effect", p=1.1 * p, g=-8, length=0.5))]),
        hit=lambda i, p: mix([(0.0, sn("SHARDS [LD Mono] 02 - Impact, Glass, Shatter, Small", p=[1.0, 1.15][i] * p, g=0, hit=True, length=0.5))]),
        swell=lambda p: rise(sn("Tall Narrow, Tone, Rubbing, Musical_01", p=p, g=0, start=0.5, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("Glass_Break_Vase_D50_Fienup_003", p=1.0 * p, g=0, hit=True, length=0.9)),
                             (0.0, sn("Smash B", p=1.1, g=-8, lp=3000, length=0.4, hit=True))]))


def moon():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("GLASMisc_Reverse Glass Effect", p=[0.85, 0.95][i] * p, g=-2, length=0.6)),
                               (0.0, sn("Whoosh,Sound Design,Airy,Full,Soft,Buffet,Medium", p=1.0 * p, g=-8, length=0.4))]),
        hit=lambda i, p: mix([(0.0, sn("Wine Glass Hit Higher Pitch", p=[0.7, 0.8][i] * p, g=0, hit=True, length=0.5)),
                              (0.0, sn("punch_general_body_impact_03", p=0.8 * p, g=-12, hit=True))]),
        swell=lambda p: rise(sn("Tall Narrow, Tone, Rubbing, Musical_01", p=0.8 * p, g=0, start=1.0, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("Glass_Break_Pane_702T_Fienup_005", p=0.85 * p, g=0, hit=True, length=0.8)),
                             (0.0, sn("SINGING_BOWL_Strike_Sustain_D_02", p=1.1 * p, g=-6, hit=True, length=1.0))]))


def water():
    return dict(
        cast=lambda i, p: mix([(0.0, sn(["water_splash_small_008", "water_splash_drop_006"][i], p=p, g=0, hit=True, length=0.5)),
                               (0.0, sn("Whoosh,Sound Design,Airy,Full,Soft,Buffet,Medium", p=1.1 * p, g=-10, length=0.4))]),
        hit=lambda i, p: mix([(0.0, sn(["LIQUID HIT Lake, Branch, Splash", "water_splash_drop_006"][i], p=p, g=0, hit=True, length=0.5))]),
        swell=lambda p: rise(sn("SFX Medium Wave Splash on Rocks 12", p=p, g=0, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("Bluezone_BC0256_water_splash_008", p=0.95 * p, g=0, hit=True, length=1.0)),
                             (0.0, sn("10 Hit Deep Thud", p=1.0, g=-8, lp=200, length=0.4, hit=True))]))


def lightning():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("ELECZap_Bug zapper zapping", p=[1.0, 0.9][i] * p, g=0, hit=True, length=0.4)),
                               (0.02, sn("Arc Weld Electrical Sparks 3", 1, p=p, g=-6, hp=1000, start=1.0 + i, length=0.35))]),
        hit=lambda i, p: mix([(0.0, sn("High Voltage Electric Arcs 2", p=p, g=0, start=2.0 + 0.7 * i, length=0.35)),
                              (0.0, sn("Damp Electric Shock 8", p=p, g=-6, start=1.0 + 0.5 * i, length=0.3))]),
        swell=lambda p: rise(sn("electric_hum_buzz_01", p=p, g=6, start=1.0, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("Thunder_Crack_Fienup_016", p=1.0 * p, g=0, length=1.1)),
                             (0.0, sn("High Voltage Electric Arcs 2", p=0.9 * p, g=-4, start=4.0, length=0.4))]))


def earth():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("Hit Rock into Gravel_RBDII 06", p=[1.0, 0.9][i] * p, g=0, hit=True, length=0.5)),
                               (0.0, sn("10 Hit Deep Thud", p=1.0 * p, g=-8, lp=250, length=0.3, hit=True))]),
        hit=lambda i, p: mix([(0.0, sn(["Hit Rock Debris_RBD 02", "Smash Rock On Debris_RBD 04"][i], p=p, g=0, hit=True, length=0.5))]),
        swell=lambda p: rise(sn("earthquake_rumble_large_005", p=p, g=0, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("GROUND IMPACT Large", p=0.9 * p, g=0, hit=True, length=1.0)),
                             (0.0, sn("Explosive Hit 10", g=-4, length=0.6, hit=True))]))


def wind():
    return dict(
        cast=lambda i, p: mix([(0.0, sn(["WHSH_Airy-Whoosh Wind Gust 11", "MAGIC AIR Large Whoosh"][i], p=p, g=0, hit="peak", pre=0.15, length=0.5))]),
        hit=lambda i, p: mix([(0.0, sn("Glove,Airy,Breathy,Punchy", p=[0.8, 0.9][i] * p, g=-2, hit="peak", pre=0.03, length=0.2)),
                              (0.0, sn("punch_general_body_impact_03", p=0.9 * p, g=-6, hit=True))]),
        swell=lambda p: rise(sn("Wind, Rush, Whoosh", p=p, g=0, hp=200, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("WHSH_Airy-Whoosh Wind Gust 11", p=0.8 * p, g=0, hit="peak", pre=0.05, length=0.7)),
                             (0.0, sn("Smash B", p=1.1, g=-8, lp=2500, length=0.4, hit=True))]))


def mech():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("gun_semi_auto_rifle_cock_02", p=[1.0, 0.9][i] * p, g=-2, hit=True, length=0.4)),
                               (0.05, sn("Compressed Air 06 Hiss and Spurt", p=p, g=-6, length=0.4))]),
        hit=lambda i, p: mix([(0.0, sn(["Hit Impact Metal Scrap Debris_UC 06", "Toolbox - DROP"][i], i, p=p, g=0, hit=True, length=0.45))]),
        swell=lambda p: rise(sn("Rotation,Metal,Crank,Gears,Squeak,Rattle,Loop,Short", p=p, g=0, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("Steam Blast,Tube or Pipe,Distant", p=1.0 * p, g=-2, length=0.9)),
                             (0.0, sn("Iron - Thick - HIT - Hammer", 3, p=0.8 * p, g=0, hit=True, post=0.3))]))


def fire():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("torch_whoosh_20", p=[1.0, 0.85][i] * p, g=0, hit="peak", pre=0.1, length=0.5)),
                               (0.05, sn("Fire_Spell_Dragon", p=p, g=-8, hp=1000, length=0.5))]),
        hit=lambda i, p: mix([(0.0, sn("Designed Fire - Impacts - Large, ignition 03", p=[1.05, 0.95][i] * p, g=0, hit=True, length=0.6))]),
        swell=lambda p: rise(sn("Designed Fire - Swooshes - Burst, evolving 34", p=p, g=0, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("EXPLReal_Medium Realistic Explosion 15", p=1.0 * p, g=0, hit=True, length=1.0)),
                             (0.0, sn("Designed Fire - Impacts - Large, ignition 03", p=0.9 * p, g=-4, hit=True, length=0.7))]))


def metal():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("METAL SWING HIT", p=[1.0, 0.9][i] * p, g=0, hit="peak", pre=0.12, length=0.5))]),
        hit=lambda i, p: mix([(0.0, sn(["Iron - Thick - HIT - Hammer", "heavy_metal_impact_metal_plate_medium"][i], 2 * i, p=p, g=0, hit=True, length=0.5))]),
        swell=lambda p: rise(rev(sn("Haunted Metal Vol 1_18", p=p, g=0, lp=4000, length=0.6)), 0.3),
        burst=lambda p: mix([(0.0, sn("Metal,Crash,Concrete,Sheet Metal", p=1.0 * p, g=0, hit=True, length=1.0)),
                             (0.0, sn("Smash B", p=1.0, g=-6, length=0.5, hit=True))]))


def beast():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("EFX INT Dog Growl 33 A", p=[0.7, 0.62][i] * p, g=-4, length=0.6)),
                               (0.0, sn("punch_general_body_impact_03", p=0.8 * p, g=-6, hit=True))]),
        hit=lambda i, p: mix([(0.0, sn(["punch_general_body_impact_03", "Heavy Body Crunch"][i], i, p=0.85 * p, g=0, hit=True, length=0.4))]),
        swell=lambda p: rise(sn("EFX INT Dog Snarling 24 C", p=0.6 * p, g=0, length=0.6), 0.4),
        burst=lambda p: mix([(0.0, sn("GROUND IMPACT Large", p=0.85 * p, g=0, hit=True, length=0.9)),
                             (0.0, sn("Heavy Body Crunch", 1, p=0.8 * p, g=-6, length=0.5, hit=True))]))


def mist():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("Whoosh,Sound Design,Airy,Full,Soft,Shudder,Very Slow,Aftershock", p=[1.6, 1.8][i] * p, g=0, length=0.5)),
                               (0.05, sn("Compressed Air 06 Hiss and Spurt", p=1.2 * p, g=-10, length=0.3))]),
        hit=lambda i, p: mix([(0.0, sn("medium metal blade wet impact", p=[1.1, 1.0][i] * p, g=0, hit=True, length=0.3)),
                              (0.0, sn("Glove,Airy,Breathy,Punchy", p=1.2 * p, g=-8, hit="peak", pre=0.03, length=0.2))]),
        swell=lambda p: rise(sn("Whoosh,Sound Design,Airy,Full,Soft,Shudder,Very Slow,Aftershock", p=p, g=0, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("Knife_Sword_Hit_Multiple", 0, p=0.9 * p, g=0, hit=True, length=0.25)),
                             (0.08, sn("Knife_Sword_Hit_Multiple", 1, p=0.85 * p, g=-2, hit=True, length=0.25)),
                             (0.16, sn("Machete_Hit_Ring", 1, p=0.9 * p, g=-4, hit=True, length=0.6))]))


def bell():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("Bell_Waiter_Fienup_001", p=[0.7, 0.6][i] * p, g=0, hit=True, length=0.7))]),
        hit=lambda i, p: mix([(0.0, sn("Bell_Waiter_Fienup_001", p=[0.55, 0.65][i] * p, g=-4, hit=True, length=0.5)),
                              (0.0, sn("punch_general_body_impact_03", p=0.8 * p, g=-6, hit=True))]),
        swell=lambda p: rise(rev(sn("PotGong", p=1.1 * p, g=0, hit=True, length=0.6)), 0.2),
        burst=lambda p: mix([(0.0, sn("PotGong", p=0.9 * p, g=0, hit=True, length=1.2)),
                             (0.0, sn("Automatic Cannon - MK44", 0, p=0.9 * p, g=-4, hit=True, length=0.6))]))


def dark():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("MAGEvil_Dark Spell Dark Energy Attack", p=[1.0, 0.85][i] * p, g=0, hit=True, length=0.6)),
                               (0.05, sn("Heavy_Chain-Foley_On_Wood", 1, p=1.0 * p, g=-8, lp=3000, length=0.4))]),
        hit=lambda i, p: mix([(0.0, sn(["med_dark_001", "IMPACT DARK Epic Punch"][i], p=p, g=0, hit=True, length=0.5))]),
        swell=lambda p: rise(rev(sn("Haunted Metal Vol 1_18", p=0.9 * p, g=0, length=0.6)), 0.3),
        burst=lambda p: mix([(0.0, sn("Bluezone_BC0250_impact_metal_01", p=0.9 * p, g=0, hit=True, length=0.9)),
                             (0.0, sn("Chains_Metal_Dropping", 1, p=0.9 * p, g=-6, length=0.5, hit=True))]))


def nature():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("leaves_pile_pick_up_04", p=[1.1, 1.0][i] * p, g=0, length=0.5)),
                               (0.05, sn("windchimes,mixed,paper,aluminum", p=1.2 * p, g=0, length=0.6))]),
        hit=lambda i, p: mix([(0.0, sn("tree_dead_tree_limb_impact_05", p=[1.1, 1.0][i] * p, g=0, hit=True, length=0.4)),
                              (0.0, sn("leaves_pile_pick_up_04", p=1.2 * p, g=-8, length=0.3))]),
        swell=lambda p: rise(sn("windchimes,mixed,paper,aluminum", p=p, g=8, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("tree_bark_rotten_rip_03", p=1.0 * p, g=0, hit=True, length=0.6)),
                             (0.0, sn("Smash B", p=1.1, g=-6, lp=2500, length=0.4, hit=True))]))


def sand():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("impact_gritty_grit_sandy_dirt_dig_shovel", p=[1.0, 0.9][i] * p, g=0, hit=True, length=0.5)),
                               (0.05, sn("Cuckoo Clock, Wind-up_01", 1, p=1.0 * p, g=-8, length=0.4))]),
        hit=lambda i, p: mix([(0.0, sn(["Hit Rock into Gravel_RBDII 06", "impact_gritty_grit_sandy_dirt_dig_shovel"][i], p=1.05 * p, g=0, hit=True, length=0.45))]),
        swell=lambda p: rise(sn("sand falling on scrapwood", p=p, g=0, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("gun_rifle_sniper_shot_01", p=0.85 * p, g=0, hit=True, length=0.6)),
                             (0.0, sn("Hit Rock into Gravel_RBDII 06", p=0.8 * p, g=-4, hit=True, length=0.5))]))


def frost():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("Ice_impact_lite_02", p=[1.1, 1.0][i] * p, g=0, hit=True, length=0.3)),
                               (0.02, sn("dry ice sizzle - serrated", p=p, g=-8, start=0.5 + i, length=0.4))]),
        hit=lambda i, p: mix([(0.0, sn(["Ice_smash_light_02", "Ice_chunk_heavy_07"][i], p=p, g=0, hit=True, length=0.45))]),
        swell=lambda p: rise(sn("ice field cracking up", p=p, g=0, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("Iceberg,Designed,Impact,Crack,Shatter,Huge_08", p=1.0 * p, g=0, hit=True, length=1.0)),
                             (0.0, sn("Ice_chunk_heavy_07", p=0.85 * p, g=-6, hit=True, length=0.4))]))


def dream():
    return dict(
        cast=lambda i, p: mix([(0.0, sn("windchimes,mixed,paper,aluminum", p=[1.4, 1.2][i] * p, g=4, length=0.6)),
                               (0.0, sn("GLASMisc_Reverse Glass Effect", p=1.2 * p, g=-6, length=0.5))]),
        hit=lambda i, p: mix([(0.0, sn("Wine Glass Hit Higher Pitch", p=[1.2, 1.35][i] * p, g=0, hit=True, length=0.45)),
                              (0.0, sn("small metal blade flesh movement", p=1.2 * p, g=-8, length=0.2, hit=True))]),
        swell=lambda p: rise(sn("Crystal, Glass, Red Wine, Tone, Rubbing, Musical_07", p=p, g=0, start=0.5, length=0.6), 0.5),
        burst=lambda p: mix([(0.0, sn("SINGING_BOWL_Strike_Sustain_D_02", p=1.4 * p, g=0, hit=True, length=1.0)),
                             (0.0, sn("Glass_Break_Pane_702T_Fienup_005", p=1.1 * p, g=-8, hit=True, length=0.6))]))


# MARK: ヒーロー（属性・武器の組・音程）。武器の組は App/Services/HeroWeaponSounds.swift と同じ

HEROES = {
    "H001": ("城門の誓衛アルデン", holy, "sword", 0.92), "H002": ("星弦のリラ", crystal, "sword", 1.08),
    "H003": ("月弓のフィリエル", moon, "bow", 1.0), "H004": ("潮祈のミレア", water, "magic_water", 1.0),
    "H005": ("黒雷のヴォス", lightning, "magic_lightning", 0.9), "H006": ("月灯のセレン", moon, "dual", 1.1),
    "H007": ("岩脈のガルク", earth, "fist", 0.9), "H008": ("風標のニア", wind, "spear", 1.05),
    "H009": ("機巧士オリン", mech, "crossbow", 1.0), "H010": ("焔冠のテッサ", fire, "magic_fire", 1.0),
    "H011": ("鉄翼のルーク", metal, "magic_light", 0.95), "H012": ("玻璃歌のエリネ", crystal, "dual", 1.15),
    "H013": ("獣刻のダガン", beast, "hammer", 0.95), "H014": ("霧歩のシオ", mist, "dual", 1.0),
    "H015": ("戦鐘のヴァルカ", bell, "gun", 1.0), "H016": ("白環のイリス", holy, "magic_light", 1.08),
    "H017": ("深淵鎖のモルド", dark, "magic_dark", 0.92), "H018": ("花星のセリア", nature, "dual", 1.1),
    "H019": ("砦砕のブラム", earth, "hammer", 0.85), "H020": ("光矢のユナ", holy, "sword", 1.15),
    "H021": ("時砂のキロス", sand, "gun", 1.0), "H022": ("蒼爪のレア", frost, "dual", 1.05),
    "H023": ("雷槍のトレン", lightning, "spear", 1.0), "H024": ("夢織のノア", dream, "dual", 1.12),
}


def hero(hid):
    name, elem, weapon, p = HEROES[hid]
    e = elem()
    tag = f"{hid} {name}（{elem.__name__}・{weapon}）"
    write(f"skill_{hid}_s1_cast", mix([(0.0, own(f"wpn_{weapon}_atk_1", p=p, g=-2)), (0.02, e["cast"](0, p))]),
          "cast", f"{tag} S1: 武器の振り・発射 + 属性の放ち", target=-21.0, cap=1.0)
    write(f"skill_{hid}_s2_cast", mix([(0.0, e["cast"](1, 0.95 * p)),
                                      (0.0, sn("Whoosh,Sound Design,Airy,Full,Soft,Buffet,Medium", p=1.1 * p, g=-6, hp=300, length=0.4))]),
          "cast", f"{tag} S2: 属性の放ち + 風切り", target=-21.0, cap=1.0)
    write(f"skill_{hid}_ult_cast", tail(mix([(0.0, e["swell"](p)), (0.55, own(f"wpn_{weapon}_crit_1", p=0.9 * p, g=-2)),
                                             (0.55, e["burst"](p))]), 1.5, 1.9),
          "ult", f"{tag} 奥義: 属性の溜め → 武器の会心 + 属性の炸裂", target=-19.0)
    for slot, pp in [("s1", 1.0), ("s2", 0.94)]:
        for k in (1, 2):
            write(f"skill_{hid}_{slot}_hit_{k}", e["hit"](k - 1, pp * p), "hit", f"{tag} {slot.upper()} の命中: 属性の当たり", target=-23.0)
    for k in (1, 2):
        write(f"skill_{hid}_ult_hit_{k}", tail(mix([(0.0, e["burst"]([1.0, 0.92][k - 1] * p)),
                                                    (0.0, sn("10 Hit Deep Thud", p=1.1, g=-8, lp=220, length=0.3, hit=True))]), 0.6, 0.8),
              "hit", f"{tag} 奥義の命中: 属性の炸裂（短く）+ 低い芯", target=-22.0)


def build():
    for hid in HEROES:
        hero(hid)
