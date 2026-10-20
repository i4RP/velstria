"""H029 ボルグ（MLBB: ティグラル）のスキル・通常攻撃・パッシブの音。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import build_audio as B  # noqa: E402,F401


# MLBB（docs/audio/MLBB_H029.md）: 通常攻撃 0.35〜0.45 秒で全帯域が着弾で揃う（体の芯 > 金属 -3〜4 dB）。
# S1 は叩きつけ（+0.05 で芯と金属）→ 低い地鳴り（+0.2）→ 炎の弾け（+0.6）、全体 1.8 秒。S2 は突進の出だしに金属と風、
# 地響き（+0.35）、炎の尾（+0.3）、1.2 秒。再使用は槌の金属（+0.05〜0.15）と低音（+0.2）0.7 秒。
# 奥義は 0.8 秒かけて全帯域がふくらみ、1.0 秒で低音の山（崩落）、0.6 秒の尾。

def build():
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
