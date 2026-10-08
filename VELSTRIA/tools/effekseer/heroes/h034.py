"""H034 鎖鉤のゴルム（Franco 型: 鎖鉤の引き寄せ・殴りつける踏み込み・狩猟鎖獄）。鉄の灰 + 錆びた赤 + 茶。近接サポート（重装）。

段: atk_cast / atk_cast2 / atk_hit / s1_cast / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit / ult_cast / ult_impact / ult_hit
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *  # noqa: E402

S = Style(core=(240, 236, 230), main=(172, 178, 190), accent=(214, 102, 62), dark=(62, 48, 44))
DUST = (118, 96, 80)
P = "H034_"


def dust(n=6, delay=0, radius=1.4, size=(1.0, 2.4), y=-0.7, life=(22, 32)):
    """舞い上がる土煙（茶の通常合成の煙）。"""
    return Node("dust", tex="Fx_Smoke", blend="normal", life=life, count=n, delay=delay, gen=Gen.circle(radius), loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, 0.4, 0), (0, 1.4, 0))),
                scale=Scl.ease(size[0], size[1]), color=Col.ease(rgba(DUST, 175), rgba(DUST, 0), "in"))


def chain_shot(length=5.5, life=14, delay=0, y=0.3, c=None, width=0.7):
    """打ち出す鎖（術者から前へ伸びる鎖）+ 先端の鉤。"""
    return [Node("chain", tex="Fx_Chain", life=life, delay=delay, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.ease((0, y, -0.5), (0, y, -0.5 - length * 0.5), "out"),
                 scale=Scl.ease((1.0, width, 1), (length, width, 1), "out"), color=fade(c or S.main, 245)),
            Node("hook", tex="Fx_Arrow", life=life, delay=delay, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.ease((0, y, -0.5), (0, y, -0.5 - length), "out"),
                 scale=Scl.fixed(1.2, 0.7, 1), color=fade(S.core, 250)),
            Node("hookglint", tex="Fx_Star", life=life, delay=delay, loc=Loc.ease((0, y, -0.5), (0, y, -0.5 - length), "out"), scale=Scl.ease(0.5, 1.3, "out"), color=fade(S.accent, 230))]


def chain_cage(n=7, radius=1.3, h=4.0, life=(46, 56), delay=0, y=0.2, c=None):
    """地面から立ち上がる鎖の束。"""
    return Node("chains", tex="Fx_Chain", life=life, count=n, delay=delay, billboard="yfixed", rot=Rot.fixed(0, 0, 90), gen=Gen.circle(radius, rotate=False),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, 1.0, 0), (0, 1.8, 0))), scale=Scl.ease((0.5, 1.2, 1), (0.7, h, 1), "out"), color=fade(c or S.main, 245), fade_in=3)


def sparks_iron(n=8, delay=0, y=0.2, speed=(2, 6), size=0.22):
    """鉄と錆の火花。"""
    return flecks(S.accent, n=n, speed=speed, life=(12, 22), size=size, y=y, delay=delay, gravity=-5, c2=S.core, spread=0.7)


def heavy_swing(flip=False, size=1.0, delay=0):
    """太い腕の殴りつけ（重い三日月 + 鎖の振り）。"""
    yaw = -8 if flip else 8
    return [crescent("punch", S.core, 3.6 * size, 10, y=0.3, z=-1.5 * size, delay=delay, yaw=-yaw, a=245),
            crescent("punchB", S.main, 4.6 * size, 12, y=0.2, z=-1.7 * size, delay=delay + 1, yaw=-yaw, a=200),
            flat_streak("chainwhip", S.main, 3.4 * size, 0.5, 10, z=-1.4 * size, yaw=yaw * 1.5, delay=delay, y=0.3, a=225, tex="Fx_Chain"),
            ground_pulse(S.accent, 0.3, 1.9 * size, 12, y=-0.85, delay=delay + 3, a=220), dust(2, delay=delay + 3, radius=0.8, size=(0.6, 1.4))]


def build():
    E = []
    # 通常攻撃: 拳と鎖の殴りつけ
    E.append(make(P + "atk_cast", heavy_swing(False, 1.0), 26))
    E.append(make(P + "atk_cast2", heavy_swing(True, 1.0), 26))
    E.append(make(P + "atk_hit", hit_burst(S, 1.05, extra=[ground_pulse(S.main, 0.3, 2.0, 14, y=-0.8), sparks_iron(5), dust(2, radius=0.6, size=(0.6, 1.4), y=-0.5)]), 28))
    # S1 鎖鉤を打ち出す（拘束）: 前へ鎖と鉤が伸びる → 鉤が食い込み、鎖が巻きつく
    E.append(make(P + "s1_cast", chain_shot(5.5, 14) + [glow_core("flare", S.core, 1.8, 9, z=-0.4), ground_pulse(S.main, 0.3, 2.0, 14, y=-0.85), sparks_iron(6, delay=2)], 30))
    E.append(make(P + "s1_impact", [glow_core("flare", S.core, 2.8, 10, z=-3.4), Node("star", tex="Fx_Star", life=14, loc=Loc.fixed(0, 0.3, -3.4), scale=Scl.ease(1.2, 3.6, "out"), color=fade(S.accent)),
                                    ground_pulse(S.main, 0.4, 3.0, 16, y=-0.8), under(S.main, 3.8, 16, z=-3.4), sparks_iron(10, y=0.2, speed=(3, 8)),
                                    # 鎖の束が絡みつく
                                    chain_cage(6, 0.8, 2.6, (30, 40), y=-0.6), Node("bind", tex="Fx_RingSoft", life=36, loc=Loc.fixed(0, 0.5, 0), scale=Scl.ease(2.8, 1.2, "in"), color=Col.ease(rgba(S.main, 40), rgba(S.accent, 210), "in"))], 40))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0, extra=[chain_cage(4, 0.6, 2.0, (24, 34), y=-0.6), sparks_iron(5)]), 34))
    # S2 殴りつける踏み込み（スロー）: 肩から突進（土煙）→ 鉄拳が地面ごと叩く
    E.append(make(P + "s2_cast", [speed_lines(S.main, 12, 3.4), glow_core("flare", S.core, 2.2, 10), under(S.main, 3.2, 14), ground_pulse(S.accent, 0.3, 2.2, 14), dust(5, radius=0.9, size=(0.8, 2.0)), sparks_iron(6)], 30))
    E.append(make(P + "s2_impact", [ground_pulse(S.core, 0.4, 3.4, 16, y=-0.8, a=255), ground_pulse(S.main, 0.4, 4.0, 22, y=-0.8, delay=3), ground_pulse(S.accent, 0.4, 4.6, 26, y=-0.8, delay=6),
                                    glow_core("flare", S.core, 3.2, 12), under(S.dark, 4.8, 22, a=170), decal(S.main, 5.2, 42, y=-0.84, tex="Fx_Crack", a=230, grow=0.8), decal(S.accent, 3.6, 44, y=-0.83, spin=80, a=190),
                                    burst_lines(S.core, n=12, length=1.2, y=0.2), scatter("Fx_Diamond", S.main, n=10, size=0.55, speed=(3, 8), life=(16, 26)), dust(8, radius=2.0, delay=1, size=(1.2, 2.8)),
                                    # スロー: 足に絡む錆の鎖
                                    chain_cage(5, 1.0, 1.6, (30, 40), y=-0.7, c=S.accent), sparks_iron(10, delay=1, speed=(3, 8))], 50))
    E.append(make(P + "s2_hit", hit_burst(S, 1.0, extra=[ground_pulse(S.accent, 0.3, 1.8, 14, y=-0.8), dust(2, radius=0.6, size=(0.6, 1.4), y=-0.5)]), 28))
    # ULT 狩猟鎖獄: 鎖が四方へ打ち出される（術者）→ 標的が鎖の檻に閉じ込められ、叩き伏せられる
    whips = []
    for i, a in enumerate((0, 70, -70, 140, -140)):
        whips.append(flat_streak(f"whip{i}", S.main if i else S.core, 5.4 - abs(a) * 0.01, 0.6, 14, z=-2.6, yaw=a, delay=i * 2, a=235, y=0.3, tex="Fx_Chain"))
    E.append(make(P + "ult_cast", whips + [glow_core("flare", S.core, 3.2, 12), decal(S.main, 5.8, 56, y=-0.85, spin=60, a=225), decal(S.accent, 3.8, 56, y=-0.84, tex="Fx_Hex", spin=-90, a=180),
                                          ground_ring(S.core, 0.4, 3.8, 20, y=-0.85, alpha=255), ground_ring(S.accent, 0.4, 4.4, 26, y=-0.85, delay=6), under(S.dark, 4.6, 28, a=170),
                                          dust(8, radius=2.0, delay=2, size=(1.2, 2.8)), sparks_iron(12, speed=(3, 8)), rise("Fx_Glow", S.accent, n=14, radius=1.2, size=0.28, life=(26, 42), y=-0.9)], 58))
    E.append(make(P + "ult_impact", [decal(S.main, 7.2, 70, y=-0.85, spin=50, a=230), decal(S.accent, 5.0, 70, y=-0.84, tex="Fx_Hex", spin=-70, a=190),
                                     chain_cage(10, 1.8, 5.0, (50, 62), y=0.0), chain_cage(8, 1.1, 4.0, (46, 56), delay=3, y=0.0, c=S.accent),
                                     Node("cage", tex="Fx_Hex", life=60, billboard="billboard", loc=Loc.fixed(0, 1.2, 0), scale=Scl.ease(5.4, 3.0, "in"), color=Col.ease(rgba(S.main, 50), rgba(S.core, 200), "in"), fade_in=4),
                                     # 叩き伏せ: 檻が締まったところで重い衝撃
                                     glow_core("slam", S.core, 5.0, 14, delay=30), Node("star", tex="Fx_Star", life=16, delay=30, scale=Scl.ease(1.8, 6.0, "out"), color=fade(S.accent)),
                                     ground_pulse(S.core, 0.5, 5.0, 18, y=-0.8, delay=30, a=255), ground_pulse(S.main, 0.5, 6.0, 24, y=-0.8, delay=32), ground_pulse(S.accent, 0.5, 6.8, 28, y=-0.8, delay=34),
                                     decal(S.main, 7.4, 50, y=-0.84, tex="Fx_Crack", a=230, grow=0.7, delay=30), under(S.dark, 7.0, 44, delay=30, a=170),
                                     burst_lines(S.core, n=18, length=1.5, y=0.3, speed=(6, 14), delay=30), scatter("Fx_Diamond", S.main, n=16, size=0.6, speed=(3, 9), life=(18, 30), delay=30),
                                     dust(10, radius=2.6, delay=31, size=(1.4, 3.2)), sparks_iron(16, delay=30, speed=(3, 9)),
                                     # 味方の回復: 錆びた金の光が昇る
                                     rise("Fx_Glow", S.accent, n=24, radius=3.0, size=0.3, life=(34, 54), y=-0.7, delay=32)], 100))
    E.append(make(P + "ult_hit", hit_burst(S, 1.15, extra=[chain_cage(5, 0.7, 2.4, (26, 36), y=-0.6), ground_pulse(S.accent, 0.3, 2.2, 16, y=-0.8)]), 40))
    return E


if __name__ == "__main__":
    build_set(build())
