"""H008 風標のニア（Sora 型: 雷 / 奔流の 2 形態）。風の水色 + 雷の黄 + 深い青。近接デュエリスト。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(250, 255, 255), main=(130, 225, 255), accent=(255, 235, 110), dark=(30, 90, 190))
P = "H008_"
WATER = (70, 150, 255)


def bolts(n=3, radius=2.2, h=5.0, delay=0, c=None, life=(8, 12)):
    return Node("bolts", tex="Fx_Bolt", life=life, count=n, interval=(2, 4), delay=delay, billboard="yfixed", gen=Gen.circle(radius, rotate=False),
                loc=Loc.fixed(0, h * 0.5 - 0.8, 0), scale=Scl.fixed(1.0, h, 1), color=Col.fixed(*(c or S.accent), 255))


def build():
    E = []
    # 通常攻撃: 風の旗槍の突き（風の輪 + 稲光）
    E.append(make(P + "atk_cast", [flat_streak("thrust", S.core, 3.4, 0.34, 9, z=-1.5), flat_streak("wind", S.main, 3.0, 0.5, 11, z=-1.3, a=170),
                                   Node("ring", tex="Fx_Ring", life=10, billboard="fixed", rot=Rot.fixed(0, 0, 0), loc=Loc.fixed(0, 0.2, -1.8), scale=Scl.ease(0.5, 2.0, "out"), color=fade(S.main, 220)),
                                   flecks(S.accent, n=5, speed=(2, 5), size=0.2, y=0.2, c2=S.core, gravity=-2, spread=0.5)], 24))
    E.append(make(P + "atk_cast2", melee_swing(S, flip=True, size=1.0), 24))
    E.append(make(P + "atk_hit", hit_burst(S, 0.9, ring_c=S.main, extra=[Node("zap", tex="Fx_Bolt", life=8, billboard="billboard", scale=Scl.ease((0.5, 1.6, 1), (0.8, 2.6, 1), "out"), color=fade(S.accent))]), 26))
    # S1: 連撃（突きの連打）→ 突進で締め
    E.append(make(P + "s1_cast", [glow_core("flare", S.core, 1.6, 8, z=-0.4), speed_lines(S.main, 8, 2.6)], 22))
    E.append(make(P + "s1_impact", [flat_streak("t1", S.core, 4.6, 0.4, 10, z=-2.0, yaw=-10), flat_streak("t2", S.main, 4.6, 0.4, 10, z=-2.0, yaw=10, delay=3),
                                    flat_streak("t3", S.core, 5.4, 0.5, 12, z=-2.4, delay=6), under(S.main, 4.4, 16, z=-2), bolts(3, 1.8, 4.0, delay=4, life=(7, 10)),
                                    burst_lines(S.accent, n=10, length=1.2, y=0.2, delay=6), flecks(S.core, n=8, c2=S.main, y=0.2, speed=(3, 7))], 30))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0), 26))
    # S2 ウィンドストライド: 前へ跳び、着地で地面叩き（風の衝撃波 + 雷）
    E.append(make(P + "s2_cast", [speed_lines(S.main, 12, 3.4), glow_core("flare", S.core, 2.2, 9), Node("gust", tex="Fx_Spiral", blend="add", life=16, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 600)),
                                                                                                 loc=Loc.fixed(0, -0.8, 0), scale=Scl.ease(0.6, 3.0, "out"), color=fade(S.main, 200))], 28))
    E.append(make(P + "s2_impact", [ground_pulse(S.core, 0.4, 3.2, 16, a=255), ground_pulse(S.main, 0.4, 3.8, 20, delay=3), decal(S.accent, 4.4, 28, tex="Fx_Crack", grow=0.5),
                                    glow_core("flare", S.core, 3.2, 10), under(S.dark, 4.4, 18, a=170), bolts(4, 1.6, 4.4, delay=1), flecks(S.main, n=12, y=0.1, speed=(3, 8)),
                                    Node("dust", tex="Fx_Smoke", blend="normal", life=24, count=6, gen=Gen.circle(1.4), loc=Loc.pva(vel=((0, 0.3, 0), (0, 1.0, 0)), pos=((0, -0.7, 0), (0, -0.7, 0))),
                                         scale=Scl.ease(0.8, 1.9), color=Col.ease(rgba((210, 225, 235), 130), rgba((210, 225, 235), 0), "in"))], 34))
    E.append(make(P + "s2_hit", hit_burst(S, 0.9), 24))
    # ULT シフティングスカイズ: 雷の形態（落雷 3 本）と奔流（水の渦）を同時に纏う変身
    E.append(make(P + "ult_cast", [glow_core("flare", S.core, 3.6, 14), ground_pulse(S.accent, 0.4, 4.4, 20, a=255), ground_pulse(S.main, 0.4, 4.8, 24, delay=4),
                                   decal(S.accent, 6.0, 44, spin=100), spin_flat("vortex", WATER, 1.0, 5.0, 36, y=-0.7, tex="Fx_Spiral", spin=-500, a=210),
                                   Node("vortex2", tex="Fx_Spiral", life=36, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 380)), loc=Loc.fixed(0, -0.6, 0), scale=Scl.ease(0.8, 3.4, "out"), color=fade(S.main, 160)),
                                   bolts(3, 2.4, 6.0, delay=2, life=(8, 12)), pillar(S.accent, 1.4, 5.5, 20, delay=3), rise("Fx_Glow", S.accent, count=22, radius=2.0, size=0.3, life=(24, 40), y=-0.8)], 52))
    E.append(make(P + "ult_impact", [ground_pulse(S.core, 0.4, 3.0, 16, a=255), glow_core("flare", S.core, 3.0, 10), bolts(3, 1.6, 5.0), under(S.dark, 4.0, 18)], 28))
    E.append(make(P + "ult_hit", hit_burst(S, 1.1, extra=[Node("zap", tex="Fx_Bolt", life=9, billboard="billboard", scale=Scl.ease((0.7, 2.0, 1), (1.0, 3.2, 1), "out"), color=fade(S.accent))]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
