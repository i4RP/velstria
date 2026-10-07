"""H016 白環のイリス（Zhuxin 型: 紅の蝶・提灯・魂の捕獲）。紅 + 桃 + 白の蝶。遠隔アルカニスト。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(255, 240, 245), main=(255, 85, 110), accent=(255, 170, 200), dark=(120, 20, 50))
P = "H016_"


def butterflies(n=10, speed=(2, 6), size=0.7, delay=0, y=0.0, life=(22, 36), c=None, gravity=0.5, spread=0.8):
    return scatter("Fx_Butterfly", c or S.main, n=n, speed=speed, life=life, size=size, y=y, delay=delay, gravity=gravity, spin=90, c2=S.accent, spread=spread)


def build():
    E = []
    # 通常攻撃: 提灯の赤い光球（蝶が散る）
    E.append(make(P + "atk_cast", ranged_muzzle(S, 1.0) + [butterflies(3, (1.5, 3.5), 0.45, life=(14, 22))], 24))
    E.append(make(P + "atk_travel", projectile(S, "orb", 1.0) + [Node("wing", tex="Fx_Butterfly", life=(14, 22), count="inf", interval=(4, 6), detach=True, billboard="billboard", gen=Gen.sphere(0.2, rotate=False),
                                                                  scale=Scl.ease(0.5, 0.2), color=fade(S.accent, 220))], 40, loop=True))
    E.append(make(P + "atk_hit", hit_burst(S, 0.95, extra=[butterflies(5, (2, 5), 0.5, life=(16, 26))]), 28))
    # S1 フラッタリング: 袖の扇状 → 蝶の群れが前へ飛ぶ
    E.append(make(P + "s1_cast", [crescent("fan", S.accent, 4.4, 12, y=0.2, z=-1.4, a=220), glow_core("flare", S.core, 1.8, 9, z=-0.5), butterflies(6, (2, 5), 0.6, y=0.2), ground_pulse(S.main, 0.3, 2.0, 14)], 28))
    E.append(make(P + "s1_travel", projectile(S, "butterfly", 1.1) + [butterflies(0, (0, 0), 0.5)] * 0 + [Node("swarm", tex="Fx_Butterfly", life=(18, 28), count="inf", interval=(2, 3), detach=True, billboard="billboard", gen=Gen.sphere(0.5, rotate=False),
                                                                                                                 loc=Loc.pva(vel=((0, 0.5, 0), (0, 1.8, 0))), scale=Scl.ease(0.6, 0.2), color=morph(S.main, S.accent, 230, 0))], 40, loop=True))
    E.append(make(P + "s1_impact", hit_burst(S, 1.2, extra=[butterflies(10, (3, 7), 0.7), ground_pulse(S.main, 0.3, 2.6, 16, y=-0.8)]), 32))
    E.append(make(P + "s1_hit", hit_burst(S, 0.9, extra=[butterflies(4, (2, 4), 0.45)]), 26))
    # S2 ランタンフレア: 提灯が床を照らし蝶が周回 → 解放で投げる
    E.append(make(P + "s2_cast", [decal(S.main, 5.0, 46, spin=50, a=210), glow_core("lantern", S.core, 2.4, 14, y=0.6), under(S.main, 3.6, 18, y=0.6), ground_pulse(S.accent, 0.3, 2.8, 18, y=-0.85),
                                  Node("orbit", tex="Fx_Butterfly", life=(40, 46), count=7, interval=(1, 2), billboard="billboard", gen=Gen.circle(1.4, rotate=False), loc=Loc.pva(pos=((0, 0.2, 0), (0, 0.8, 0)), vel=((0, 0.2, 0), (0, 0.8, 0))),
                                       scale=Scl.fixed(0.7), color=Col.ease(rgba(S.main, 255), rgba(S.accent, 0), "in"))], 56))
    E.append(make(P + "s2_impact", [decal(S.main, 5.6, 36, spin=-60, a=230), ground_pulse(S.core, 0.4, 3.4, 18, a=255), glow_core("flare", S.core, 3.0, 12), under(S.main, 4.8, 20), butterflies(14, (3, 8), 0.8), flecks(S.accent, n=14, y=0.2, speed=(3, 8))], 44))
    E.append(make(P + "s2_hit", hit_burst(S, 0.9), 24))
    # ULT クリムゾンビーコン: 予告の紅い輪 → 紅の光柱と蝶の渦、降る花びら
    E.append(make(P + "ult_cast", [glow_core("flare", S.core, 2.6, 12), ground_pulse(S.main, 0.4, 3.0, 16), butterflies(10, (2, 6), 0.7, life=(26, 40)), decal(S.accent, 4.0, 30, spin=80)], 34))
    E.append(make(P + "ult_telegraph", [decal(S.main, 7.0, 40, spin=40, a=180, grow=0.9, fade_in=8), Node("warn", tex="Fx_Ring", life=40, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(0, -0.84, 0), scale=Scl.fixed(6.6),
                                                                                                          color=Col.ease(rgba(S.main, 120), rgba(S.main, 220), "lin"), fade_in=6)], 44))
    E.append(make(P + "ult_impact", [decal(S.main, 8.0, 80, spin=60, a=235), decal(S.accent, 5.4, 80, tex="Fx_Hex", spin=-70, a=190), ground_pulse(S.core, 0.5, 4.4, 18, a=255), ground_pulse(S.main, 0.5, 5.2, 24, delay=5),
                                     pillar(S.main, 3.0, 8.0, 36, delay=2), pillar(S.core, 1.2, 9.0, 30, delay=2), glow_core("flare", S.core, 4.2, 14), under(S.dark, 7.0, 40, a=170),
                                     butterflies(26, (3, 9), 0.9, life=(40, 66), y=-0.4), scatter("Fx_Petal", S.accent, n=24, size=0.55, speed=(1, 4), life=(40, 70), gravity=-0.5, spread=0.4, y=3.0),
                                     rise("Fx_Glow", S.accent, count="inf", radius=2.6, size=0.3, life=(30, 46), interval=(1, 2), y=-0.7)], 100))
    E.append(make(P + "ult_hit", hit_burst(S, 1.1, extra=[butterflies(6, (2, 5), 0.5)]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
