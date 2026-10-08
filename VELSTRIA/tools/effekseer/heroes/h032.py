"""H032 赤拳のディアス（Dyrroth 型: 拳剣の薙ぎと衝撃波・跳躍の叩きつけ・煉獄連拳）。赤 + 黒 + 鉄の灰（熾火の橙）。近接デュエリスト。

段: atk_cast / atk_cast2 / atk_hit / s1_cast / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit / ult_cast / ult_impact / ult_hit
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *  # noqa: E402

S = Style(core=(255, 238, 228), main=(238, 52, 52), accent=(255, 150, 80), dark=(70, 10, 18))
IRON = (150, 150, 158)
P = "H032_"


def blade_arc(flip=False, size=1.0, delay=0):
    """拳剣の薙ぎ（重い赤の三日月 + 白熱の刃筋）。flip = 逆向きの振り。"""
    yaw = -9 if flip else 9
    return [crescent("slash", S.core, 3.6 * size, 10, y=0.25, z=-1.5 * size, delay=delay, yaw=-yaw, a=250),
            crescent("slashB", S.main, 4.6 * size, 12, y=0.2, z=-1.7 * size, delay=delay + 1, yaw=-yaw, a=210),
            flat_streak("edge", S.core, 2.8 * size, 0.18, 8, z=-1.2 * size, yaw=yaw, delay=delay, y=0.25, a=240),
            flat_streak("wind", S.accent, 2.2 * size, 0.3, 9, z=-1.0 * size, yaw=-yaw * 1.4, delay=delay, y=0.2, a=190)]


def embers(n=8, delay=0, y=0.2, speed=(2, 6), size=0.24, spread=0.7):
    """赤い気の火の粉。"""
    return flecks(S.accent, n=n, speed=speed, life=(14, 26), size=size, y=y, delay=delay, gravity=-1.5, c2=S.main, spread=spread)


def soot(n=5, delay=0, radius=1.4, size=(0.9, 2.2), y=-0.7, life=(20, 30)):
    """黒い煤煙（通常合成の暗い煙）。"""
    return Node("soot", tex="Fx_Smoke", blend="normal", life=life, count=n, delay=delay, gen=Gen.circle(radius, rotate=False),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, 0.5, 0), (0, 1.6, 0))), scale=Scl.ease(size[0], size[1]), color=Col.ease(rgba((28, 22, 26), 190), rgba((28, 22, 26), 0), "in"))


def shock_wave(length=6.0, width=0.9, z=-3.0, delay=0, life=14, c=None):
    """前へ走る赤い衝撃波（地面に平らな三日月 + 筋）。"""
    return [crescent("shockA", c or S.main, length * 0.9, life, y=0.1, z=z, delay=delay, a=235, grow=(0.5, 1.0)),
            flat_streak("shockB", S.core, length, width * 0.5, life - 2, z=z, delay=delay, y=0.12, a=230)]


def punch(delay=0, yaw=0, x=0.0, y=0.4, size=1.0):
    """拳の一撃（拳の位置に閃光 + 前へ突く筋）。"""
    return [Node("pfx", tex="Fx_Core", life=7, delay=delay, loc=Loc.fixed(x, y, 0.0), scale=Scl.ease(0.8 * size, 2.6 * size, "out"), color=fade(S.core)),
            Node("pstar", tex="Fx_Star", life=9, delay=delay, loc=Loc.fixed(x, y, 0.0), scale=Scl.ease(0.8 * size, 3.0 * size, "out"), color=fade(S.main)),
            flat_streak("pfist", S.accent, 2.4 * size, 0.34, 7, z=-0.9, yaw=yaw, delay=delay, y=y, a=235, x=x)]


def build():
    E = []
    # 通常攻撃: 拳剣の薙ぎ（左右交互）
    E.append(make(P + "atk_cast", blade_arc(False, 1.0) + [embers(5)], 24))
    E.append(make(P + "atk_cast2", blade_arc(True, 1.0) + [embers(5)], 24))
    E.append(make(P + "atk_hit", hit_burst(S, 0.95, extra=[flat_streak("cut", S.core, 2.6, 0.2, 7, z=0.0), ground_pulse(S.main, 0.3, 1.7, 14, y=-0.75), scatter("Fx_Diamond", S.main, n=4, size=0.45, speed=(2, 5), life=(14, 22))]), 28))
    # S1 拳剣の薙ぎ: 大きく薙いで赤い衝撃波を前へ飛ばす
    E.append(make(P + "s1_cast", blade_arc(False, 1.3) + [glow_core("flare", S.core, 2.0, 9, z=-0.4), ground_pulse(S.main, 0.3, 2.0, 14, y=-0.85), embers(8, delay=1)], 28))
    E.append(make(P + "s1_impact", shock_wave(6.4, 1.1, z=-3.0) + shock_wave(5.0, 0.8, z=-3.4, delay=2, c=S.accent) + [under(S.main, 4.8, 16, z=-2.6), decal(S.main, 4.0, 34, y=-0.84, z=-3.0, tex="Fx_Crack", a=215, grow=0.8),
                                                                                                                      burst_lines(S.core, n=10, length=1.2, y=0.2, delay=1), embers(10, delay=1, speed=(3, 8)), soot(3, radius=1.0, delay=1)], 32))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0, extra=[flat_streak("cut", S.core, 2.8, 0.22, 7, z=0.0), embers(5)]), 26))
    # S2 跳躍の叩きつけ: 赤い気を纏って跳び（上昇の筋）→ 着地で地面を割りスタン
    E.append(make(P + "s2_cast", [pillar(S.main, 1.2, 3.6, 14, y=-0.8), glow_core("flare", S.core, 2.4, 10, y=0.4), ground_pulse(S.accent, 0.3, 2.2, 14, y=-0.85), soot(4, radius=0.8, delay=0), embers(8, y=0.2, speed=(3, 7))], 28))
    E.append(make(P + "s2_impact", [ground_pulse(S.core, 0.4, 3.2, 16, y=-0.8, a=255), ground_pulse(S.main, 0.4, 3.8, 22, y=-0.8, delay=3), ground_pulse(S.accent, 0.4, 4.4, 26, y=-0.8, delay=6),
                                    glow_core("flare", S.core, 3.2, 12), under(S.dark, 4.8, 22, a=170), decal(S.main, 5.4, 44, y=-0.84, tex="Fx_Crack", a=235, grow=0.7), decal(S.accent, 3.6, 44, y=-0.83, spin=90, a=180),
                                    burst_lines(S.core, n=12, length=1.3), scatter("Fx_Diamond", S.main, n=10, size=0.55, speed=(3, 8), life=(16, 26)), soot(6, radius=1.8, delay=1), embers(10, y=0.0, speed=(3, 8), delay=1),
                                    # スタンの印: 頭上で回る赤い輪
                                    Node("stun", tex="Fx_Wheel", life=44, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 480)), loc=Loc.fixed(0, 1.2, 0), scale=Scl.fixed(1.6), color=Col.ease(rgba(S.main, 235), rgba(S.main, 0), "in"), fade_in=4)], 50))
    E.append(make(P + "s2_hit", hit_burst(S, 1.0, extra=[ground_pulse(S.main, 0.3, 1.8, 14, y=-0.8), embers(5)]), 26))
    # ULT 煉獄連拳: 赤い気が燃え上がる（術者）→ 標的へ拳の連打（減速の枷）
    E.append(make(P + "ult_cast", [glow_core("flare", S.core, 3.4, 14), decal(S.main, 5.4, 56, y=-0.85, spin=80, a=225), decal(S.accent, 3.6, 56, y=-0.84, tex="Fx_Hex", spin=-100, a=180),
                                   ground_ring(S.core, 0.4, 3.8, 20, y=-0.85, alpha=255), ground_ring(S.main, 0.4, 4.4, 26, y=-0.85, delay=6), pillar(S.main, 1.6, 5.4, 26), pillar(S.accent, 3.0, 4.2, 28, a=140),
                                   under(S.dark, 4.6, 28, a=170), soot(6, radius=1.6, delay=2), embers(14, y=0.0, speed=(3, 8)),
                                   rise("Fx_Glow", S.accent, n=18, radius=1.2, size=0.3, life=(30, 46), y=-0.9)], 60))
    barrage = []
    for i, d in enumerate(range(0, 30, 3)):
        barrage += punch(delay=d, yaw=(i * 37) % 60 - 30, x=((i % 3) - 1) * 0.5, y=0.3 + (i % 2) * 0.5, size=0.9 + 0.05 * i)
    E.append(make(P + "ult_impact", barrage + [ground_pulse(S.main, 0.4, 2.6, 14, y=-0.8, delay=6), ground_pulse(S.main, 0.4, 2.8, 14, y=-0.8, delay=15), ground_pulse(S.accent, 0.4, 3.0, 14, y=-0.8, delay=24),
                                              glow_core("slam", S.core, 4.6, 14, delay=30), Node("star", tex="Fx_Star", life=16, delay=30, scale=Scl.ease(1.8, 6.2, "out"), color=fade(S.main)),
                                              ground_pulse(S.core, 0.5, 4.4, 18, y=-0.8, delay=30, a=255), ground_pulse(S.main, 0.5, 5.4, 24, y=-0.8, delay=32), ground_pulse(S.accent, 0.5, 6.2, 28, y=-0.8, delay=34),
                                              decal(S.main, 7.0, 56, y=-0.84, tex="Fx_Crack", a=235, grow=0.7, delay=30), decal(S.accent, 5.0, 56, y=-0.83, spin=-70, a=190, delay=30),
                                              under(S.dark, 6.4, 44, delay=30, a=170), burst_lines(S.core, n=16, length=1.5, y=0.3, speed=(6, 13), delay=30),
                                              scatter("Fx_Diamond", S.main, n=14, size=0.65, speed=(3, 9), life=(18, 30), delay=30), soot(8, radius=2.2, delay=31), embers(16, y=0.0, speed=(3, 9), delay=30)], 80))
    E.append(make(P + "ult_hit", hit_burst(S, 1.15, extra=[flat_streak("pierce", S.core, 2.8, 0.22, 7, z=0.0), embers(6),
                                                            # 減速の枷: 足もとで締まる鉄の輪
                                                            Node("shackle", tex="Fx_Ring", life=40, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(0, -0.75, 0), scale=Scl.ease(3.2, 1.4, "in"), color=Col.ease(rgba(IRON, 40), rgba(S.accent, 220), "in"))]), 36))
    return E


if __name__ == "__main__":
    build_set(build())
