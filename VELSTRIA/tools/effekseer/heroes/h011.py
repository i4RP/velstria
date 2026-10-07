"""H011 鉄翼のルーク（Floryn 型: デュー・種まき・開花・全体回復）。桃の花 + 若葉 + 金。遠隔サポート。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(255, 250, 240), main=(255, 150, 200), accent=(150, 255, 170), dark=(150, 50, 100))
GOLD = (255, 224, 130)
P = "H011_"


def petals(n=12, speed=(1.5, 5), size=0.55, delay=0, y=0.0, life=(24, 40), c=None, gravity=-1.2, spread=0.9):
    return scatter("Fx_Petal", c or S.main, n=n, speed=speed, size=size, life=life, y=y, delay=delay, gravity=gravity, spin=300, c2=S.core, spread=spread)


def build():
    E = []
    # 通常攻撃: 灯火の杖から柔らかな光球（花びらが舞う）
    E.append(make(P + "atk_cast", ranged_muzzle(S, 0.9) + [petals(3, (1, 3), 0.4, life=(14, 20))], 22))
    E.append(make(P + "atk_travel", projectile(S, "orb", 0.95) + [Node("petal", tex="Fx_Petal", life=(14, 22), count="inf", interval=(3, 5), detach=True, billboard="billboard", gen=Gen.sphere(0.2, rotate=False),
                                                                    rot=Rot.pva(0, (0, 0, 240)), scale=Scl.ease(0.5, 0.2), color=fade(S.main, 230))], 40, loop=True))
    E.append(make(P + "atk_hit", hit_burst(S, 0.9, extra=[petals(5, (2, 4), 0.45)]), 26))
    # S1 ソウ: 種が飛び、着弾で芽吹いて回復の実が跳ねる
    E.append(make(P + "s1_cast", [glow_core("flare", S.core, 1.8, 9, z=-0.4), petals(5, (1.5, 4), 0.5, y=0.2), ground_pulse(S.accent, 0.3, 2.0, 14)], 26))
    E.append(make(P + "s1_travel", projectile(S, "seed", 1.0), 40, loop=True))
    E.append(make(P + "s1_impact", [ground_pulse(S.accent, 0.3, 3.0, 18, y=-0.8, a=240), decal(S.accent, 3.4, 40, spin=40), glow_core("flare", S.core, 2.4, 10), under(S.main, 3.4, 16),
                                    Node("sprout", tex="Fx_Petal", life=(28, 40), count=6, billboard="yfixed", gen=Gen.circle(0.7, rotate=False), rot=Rot.fixed(0, 0, 90),
                                         loc=Loc.fixed(0, 0.0, 0), scale=Scl.ease((0.3, 0.2, 1), (0.9, 1.8, 1), "out"), color=Col.ease(rgba(S.accent, 255), rgba(S.accent, 0), "in")),
                                    Node("fruit", tex="Fx_Glow", life=(24, 34), count=4, gen=Gen.circle(0.5, rotate=False), loc=Loc.pva(vel=((0, 5, 0), (0, 8, 0)), acc=(0, -14, 0)), scale=Scl.fixed(0.5), color=morph(GOLD, S.accent, 255, 0)),
                                    petals(8, (2, 5), 0.5)], 46))
    E.append(make(P + "s1_hit", hit_burst(S, 0.9, extra=[petals(4, (2, 4), 0.45)]), 26))
    # S2 スプラウト: エネルギー塊が爆発（花の爆発 + スタン）
    E.append(make(P + "s2_cast", [glow_core("flare", S.core, 2.0, 10), Node("bloom", tex="Fx_Star", life=16, loc=Loc.fixed(0, 0.6, 0), scale=Scl.ease(0.8, 3.0, "out"), color=fade(S.main)), petals(6, (2, 5), 0.5, y=0.4), ground_pulse(S.main, 0.3, 2.4, 14)], 28))
    E.append(make(P + "s2_impact", [ground_pulse(S.core, 0.4, 3.4, 16, y=-0.8, a=255), ground_pulse(S.main, 0.4, 3.8, 20, delay=3, y=-0.8), glow_core("flare", S.core, 3.2, 10), Node("flower", tex="Fx_Star", life=20, loc=Loc.fixed(0, 0.2, 0), scale=Scl.ease(1.4, 5.0, "out"), color=fade(S.main)),
                                    under(S.main, 4.4, 18), petals(18, (3, 8), 0.65), Node("stun", tex="Fx_Star", life=26, loc=Loc.fixed(0, 1.4, 0), rot=Rot.pva(0, (0, 0, 360)), scale=Scl.fixed(1.0), color=fade(GOLD, 240))], 40))
    E.append(make(P + "s2_hit", hit_burst(S, 0.9), 24))
    # ULT ブルーム: 場所を問わず全員へ花の輝き（術者の足もとで巨大な開花）
    E.append(make(P + "ult_cast", [decal(S.main, 7.4, 70, spin=30, a=230), decal(S.accent, 5.4, 70, spin=-50, tex="Fx_Hex", a=190), ground_pulse(S.core, 0.5, 5.0, 20, a=255), ground_pulse(S.accent, 0.5, 5.8, 26, delay=5),
                                   glow_core("flare", S.core, 4.4, 14), Node("bloom", tex="Fx_Star", life=34, loc=Loc.fixed(0, 0.8, 0), rot=Rot.pva(0, (0, 0, 40)), scale=Scl.ease(1.6, 7.0, "out"), color=fade(S.main, 240)),
                                   pillar(S.accent, 2.6, 7.0, 34, delay=2), under(S.main, 6.4, 40, a=150), petals(30, (3, 9), 0.7, life=(40, 70), y=0.3, spread=1.0),
                                   rise("Fx_Glow", S.accent, count="inf", radius=2.4, size=0.3, life=(30, 46), interval=(1, 2), y=-0.7)], 90))
    E.append(make(P + "ult_impact", [glow_core("flare", S.core, 3.0, 12), ground_pulse(S.accent, 0.4, 4.0, 20, y=-0.8)], 28))
    return E


if __name__ == "__main__":
    build_set(build())
