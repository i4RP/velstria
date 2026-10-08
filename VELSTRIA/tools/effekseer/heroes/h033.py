"""H033 紅牙のヴァルド（Alucard 型: 大剣の叩き割り・追い打ちの踏み込み・血月断裂）。深紅 + 黒 + 青白。近接アサシン。

段: atk_cast / atk_cast2 / atk_hit / s1_cast / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit / ult_cast / ult_impact / ult_hit
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *  # noqa: E402

S = Style(core=(255, 232, 232), main=(225, 28, 58), accent=(188, 208, 255), dark=(75, 6, 22))
P = "H033_"


def blood_moon(size=3.0, life=16, y=0.0, z=-1.0, delay=0, a=240, flat=False, c=None):
    """血月の弧（深紅の三日月）。"""
    return crescent("moon", c or S.main, size, life, y=y, z=z, delay=delay, a=a, flat=flat, grow=(0.5, 1.0))


def greatsword(flip=False, size=1.0, delay=0):
    """大剣の袈裟斬り（重い三日月 + 赤い縁の刃筋 + 青白い風）。"""
    yaw = -10 if flip else 10
    return [crescent("cleave", S.core, 4.0 * size, 10, y=0.3, z=-1.6 * size, delay=delay, yaw=-yaw, a=250),
            crescent("cleaveB", S.main, 5.0 * size, 12, y=0.2, z=-1.8 * size, delay=delay + 1, yaw=-yaw, a=215),
            flat_streak("edge", S.main, 3.2 * size, 0.2, 9, z=-1.3 * size, yaw=yaw, delay=delay, y=0.3, a=245),
            flat_streak("air", S.accent, 2.4 * size, 0.28, 9, z=-1.0 * size, yaw=-yaw * 1.4, delay=delay, y=0.2, a=190)]


def blood(n=8, delay=0, y=0.2, speed=(2.5, 7), size=0.3, life=(14, 24)):
    """飛び散る血しぶき（通常合成の濃い赤の雫）。"""
    return Node("blood", tex="Fx_Blob", blend="normal", life=life, count=n, delay=delay, gen=Gen.sphere(0.05, rx=(-80, 80), ry=(-180, 180)),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, speed[0], 0), (0, speed[1], 0)), acc=(0, -9, 0)),
                scale=Scl.ease(size, size * 0.3), color=Col.ease(rgba(S.main, 235), rgba(S.dark, 0), "in"))


def bats(n=6, delay=0, y=0.6, size=0.8, speed=(2, 6)):
    """蝙蝠の翼風の黒赤の影が散る。"""
    return scatter("Fx_Crescent", S.dark, n=n, size=size, speed=speed, life=(18, 30), y=y, delay=delay, gravity=-1, spin=300, c2=S.main)


def fang_cut(size=1.0, delay=0, life=9, y=0.25, a=250):
    """交差する 2 本の斬り裂き（標的の位置で X 字に光る）。"""
    return [Node("cutA", tex="Fx_Streak", life=life, delay=delay, billboard="billboard", rot=Rot.fixed(0, 0, 38), loc=Loc.fixed(0, y, 0), scale=Scl.ease((1.0 * size, 0.22, 1), (4.6 * size, 0.08, 1), "out"), color=fade(S.core, a)),
            Node("cutB", tex="Fx_Streak", life=life, delay=delay + 1, billboard="billboard", rot=Rot.fixed(0, 0, -38), loc=Loc.fixed(0, y, 0), scale=Scl.ease((1.0 * size, 0.22, 1), (4.6 * size, 0.08, 1), "out"), color=fade(S.main, a))]


def build():
    E = []
    # 通常攻撃: 大剣の袈裟斬り（左右交互）
    E.append(make(P + "atk_cast", greatsword(False, 1.0) + [blood(3, delay=3, y=0.3, speed=(2, 4))], 26))
    E.append(make(P + "atk_cast2", greatsword(True, 1.0) + [blood(3, delay=3, y=0.3, speed=(2, 4))], 26))
    E.append(make(P + "atk_hit", hit_burst(S, 0.95, extra=fang_cut(0.8, life=8) + [blood(6)]), 28))
    # S1 叩き割り（スロー）: 大剣を振り下ろして地面を割る → 割れ目から赤い気が噴く
    E.append(make(P + "s1_cast", greatsword(False, 1.3) + [glow_core("flare", S.core, 2.0, 10, z=-0.5), ground_pulse(S.main, 0.3, 2.2, 14, y=-0.85)], 28))
    E.append(make(P + "s1_impact", [ground_pulse(S.core, 0.4, 3.0, 16, y=-0.8, a=255), ground_pulse(S.main, 0.4, 3.6, 22, y=-0.8, delay=2), glow_core("flare", S.core, 3.0, 11, z=-2.8),
                                    decal(S.main, 5.0, 40, y=-0.84, z=-2.8, tex="Fx_Crack", a=235, grow=0.8), under(S.dark, 4.8, 20, z=-2.8, a=170), pillar(S.main, 1.2, 4.0, 16, y=-0.8),
                                    burst_lines(S.core, n=10, length=1.3, y=0.2, delay=1), blood(10, delay=1, y=0.1), rise("Fx_Glow", S.main, n=12, radius=1.6, size=0.28, life=(24, 40), y=-0.7, delay=2)], 36))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0, extra=[blood(6), ground_pulse(S.main, 0.3, 1.8, 14, y=-0.8)]), 26))
    # S2 追い打ち: 影のような踏み込み（青白い残像 + 蝙蝠）→ 斬り裂き
    E.append(make(P + "s2_cast", [speed_lines(S.accent, 12, 3.6), glow_core("flare", S.core, 2.0, 9, z=-0.3), under(S.main, 3.0, 14, z=-0.3), flat_streak("dash", S.main, 4.2, 0.6, 12, z=-2.0, a=200),
                                  ground_pulse(S.main, 0.3, 2.0, 14, y=-0.85), bats(5, y=0.4)], 26))
    E.append(make(P + "s2_impact", greatsword(True, 1.4, ) + [flat_streak("trail", S.main, 5.4, 0.5, 14, z=-2.6, a=220), under(S.main, 4.6, 14, z=-2.4), burst_lines(S.core, n=10, length=1.2, y=0.2, delay=1),
                                                              blood(10, delay=1), flecks(S.accent, n=8, speed=(3, 7), size=0.22, y=0.2, c2=S.main, gravity=-2)], 30))
    E.append(make(P + "s2_hit", hit_burst(S, 0.95, extra=fang_cut(1.0, life=8) + [blood(5)]), 26))
    # ULT 血月断裂: 背後に血の月が昇る（術者）→ 標的へ飛びかかり斬り裂く（吸血の光が戻る）
    moon = [Node("moonglow", tex="Fx_Core", life=44, loc=Loc.fixed(0, 3.4, 0.6), scale=Scl.ease(1.4, 5.2, "out"), color=Col.ease(rgba(S.main, 220), rgba(S.main, 0), "in"), fade_in=4),
            Node("moondisc", tex="Fx_Glow", life=44, loc=Loc.fixed(0, 3.4, 0.6), scale=Scl.ease(1.0, 4.0, "out"), color=Col.ease(rgba(S.dark, 200), rgba(S.main, 0), "in"), fade_in=4),
            blood_moon(5.6, 44, y=3.4, z=0.6, a=255, c=S.core), blood_moon(7.0, 44, y=3.4, z=0.6, delay=2, a=200)]
    E.append(make(P + "ult_cast", moon + [glow_core("flare", S.core, 3.2, 12), decal(S.main, 5.4, 56, y=-0.85, spin=70, a=225), ground_pulse(S.core, 0.4, 3.6, 18, y=-0.85, a=255),
                                         ground_pulse(S.main, 0.4, 4.2, 24, y=-0.85, delay=4), pillar(S.main, 1.4, 5.0, 24), under(S.dark, 4.6, 28, a=170), bats(10, y=0.8, size=1.0, speed=(3, 8)),
                                         rise("Fx_Glow", S.main, n=16, radius=1.2, size=0.3, life=(28, 44), y=-0.9)], 60))
    E.append(make(P + "ult_impact", fang_cut(1.7, delay=0, life=9) + fang_cut(2.0, delay=7, life=9) + fang_cut(2.4, delay=14, life=11)
             + [Node(f"flash{i}", tex="Fx_Core", life=9, delay=d, loc=Loc.fixed(0, 0.25, 0), scale=Scl.ease(0.8, 3.2, "out"), color=fade(S.core)) for i, d in enumerate((0, 7, 14))]
             + [blood_moon(6.0, 22, y=0.4, z=0.0, delay=14, a=240, flat=False), decal(S.main, 6.0, 56, y=-0.85, spin=-80, a=225, delay=0), ground_pulse(S.core, 0.4, 3.2, 16, y=-0.8, a=255, delay=14),
                ground_pulse(S.main, 0.4, 4.4, 24, y=-0.8, delay=16), pillar(S.core, 1.6, 7.0, 26, delay=14, y=-0.8), pillar(S.main, 3.2, 5.6, 30, delay=14, y=-0.8, a=170),
                glow_core("burst", S.core, 4.6, 14, delay=14), under(S.dark, 6.0, 40, a=170), burst_lines(S.core, n=16, length=1.5, y=0.3, speed=(6, 13), delay=14),
                blood(18, delay=14, y=0.2, speed=(3, 9)), bats(8, delay=15, y=0.6, size=0.9, speed=(3, 8)), rise("Fx_Glow", S.main, n=18, radius=2.0, size=0.3, life=(30, 46), y=-0.7, delay=16)], 66))
    # 吸血: 標的から赤い光が昇る
    E.append(make(P + "ult_hit", hit_burst(S, 1.15, extra=fang_cut(1.2, life=9) + [blood(8), rise("Fx_Glow", S.main, n=10, radius=0.7, size=0.26, life=(24, 38), y=0.0, speed=(1.2, 3.0))]), 34))
    return E


if __name__ == "__main__":
    build_set(build())
