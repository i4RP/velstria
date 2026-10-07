"""H020 光矢のユナ（Yi Sun-shin 型: グレイブ・長弓・亀甲船）。海の青 + 白金。近接デュエリスト。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(245, 252, 255), main=(110, 215, 255), accent=(255, 224, 130), dark=(20, 90, 150))
P = "H020_"


def build():
    E = []
    # 通常攻撃: 光の刃（グレイブ）の連斬り
    E.append(make(P + "atk_cast", melee_swing(S, flip=False, size=1.05), 24))
    E.append(make(P + "atk_cast2", melee_swing(S, flip=True, size=1.05), 24))
    E.append(make(P + "atk_hit", hit_burst(S, 0.95, extra=[flat_streak("cut", S.core, 2.6, 0.2, 7, z=0.0, yaw=0)]), 28))
    # S1 無跡: 前へ斬り抜ける（青い軌跡 + 残像）
    E.append(make(P + "s1_cast", [speed_lines(S.main, 10, 3.0), glow_core("flare", S.core, 1.8, 8, z=-0.3)], 24))
    E.append(make(P + "s1_impact", [crescent("slash", S.core, 5.4, 14, y=0.15, z=-2.2, a=255), arc_slash("arc", S.main, 3.6, 13, sweep=(-70, 70), y=0.2, width=0.5),
                                    flat_streak("trail", S.main, 5.6, 0.5, 14, z=-2.4, a=220), under(S.main, 4.6, 14, z=-2),
                                    burst_lines(S.accent, n=10, length=1.2, y=0.2, delay=1), flecks(S.core, n=8, c2=S.main, y=0.2, speed=(3, 7), spread=0.5)], 28))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0), 26))
    # S2 血潮: 突進して振り抜く → 着地で光の矢の貫通（青い光線）
    E.append(make(P + "s2_cast", [speed_lines(S.accent, 12, 3.6), glow_core("flare", S.core, 2.2, 9), flat_streak("beam", S.main, 6.0, 0.7, 12, z=-3.2, a=235),
                                  ground_pulse(S.main, 0.3, 2.0, 14)], 28))
    E.append(make(P + "s2_impact", [ground_pulse(S.core, 0.4, 3.0, 16, a=255), ground_pulse(S.main, 0.4, 3.6, 20, delay=3), glow_core("flare", S.core, 3.0, 10),
                                    Node("star", tex="Fx_Star", life=14, loc=Loc.fixed(0, 0.2, 0), scale=Scl.ease(1.6, 4.6, "out"), color=fade(S.accent)),
                                    under(S.main, 4.2, 16), burst_lines(S.core, n=12, length=1.3, speed=(5, 11)), flecks(S.main, n=10, y=0.1, speed=(2, 6))], 34))
    E.append(make(P + "s2_hit", hit_burst(S, 0.9), 24))
    # ULT 亀甲船: 巨大な魔法陣（船団）+ 3 波の艦砲射撃（連撃のたびに環状の爆発）
    big = [decal(S.main, 9.0, 36, y=-0.85, spin=30, a=200), decal(S.accent, 6.4, 36, y=-0.84, tex="Fx_Hex", spin=-45, a=170)]
    E.append(make(P + "ult_cast", big + [glow_core("flare", S.core, 3.6, 14), ground_pulse(S.main, 0.5, 5.0, 24, a=255),
                                         Node("hull", tex="Fx_Hex", blend="normal", life=40, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(0, -0.8, 0),
                                              scale=Scl.fixed(3.6), color=Col.ease(rgba(S.dark, 150), rgba(S.dark, 0), "in"), fade_in=6),
                                         rise("Fx_Glow", S.core, count=24, radius=3.0, size=0.34, life=(26, 44), y=-0.8)], 50))
    wave = lambda d: [ground_pulse(S.core, 0.5, 4.2, 14, y=-0.8, delay=d, a=255), ground_pulse(S.accent, 0.5, 5.0, 18, y=-0.8, delay=d + 2),
                      glow_core("blast", S.core, 3.4, 10, y=0.0, delay=d), under(S.dark, 5.0, 18, delay=d, y=0.0, a=180),
                      Node("shell", tex="Fx_Streak", life=(8, 12), count=6, delay=d, billboard="yfixed", rot=Rot.fixed(0, 0, 90), gen=Gen.circle(2.0, rotate=False),
                           loc=Loc.pva(pos=((0, 2.5, 0), (0, 3.5, 0)), vel=((0, -16, 0), (0, -22, 0))), scale=Scl.fixed(0.35, 3.0, 1), color=fade(S.core, 230)),
                      flecks(S.accent, n=14, y=0.2, speed=(3, 8), c2=S.main, delay=d + 1)]
    E.append(make(P + "ult_impact", wave(0), 34))
    E.append(make(P + "ult_hit", hit_burst(S, 1.2, extra=[glow_core("pop", S.accent, 2.2, 10)]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
