"""H024 夢織のノア（Julian 型: 鎌・剣ダッシュ・鎖）。夢の紫 + 桃の糸 + 藍。近接アサシン。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(250, 240, 255), main=(185, 140, 255), accent=(255, 150, 215), dark=(70, 40, 140))
P = "H024_"


def thread_burst(n=8, length=2.4, y=0.0, delay=0):
    """夢の糸が放射状に走る（細い線）。"""
    return Node("threads", tex="Fx_Chain", life=(10, 16), count=n, delay=delay, billboard="directional", gen=Gen.sphere(0.05, rx=(-70, 70), ry=(-180, 180)),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, 5, 0), (0, 10, 0))), scale=Scl.ease((length, 0.3, 1), (length * 1.4, 0.15, 1)), color=fade(S.accent, 230))


def build():
    E = []
    # 通常攻撃: 針の双刃（左右交互の斬り）
    E.append(make(P + "atk_cast", melee_swing(S, flip=False, size=1.0) + [flat_streak("needle", S.core, 1.8, 0.14, 8, z=-1.0, yaw=0)], 24))
    E.append(make(P + "atk_cast2", melee_swing(S, flip=True, size=1.0) + [flat_streak("needle", S.core, 1.8, 0.14, 8, z=-1.0, yaw=0)], 24))
    E.append(make(P + "atk_hit", hit_burst(S, 0.9, extra=[scatter("Fx_Shard", S.accent, n=5, size=0.5, speed=(2, 5), life=(14, 22))]), 28))
    # S1 サイズ（鎌）: 大きな三日月が前へ薙ぎ、糸が追う
    E.append(make(P + "s1_cast", [flat_streak("wind", S.accent, 3.0, 0.3, 9, z=-0.8), glow_core("flare", S.main, 1.6, 8, z=-0.4),
                                  decal(S.main, 2.4, 20, y=-0.85, z=-0.4)], 26))
    E.append(make(P + "s1_impact", [crescent("scythe", S.core, 5.6, 16, y=0.15, z=-2.0, a=255), crescent("scytheB", S.main, 6.4, 18, y=0.1, z=-2.2, delay=2, a=200),
                                    arc_slash("arc", S.accent, 3.4, 14, sweep=(-75, 75), y=0.2, width=0.55), under(S.main, 5, 16, y=0.1, z=-2),
                                    thread_burst(8, 2.8, delay=2), flecks(S.core, n=10, y=0.2, c2=S.accent, speed=(3, 7), spread=0.6)], 34))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0, extra=[Node("cut", tex="Fx_Streak", life=8, billboard="billboard", rot=Rot.fixed(0, 0, 35), scale=Scl.ease((0.8, 0.14, 1), (3.2, 0.06, 1), "out"), color=fade(S.core))]), 28))
    # S2 ソード（飛剣ダッシュ）: 紫の煙を残して消える → 着地で剣の奔流
    E.append(make(P + "s2_cast", [Node("smoke", tex="Fx_Smoke", blend="normal", life=22, count=8, gen=Gen.sphere(0.4, rx=(-40, 40), ry=(-180, 180), rotate=False),
                                       loc=Loc.pva(vel=((0, 0.4, 0), (0, 1.4, 0))), scale=Scl.ease(1.2, 2.4), color=Col.ease(rgba(S.dark, 200), rgba(S.dark, 0), "in")),
                                  speed_lines(S.main, 12, 3.4), glow_core("flare", S.core, 2.2, 10), thread_burst(6, 2.2), ground_pulse(S.accent, 0.3, 2.0, 14)], 30))
    E.append(make(P + "s2_impact", [ground_pulse(S.main, 0.4, 3.0, 16), ground_pulse(S.accent, 0.4, 3.4, 18, delay=3), decal(S.main, 4.6, 34, spin=-60),
                                    glow_core("flare", S.core, 3.0, 10), under(S.main, 4.2, 16),
                                    # 剣の奔流: 放射状の細い剣（Fx_Shard）が外へ
                                    Node("swords", tex="Fx_Shard", life=(12, 18), count=14, billboard="billboard", gen=Gen.circle(0.3, rotate=True),
                                         loc=Loc.pva(vel=((0, 5.5, 0), (0, 9.5, 0))), scale=Scl.ease((0.4, 1.4, 1), (0.25, 2.4, 1), "out"), color=fade(S.core)),
                                    flecks(S.accent, n=10, y=0.0, size=0.3, speed=(2, 6))], 36))
    E.append(make(P + "s2_hit", hit_burst(S, 0.9), 26))
    # ULT チェイン: 鎖を打ち込み、地面から鎖の束が立ち上がって縛る
    E.append(make(P + "ult_cast", [Node("chainshot", tex="Fx_Chain", life=12, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.ease((0, 0.2, -0.4), (0, 0.2, -3.6), "out"),
                                        scale=Scl.fixed(3.6, 0.7, 1), color=fade(S.accent, 255)),
                                   glow_core("flare", S.main, 2.4, 10, z=-0.3), thread_burst(8, 2.8), ground_pulse(S.main, 0.3, 2.4, 16)], 28))
    chains = Node("chains", tex="Fx_Chain", life=(46, 56), count=7, billboard="yfixed", rot=Rot.fixed(0, 0, 90), gen=Gen.circle(1.3, rotate=False),
                  loc=Loc.pva(pos=((0, 0.2, 0), (0, 0.2, 0)), vel=((0, 1.0, 0), (0, 1.8, 0))), scale=Scl.ease((0.5, 1.2, 1), (0.7, 4.0, 1), "out"), color=fade(S.accent, 240), fade_in=3)
    E.append(make(P + "ult_impact", [decal(S.main, 6.0, 60, spin=70), decal(S.accent, 4.0, 60, spin=-90, tex="Fx_Hex", a=170), ground_pulse(S.core, 0.4, 3.2, 18, a=255),
                                     glow_core("flare", S.core, 3.2, 12), under(S.dark, 5.4, 40, a=170), chains,
                                     Node("bind", tex="Fx_RingSoft", life=50, loc=Loc.fixed(0, 0.6, 0), scale=Scl.ease(3.4, 1.6, "in"), color=Col.ease(rgba(S.main, 40), rgba(S.accent, 220), "in")),
                                     rise("Fx_Glow", S.accent, count="inf", radius=1.6, size=0.28, life=(28, 40), interval=(2, 3), y=-0.7)], 64))
    E.append(make(P + "ult_hit", hit_burst(S, 1.1, extra=[thread_burst(6, 2.0)]), 30))
    return E


if __name__ == "__main__":
    build_set(build())
