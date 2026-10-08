"""H029 聖槌のボルグ（Tigreal 型: 大槌の衝撃波・聖槌の踏み込み・崩落聖域）。青 + 金 + 白。近接サポート（重装）。

段: atk_cast / atk_cast2 / atk_hit / s1_cast / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit / ult_cast / ult_impact / ult_hit
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *  # noqa: E402

S = Style(core=(255, 250, 225), main=(95, 155, 255), accent=(255, 208, 95), dark=(30, 55, 135))
P = "H029_"


def hammer_smash(flip=False, size=1.0, delay=0):
    """大槌の叩きつけ（重い三日月 + 地面の衝撃 + 金の火花）。"""
    yaw = -8 if flip else 8
    return [crescent("smash", S.core, 3.8 * size, 10, y=0.3, z=-1.6 * size, delay=delay, yaw=-yaw, a=250),
            crescent("smashB", S.main, 4.8 * size, 12, y=0.2, z=-1.8 * size, delay=delay + 1, yaw=-yaw, a=200),
            ground_pulse(S.accent, 0.3, 2.0 * size, 12, y=-0.85, delay=delay + 3, a=230),
            flecks(S.accent, n=6, speed=(2, 5), size=0.22, y=0.1, delay=delay + 3, gravity=-4, c2=S.core, spread=0.6)]


def shield_glint(n=3, delay=0, size=1.6, y=0.6, radius=0.9):
    """円盾に走る金の反射光。"""
    return [Node(f"glint{i}", tex="Fx_Star", life=12, delay=delay + i * 3, loc=Loc.fixed(math.sin(i * 2.1) * radius, y + (i % 2) * 0.4, -math.cos(i * 2.1) * radius * 0.5),
                 scale=Scl.ease(size * 0.4, size, "out"), color=fade(S.accent, 240)) for i in range(n)]


def sanctuary_motes(n=14, radius=2.4, delay=0, y=-0.7, count=None, life=(34, 54)):
    """立ち昇る聖域の光（金）。"""
    return rise("Fx_Glow", S.accent, n=n, radius=radius, life=life, size=0.3, y=y, delay=delay, count=count)


def build():
    E = []
    # 通常攻撃: 大槌の叩きつけ
    E.append(make(P + "atk_cast", hammer_smash(False, 1.0), 26))
    E.append(make(P + "atk_cast2", hammer_smash(True, 1.0), 26))
    E.append(make(P + "atk_hit", hit_burst(S, 1.05, extra=[ground_pulse(S.main, 0.3, 2.0, 14, y=-0.8), scatter("Fx_Diamond", S.accent, n=5, size=0.5, speed=(2, 5), life=(14, 22))]), 28))
    # S1 聖槌の衝撃波: 叩きつけた衝撃が前へ走る（スロー）
    waves = [flat_streak(f"wave{i}", S.main if i % 2 else S.core, 3.2 + i * 0.6, 0.9 - i * 0.12, 12, z=-1.6 - i * 1.5, delay=i * 2, a=225, y=0.1) for i in range(3)]
    E.append(make(P + "s1_cast", hammer_smash(False, 1.2) + waves + [glow_core("flare", S.core, 2.0, 10, z=-0.5)], 30))
    E.append(make(P + "s1_impact", [ground_pulse(S.core, 0.4, 3.2, 16, y=-0.8, a=255, delay=0), ground_pulse(S.main, 0.4, 3.8, 20, y=-0.8, delay=2), ground_pulse(S.accent, 0.4, 4.4, 24, y=-0.8, delay=4),
                                    glow_core("flare", S.core, 2.8, 10, z=-3.2), under(S.main, 4.6, 18, z=-3.0), decal(S.main, 5.0, 36, y=-0.84, z=-3.0, tex="Fx_Crack", a=210, grow=0.8),
                                    # スロー: 青い霜の粒が足もとに
                                    rise("Fx_Glow", S.main, count=12, radius=1.8, size=0.26, life=(24, 40), y=-0.7, delay=2), flecks(S.accent, n=10, y=0.0, speed=(2, 6), c2=S.core)], 36))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0, extra=[ground_pulse(S.main, 0.3, 1.8, 14, y=-0.8)]), 26))
    # S2 聖槌の踏み込み: 盾を構えて突進 → 叩き伏せてスタン（金の星が頭上で回る）
    E.append(make(P + "s2_cast", [speed_lines(S.accent, 12, 3.4), glow_core("flare", S.core, 2.2, 10), under(S.main, 3.2, 14), ground_pulse(S.main, 0.3, 2.2, 14)] + shield_glint(3, 0, 1.8, 0.7, 0.8), 30))
    E.append(make(P + "s2_impact", [ground_pulse(S.core, 0.4, 3.4, 16, y=-0.8, a=255), ground_pulse(S.accent, 0.4, 4.0, 22, y=-0.8, delay=3), glow_core("flare", S.core, 3.4, 12), under(S.main, 4.6, 20),
                                    decal(S.main, 5.0, 40, y=-0.84, tex="Fx_Crack", a=230, grow=0.8), decal(S.accent, 3.6, 44, y=-0.83, spin=90, a=200),
                                    burst_lines(S.core, n=12, length=1.2, y=0.2), scatter("Fx_Diamond", S.accent, n=10, size=0.55, speed=(3, 8), life=(16, 26)),
                                    Node("stunring", tex="Fx_Wheel", life=44, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 360)), loc=Loc.fixed(0, 1.3, 0), scale=Scl.fixed(1.5), color=Col.ease(rgba(S.accent, 235), rgba(S.accent, 0), "in"), fade_in=4),
                                    Node("stunstar", tex="Fx_Star", life=44, loc=Loc.fixed(0, 1.3, 0), scale=Scl.fixed(1.0), color=Col.ease(rgba(S.core, 230), rgba(S.core, 0), "in"), fade_in=4)], 50))
    E.append(make(P + "s2_hit", hit_burst(S, 1.0, extra=[ground_pulse(S.accent, 0.3, 1.8, 14, y=-0.8)]), 26))
    # ULT 崩落聖域: 青と金の聖域が立ち上がる（6 秒）→ 引き寄せて叩き伏せる崩落
    dome = Node("dome", tex="Fx_Hex", life=360, billboard="billboard", loc=Loc.fixed(0, 0.6, 0), scale=Scl.fixed(6.2), color=Col.fixed(*S.main, 110), fade_in=14, fade_out=30)
    E.append(make(P + "ult_cast", [dome, Node("dome2", tex="Fx_Hex", life=360, billboard="billboard", loc=Loc.fixed(0, 0.6, 0), rot=Rot.pva(0, (0, 0, 40)), scale=Scl.fixed(4.6), color=Col.fixed(*S.accent, 90), fade_in=14, fade_out=30),
                                   decal(S.main, 8.0, 90, y=-0.85, spin=40, a=230), decal(S.accent, 5.4, 90, y=-0.84, tex="Fx_Hex", spin=-60, a=190), ground_pulse(S.core, 0.5, 4.8, 20, y=-0.8, a=255),
                                   ground_pulse(S.accent, 0.5, 5.6, 26, y=-0.8, delay=6), glow_core("flare", S.core, 3.6, 14), pillar(S.accent, 1.4, 6.0, 26), under(S.dark, 6.0, 40, a=150),
                                   Node("aura", tex="Fx_Glow", life=360, scale=Scl.fixed(3.4), color=Col.fixed(*S.accent, 60), fade_in=12, fade_out=30),
                                   Node("motes", tex="Fx_Glow", life=(26, 44), count="inf", interval=(2, 3), gen=Gen.circle(2.2, rotate=False), delay=10, loc=Loc.pva(pos=((0, -0.9, 0), (0, -0.9, 0)), vel=((0, 0.8, 0), (0, 2.2, 0))),
                                        scale=Scl.ease(0.28, 0.04), color=morph(S.core, S.accent, 230, 0))], 380))
    # 崩落: 外から内へ縮む輪（引き寄せ）→ 中央で叩きつけ（回復の光 + 敵はスタン）
    pull = [Node(f"pull{i}", tex="Fx_Ring", life=22, delay=i * 4, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(0, -0.8, 0), scale=Scl.ease(10.0 - i, 1.0, "in"), color=Col.ease(rgba(S.main if i % 2 else S.accent, 60), rgba(S.core, 240), "lin")) for i in range(3)]
    E.append(make(P + "ult_impact", pull + [glow_core("slam", S.core, 5.0, 14, delay=16), Node("star", tex="Fx_Star", life=16, delay=16, scale=Scl.ease(1.8, 6.0, "out"), color=fade(S.accent)),
                                            ground_pulse(S.core, 0.5, 5.0, 18, y=-0.8, a=255, delay=16), ground_pulse(S.main, 0.5, 6.0, 24, y=-0.8, delay=18), ground_pulse(S.accent, 0.5, 6.8, 28, y=-0.8, delay=20),
                                            decal(S.main, 7.4, 50, y=-0.84, tex="Fx_Crack", a=230, grow=0.7, delay=16), under(S.dark, 7.0, 40, delay=16, a=170),
                                            burst_lines(S.core, n=18, length=1.5, y=0.3, speed=(6, 14), delay=16), scatter("Fx_Diamond", S.accent, n=16, size=0.6, speed=(3, 9), life=(18, 30), delay=16),
                                            # 味方の回復: 金の光の粒が昇る
                                            sanctuary_motes(24, 3.0, delay=18, count=24)], 70))
    E.append(make(P + "ult_hit", hit_burst(S, 1.15, extra=[ground_pulse(S.accent, 0.3, 2.2, 16, y=-0.8)]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
