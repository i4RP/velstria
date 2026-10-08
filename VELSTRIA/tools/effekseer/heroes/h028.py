"""H028 断空のザイル（Saber 型: 光刃の長剣・加速の突進斬り・薙ぎ払い・三連斬り）。濃紺 + シアン + 白。近接アサシン。

段: atk_cast / atk_cast2 / atk_hit / s1_cast / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit / ult_cast / ult_impact / ult_hit
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *  # noqa: E402

S = Style(core=(240, 255, 255), main=(55, 220, 255), accent=(120, 150, 255), dark=(10, 40, 95))
P = "H028_"


def blade_slash(flip=False, size=1.0, delay=0, y=0.2, z=-1.5, tilt=0):
    """光刃の斬撃（三日月 + 白い刃筋 + 風）。flip = 逆向きの振り。"""
    yaw = -10 if flip else 10
    return [crescent("slash", S.core, 3.6 * size, 9, y=y, z=z * size, delay=delay, yaw=-yaw, a=250),
            crescent("slashB", S.main, 4.4 * size, 10, y=y - 0.05, z=(z - 0.2) * size, delay=delay + 1, yaw=-yaw, a=190),
            flat_streak("edge", S.core, 3.0 * size, 0.14, 8, z=-1.2 * size, yaw=yaw, delay=delay, y=y, a=240),
            flat_streak("air", S.accent, 2.4 * size, 0.28, 9, z=-1.0 * size, yaw=-yaw * 1.4, delay=delay, y=y, a=190)]


def photon(n=8, delay=0, y=0.2, speed=(2.5, 6.5), size=0.24):
    """光の粒子が飛び散る。"""
    return flecks(S.core, n=n, speed=speed, life=(12, 22), size=size, y=y, delay=delay, gravity=-2, c2=S.main, spread=0.6)


def x_cut(size=1.0, delay=0, life=9, y=0.2, a=250):
    """交差する 2 本の斬撃（標的の位置で X 字に光る）。"""
    return [Node("cutA", tex="Fx_Streak", life=life, delay=delay, billboard="billboard", rot=Rot.fixed(0, 0, 32), loc=Loc.fixed(0, y, 0), scale=Scl.ease((1.0 * size, 0.2, 1), (4.4 * size, 0.08, 1), "out"), color=fade(S.core, a)),
            Node("cutB", tex="Fx_Streak", life=life, delay=delay + 1, billboard="billboard", rot=Rot.fixed(0, 0, -32), loc=Loc.fixed(0, y, 0), scale=Scl.ease((1.0 * size, 0.2, 1), (4.4 * size, 0.08, 1), "out"), color=fade(S.main, a))]


def build():
    E = []
    # 通常攻撃: 光刃の斬り（左右の振りは逆）
    E.append(make(P + "atk_cast", blade_slash(False, 1.0) + [photon(5)], 24))
    E.append(make(P + "atk_cast2", blade_slash(True, 1.0) + [photon(5)], 24))
    E.append(make(P + "atk_hit", hit_burst(S, 0.95, extra=x_cut(0.8, life=8)), 26))
    # S1 加速の突進斬り: 青い残像を引いて斬り抜ける
    E.append(make(P + "s1_cast", [speed_lines(S.main, 14, 3.6), glow_core("flare", S.core, 2.0, 9, z=-0.3), under(S.main, 3.0, 14, z=-0.3), ground_pulse(S.accent, 0.3, 2.0, 14, y=-0.85),
                                  flat_streak("dash", S.main, 4.2, 0.6, 12, z=-2.0, a=200)], 26))
    E.append(make(P + "s1_impact", blade_slash(False, 1.5, z=-1.6) + [flat_streak("trail", S.main, 6.0, 0.5, 14, z=-2.8, a=220), under(S.main, 4.6, 14, z=-2.4),
                                                                      burst_lines(S.core, n=10, length=1.2, y=0.2, delay=1), photon(10, delay=1, speed=(3, 8))], 30))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0, extra=x_cut(1.0, life=8)), 26))
    # S2 光刃の薙ぎ払い: 大きな半円の斬撃（ノックバック）
    sweep = [crescent("sweepA", S.core, 6.4, 13, y=0.2, z=-2.4, a=255), crescent("sweepB", S.main, 7.4, 15, y=0.15, z=-2.6, delay=2, a=210), crescent("sweepC", S.accent, 5.4, 14, y=0.1, z=-2.0, delay=3, yaw=-10, a=200),
             crescent("sweepD", S.accent, 5.4, 14, y=0.1, z=-2.0, delay=3, yaw=10, a=200)]
    E.append(make(P + "s2_cast", [glow_core("flare", S.core, 2.2, 9), speed_lines(S.accent, 8, 2.6), ground_pulse(S.main, 0.3, 2.0, 14)], 24))
    E.append(make(P + "s2_impact", sweep + [flat_streak("wind", S.core, 6.0, 0.4, 12, z=-2.8, a=200), under(S.main, 5.0, 16, z=-2.4), ground_pulse(S.main, 0.4, 3.4, 18, y=-0.8, delay=2),
                                            burst_lines(S.core, n=12, length=1.4, y=0.2, delay=1), photon(12, delay=1, speed=(3, 8))], 32))
    E.append(make(P + "s2_hit", hit_burst(S, 0.95), 24))
    # ULT 三連断空: 瞬間移動の光（術者）→ 標的に三連斬りと打ち上げの光柱
    E.append(make(P + "ult_cast", [glow_core("flare", S.core, 3.6, 12), Node("ghost", tex="Fx_Star", life=16, loc=Loc.fixed(0, 0.8, 0), scale=Scl.ease(1.2, 4.6, "out"), color=fade(S.main, 230)),
                                   pillar(S.core, 1.4, 6.0, 16), pillar(S.main, 3.0, 5.0, 20, a=150), ground_pulse(S.core, 0.4, 3.4, 16, a=255), ground_pulse(S.main, 0.4, 4.0, 20, delay=3),
                                   speed_lines(S.main, 12, 4.0), under(S.dark, 4.0, 20, a=160)], 32))
    triple = x_cut(1.5, delay=0, life=9) + x_cut(1.7, delay=8, life=9) + x_cut(2.0, delay=16, life=10)
    triple += [Node(f"flash{i}", tex="Fx_Core", life=9, delay=d, loc=Loc.fixed(0, 0.2, 0), scale=Scl.ease(0.8, 3.0, "out"), color=fade(S.core)) for i, d in enumerate((0, 8, 16))]
    E.append(make(P + "ult_impact", triple + [decal(S.main, 5.6, 50, y=-0.85, spin=80, a=220), ground_pulse(S.core, 0.4, 3.0, 16, y=-0.8, a=255, delay=16), ground_pulse(S.main, 0.4, 4.2, 22, y=-0.8, delay=18),
                                                pillar(S.core, 1.6, 8.0, 26, delay=18, y=-0.8), pillar(S.main, 3.4, 6.5, 30, delay=18, y=-0.8, a=160), glow_core("burst", S.core, 4.4, 14, delay=17),
                                                under(S.dark, 6.0, 40, a=170), burst_lines(S.core, n=16, length=1.4, y=0.3, speed=(6, 13), delay=17), photon(18, delay=17, speed=(3, 9))], 60))
    E.append(make(P + "ult_hit", hit_burst(S, 1.15, extra=x_cut(1.2, life=9)), 28))
    return E


if __name__ == "__main__":
    build_set(build())
