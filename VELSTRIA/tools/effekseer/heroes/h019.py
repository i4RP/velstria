"""H019 砦砕のブラム（Minotaur 型: 激昂・踏みつけ・地割れ）。血の赤 + 橙 + 黒い煙。近接ヴァンガード。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(255, 240, 220), main=(255, 80, 50), accent=(255, 170, 60), dark=(70, 10, 10))
P = "H019_"


def dust(n=6, delay=0, radius=1.4, size=(1.0, 2.4), y=-0.7):
    return Node("dust", tex="Fx_Smoke", blend="normal", life=(22, 32), count=n, delay=delay, gen=Gen.circle(radius), loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, 0.4, 0), (0, 1.4, 0))),
                scale=Scl.ease(size[0], size[1]), color=Col.ease(rgba((90, 60, 50), 170), rgba((90, 60, 50), 0), "in"))


def embers(n=14, delay=0, y=0.0, speed=(2, 8)):
    return flecks(S.accent, n=n, y=y, delay=delay, speed=speed, c2=S.main, size=0.28, gravity=-3, life=(20, 36))


def build():
    E = []
    # 通常攻撃: 攻城槌の重い叩きつけ（赤い弧 + 土煙 + 火の粉）
    heavy = lambda flip: melee_swing(S, flip=flip, size=1.25) + [dust(3, radius=0.8), embers(5, speed=(2, 5))]
    E.append(make(P + "atk_cast", heavy(False), 28))
    E.append(make(P + "atk_cast2", heavy(True), 28))
    E.append(make(P + "atk_hit", hit_burst(S, 1.1, extra=[embers(8), dust(2)]), 30))
    # S1 絶望の踏みつけ: 跳躍して着地の踏みつけ（衝撃輪 + 亀裂）
    E.append(make(P + "s1_cast", [glow_core("flare", S.core, 1.8, 8, z=-0.5), ground_pulse(S.main, 0.3, 2.2, 14), dust(3, radius=0.8)], 24))
    E.append(make(P + "s1_impact", [ground_pulse(S.core, 0.5, 3.4, 16, y=-0.85, a=255), ground_pulse(S.main, 0.5, 4.0, 20, delay=3, y=-0.85), decal(S.main, 4.6, 40, tex="Fx_Crack", grow=0.5, a=240), glow_core("flare", S.core, 2.8, 10),
                                    under(S.dark, 4.8, 22, a=190), dust(8, radius=2.0), embers(14)], 40))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0, extra=[embers(6)]), 26))
    # S2 激励の咆哮: 咆哮の波（赤金の輪が外へ）+ 回復の粒
    E.append(make(P + "s2_cast", [speed_lines(S.accent, 10, 3.0), glow_core("flare", S.core, 2.2, 9), flat_streak("charge", S.main, 3.6, 0.8, 12, z=-1.4, a=200), dust(3)], 26))
    E.append(make(P + "s2_impact", [ground_pulse(S.core, 0.4, 3.2, 16, y=-0.85, a=255), ground_pulse(S.accent, 0.4, 3.8, 22, delay=3, y=-0.85), decal(S.main, 4.2, 34, tex="Fx_Crack", grow=0.5), glow_core("flare", S.core, 2.8, 10),
                                    under(S.dark, 4.4, 20, a=180), dust(6), embers(12), rise("Fx_Glow", S.accent, count=10, radius=1.0, size=0.26, life=(28, 40), y=-0.6)], 40))
    E.append(make(P + "s2_hit", hit_burst(S, 0.95), 24))
    # ULT ミノアの怒り: 地面を 3 連続で叩き壊す（1・2 発目の赤い衝撃 → 3 発目は真実の赤白 + 噴煙）
    def slam(d, big=False):
        k = 1.35 if big else 1.0
        n = [ground_pulse(S.core, 0.5, 4.4 * k, 16, y=-0.85, delay=d, a=255), ground_pulse(S.main, 0.5, 5.2 * k, 22, y=-0.85, delay=d + 2), decal(S.main, 6.0 * k, 40, tex="Fx_Crack", grow=0.5, delay=d, a=240),
             glow_core("flare", S.core, 3.4 * k, 11, delay=d), under(S.dark, 5.4 * k, 24, delay=d, a=190), dust(8, d + 1, 2.2 * k), embers(16, d + 1, speed=(3, 11))]
        if big:
            n += [pillar(S.main, 3.0, 8.0, 24, delay=d + 1), pillar(S.core, 1.2, 9.0, 20, delay=d + 1), Node("true", tex="Fx_RingSoft", life=20, delay=d, loc=Loc.fixed(0, 0.6, 0), scale=Scl.ease(1.0, 8.0, "out"), color=fade(S.core, 255))]
        return n
    E.append(make(P + "ult_cast", [glow_core("flare", S.core, 3.4, 12), ground_pulse(S.main, 0.4, 3.6, 18), decal(S.main, 5.0, 28, spin=60), dust(4, radius=1.4), embers(10)], 32))
    E.append(make(P + "ult_impact", slam(0) + slam(14) + slam(28, big=True), 80))
    E.append(make(P + "ult_hit", hit_burst(S, 1.2, extra=[embers(10), Node("true", tex="Fx_RingSoft", life=14, scale=Scl.ease(0.8, 3.2, "out"), color=fade((255, 255, 255), 255))]), 30))
    return E


if __name__ == "__main__":
    build_set(build())
