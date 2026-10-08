"""H031 氷嵐のオーリア（Aurora 型: 氷の弾・凍結の波・絶界凍獄）。氷青 + 白 + 淡い紫。遠隔アルカニスト。

段: atk_cast / atk_travel / atk_hit / s1_cast / s1_travel / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit /
    ult_cast / ult_telegraph / ult_impact / ult_hit（H016 と同じ構成）
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *  # noqa: E402

S = Style(core=(245, 252, 255), main=(130, 215, 255), accent=(205, 170, 255), dark=(35, 95, 175))
P = "H031_"


def ice_shards(n=10, speed=(4, 9), size=(0.3, 1.1), delay=0, c=None, life=(12, 18), y=0.0):
    """氷の破片が四方へ飛び散る。"""
    return Node("shards", tex="Fx_Shard", life=life, count=n, delay=delay, billboard="billboard", gen=Gen.sphere(0.05, rx=(-60, 60), ry=(-180, 180)),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, speed[0], 0), (0, speed[1], 0)), acc=(0, -6, 0)),
                rot=Rot.pva(0, ((0, 0, -300), (0, 0, 300))), scale=Scl.ease((size[0], size[1], 1), (size[0] * 0.5, size[1] * 0.5, 1)), color=fade(c or S.core, 240))


def frost_flakes(n=8, radius=1.2, life=(26, 44), delay=0, y=0.6, size=0.4):
    """舞い降りる雪の結晶（星形が回りながら漂う）。"""
    return Node("flakes", tex="Fx_Star", life=life, count=n, delay=delay, billboard="billboard", gen=Gen.sphere(radius, rx=(-60, 60), ry=(-180, 180), rotate=False),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, -0.2, 0), (0, 0.8, 0))), rot=Rot.pva(0, ((0, 0, -120), (0, 0, 120))),
                scale=Scl.ease(size, size * 0.2), color=morph(S.core, S.main, 230, 0))


def ice_spikes(n=8, radius=1.3, h=(1.2, 2.4), life=(16, 24), delay=0, y=-0.8, c=None, up=(5, 9)):
    """地面から突き上がる氷柱（縦長の氷の破片）。"""
    return Node("spikes", tex="Fx_Shard", life=life, count=n, delay=delay, billboard="yfixed", gen=Gen.circle(radius, rotate=False),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, up[0], 0), (0, up[1], 0)), acc=(0, -16, 0)),
                scale=Scl.ease((0.4, h[0], 1), (0.3, h[1], 1)), color=fade(c or S.core, 240))


def frost_ring(r=3.0, life=44, delay=0, y=-0.84, spin=60, a=200, grow=0.6):
    """地面に広がる霜の紋様（六角 + 亀裂）。"""
    return [decal(S.main, r, life, y=y, delay=delay, tex="Fx_Hex", spin=spin, a=a, grow=grow),
            decal(S.core, r * 0.8, life, y=y + 0.01, delay=delay, tex="Fx_Crack", a=int(a * 0.9), grow=grow)]


def build():
    E = []
    # 通常攻撃: 氷の礫
    E.append(make(P + "atk_cast", ranged_muzzle(S, 1.0) + [frost_flakes(4, 0.6, (14, 22), y=0.0, size=0.34)], 24))
    E.append(make(P + "atk_travel", projectile(S, "shard", 1.0) + [Node("flake", tex="Fx_Star", life=(10, 16), count="inf", interval=(4, 6), detach=True, gen=Gen.sphere(0.3, rx=(-90, 90), ry=(-180, 180), rotate=False),
                                                                     scale=Scl.ease(0.45, 0.05), color=fade(S.main, 220))], 40, loop=True))
    E.append(make(P + "atk_hit", hit_burst(S, 0.95, extra=[ice_shards(6, size=(0.25, 0.9)), ground_pulse(S.main, 0.3, 1.7, 14, y=-0.7)]), 28))
    # S1 氷の弾（スロー）: 大きめの氷塊を撃つ → 着弾で砕け、霜が足もとに残る
    E.append(make(P + "s1_cast", [glow_core("flare", S.core, 2.2, 10, z=-0.5), under(S.main, 2.8, 14, z=-0.5), flat_streak("beam", S.core, 3.4, 0.5, 10, z=-1.6),
                                  flat_streak("beamL", S.main, 2.4, 0.3, 10, z=-1.3, yaw=16), flat_streak("beamR", S.main, 2.4, 0.3, 10, z=-1.3, yaw=-16),
                                  ice_spikes(5, 0.5, (0.8, 1.6), (12, 18), y=-0.8, up=(3, 6)), ground_pulse(S.main, 0.3, 2.0, 14, y=-0.85), frost_flakes(6, 0.8, y=0.2)], 28))
    E.append(make(P + "s1_travel", projectile(S, "shard", 1.5) + [Node("rimeA", tex="Fx_Hex", blend="add", life=600, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 300)), scale=Scl.fixed(2.4), color=Col.fixed(*S.accent, 130))], 40, loop=True))
    E.append(make(P + "s1_impact", hit_burst(S, 1.2, extra=[ice_shards(12, speed=(5, 10), size=(0.35, 1.3)), ice_spikes(6, 1.0), ground_pulse(S.accent, 0.3, 2.6, 16, y=-0.8)] + frost_ring(3.4, 40)), 34))
    E.append(make(P + "s1_hit", hit_burst(S, 0.9, extra=[ice_shards(5), frost_flakes(5, 0.8, y=0.4, size=0.34)]), 26))
    # S2 凍結の波（拘束）: 前へ走る霜の波 → 氷の柱が連なって突き上がる
    waves = [flat_streak(f"wave{i}", S.core if i == 0 else S.main, 5.4 - i * 0.8, 0.6 - i * 0.14, 14, z=-3.0, yaw=a, a=230, y=0.1) for i, a in enumerate((0, -10, 10))]
    spikes_line = [ice_spikes(3, 0.4, (1.0, 2.0), (14, 20), delay=i * 2, y=-0.8, up=(4, 8)) for i in range(4)]
    E.append(make(P + "s2_cast", waves + [glow_core("flare", S.core, 2.2, 9), ground_pulse(S.main, 0.3, 2.2, 14, y=-0.85), under(S.main, 3.0, 14), frost_flakes(8, 1.0, y=0.2)] + spikes_line, 30))
    E.append(make(P + "s2_impact", [glow_core("flare", S.core, 2.6, 10), ground_pulse(S.core, 0.4, 2.8, 16, y=-0.8, a=255), ground_pulse(S.main, 0.4, 3.4, 22, y=-0.8, delay=3),
                                    ice_spikes(10, 1.1, (1.4, 2.8), (18, 26), y=-0.8), ice_spikes(6, 0.5, (1.0, 2.0), (16, 22), delay=3, y=-0.8, c=S.main), under(S.dark, 4.0, 22, a=160),
                                    # 拘束: 足もとで回る霜の輪（動けない印）
                                    Node("bind", tex="Fx_Wheel", life=48, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, -300)), loc=Loc.fixed(0, -0.7, 0), scale=Scl.fixed(2.4), color=Col.ease(rgba(S.accent, 230), rgba(S.accent, 0), "in"), fade_in=4),
                                    ice_shards(8, speed=(4, 9)), frost_flakes(10, 1.2, delay=2)] + frost_ring(4.2, 44), 54))
    E.append(make(P + "s2_hit", hit_burst(S, 0.95, extra=[ice_spikes(5, 0.6, (0.8, 1.6), (14, 20), y=-0.8), ice_shards(5)]), 26))
    # ULT 絶界凍獄: 杖を掲げる → 予告の陣 → 一帯が凍結する氷の円蓋
    E.append(make(P + "ult_cast", [glow_core("flare", S.core, 2.8, 12), ground_pulse(S.main, 0.4, 3.0, 16, y=-0.85), decal(S.accent, 4.6, 32, y=-0.84, spin=100, tex="Fx_Hex"),
                                   pillar(S.main, 1.6, 5.0, 20), frost_flakes(12, 1.4, (24, 36), y=0.4), ice_shards(6, speed=(3, 7))], 36))
    E.append(make(P + "ult_telegraph", [decal(S.main, 7.0, 44, y=-0.84, spin=50, a=180, grow=0.9, fade_in=8, tex="Fx_Hex"), decal(S.accent, 4.6, 44, y=-0.83, spin=-80, a=150, grow=0.9, fade_in=8),
                                        Node("warn", tex="Fx_Ring", life=44, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(0, -0.82, 0), scale=Scl.fixed(6.6),
                                             color=Col.ease(rgba(S.main, 120), rgba(S.core, 230), "lin"), fade_in=6)], 48))
    dome = [Node("dome", tex="Fx_Hex", life=90, billboard="billboard", loc=Loc.fixed(0, 1.0, 0), scale=Scl.ease(3.0, 7.2, "out"), color=Col.ease(rgba(S.main, 150), rgba(S.main, 0), "in"), fade_in=3),
            Node("domeB", tex="Fx_Hex", life=90, billboard="billboard", loc=Loc.fixed(0, 1.0, 0), rot=Rot.pva(0, (0, 0, 40)), scale=Scl.ease(2.2, 5.4, "out"), color=Col.ease(rgba(S.accent, 120), rgba(S.accent, 0), "in"), fade_in=3),
            Node("domeglow", tex="Fx_Glow", life=70, loc=Loc.fixed(0, 0.8, 0), scale=Scl.ease(3.0, 7.0, "out"), color=Col.ease(rgba(S.core, 110), rgba(S.core, 0), "in"))]
    E.append(make(P + "ult_impact", [decal(S.main, 8.0, 90, y=-0.85, spin=60, a=235, tex="Fx_Hex"), decal(S.core, 6.0, 90, y=-0.84, tex="Fx_Crack", a=220, grow=0.7), decal(S.accent, 5.2, 90, y=-0.83, spin=-70, a=190),
                                     glow_core("flare", S.core, 4.4, 14, y=0.4), ground_pulse(S.core, 0.5, 4.4, 18, y=-0.8, a=255), ground_pulse(S.main, 0.5, 5.4, 24, y=-0.8, delay=4),
                                     ground_pulse(S.accent, 0.5, 6.2, 28, y=-0.8, delay=8), under(S.dark, 7.0, 60, a=170)] + dome +
             [ice_spikes(18, 3.0, (1.8, 3.4), (22, 32), y=-0.8, up=(6, 11)), ice_spikes(10, 1.4, (1.4, 2.6), (20, 28), delay=4, y=-0.8, c=S.main), ice_shards(18, speed=(5, 12), size=(0.4, 1.4), delay=2),
              frost_flakes(26, 3.0, (36, 56), delay=2, y=1.0, size=0.5), flecks(S.core, n=16, y=0.2, speed=(3, 9), c2=S.main, delay=2),
              rise("Fx_Glow", S.core, n=24, radius=2.6, size=0.3, life=(30, 46), y=-0.7)], 100))
    E.append(make(P + "ult_hit", hit_burst(S, 1.1, extra=[ice_spikes(6, 0.7, (1.0, 2.0), (14, 20), y=-0.8), ice_shards(6),
                                                           Node("freeze", tex="Fx_Wheel", life=44, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 360)), loc=Loc.fixed(0, 1.2, 0), scale=Scl.fixed(1.5), color=Col.ease(rgba(S.main, 230), rgba(S.main, 0), "in"), fade_in=4)]), 40))
    return E


if __name__ == "__main__":
    build_set(build())
