"""H027 竜槍のジャルド（趙子龍 型: 長槍の連突き・竜牙の踏み込み突き・昇竜）。銀青 + 白 + 赤の房。近接デュエリスト。

段: atk_cast / atk_cast2 / atk_hit / s1_cast / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit / ult_cast / ult_impact / ult_hit
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *  # noqa: E402

S = Style(core=(245, 250, 255), main=(150, 190, 240), accent=(255, 95, 95), dark=(40, 70, 135))
P = "H027_"


def thrust(length=4.4, width=0.26, life=8, z=-1.6, yaw=0, delay=0, c=None, a=240):
    """槍の突き（細長い筋 + 穂先の輝き）。"""
    return [flat_streak("spear", c or S.core, length, width, life, z=z, yaw=yaw, a=a, delay=delay, y=0.2),
            flat_streak("wake", S.main, length * 0.8, width * 2.2, life + 2, z=z + 0.2, yaw=yaw, a=150, delay=delay, y=0.18),
            Node("tip", tex="Fx_Star", life=life + 2, delay=delay, loc=Loc.ease((0, 0.2, z + length * 0.1), (0, 0.2, z - length * 0.45), "out"), scale=Scl.ease(0.5, 1.4, "out"), color=fade(S.core, 230))]


def tassel(n=6, delay=0, y=0.3, z=-0.5):
    """赤い房飾りが舞う。"""
    return flecks(S.accent, n=n, speed=(1.5, 4), life=(14, 24), size=0.24, y=y, delay=delay, gravity=-4, c2=S.core, spread=0.7)


def scales_burst(n=8, delay=0, y=0.0, size=0.6, speed=(2, 5)):
    """竜鱗（銀青の細片）が散る。"""
    return scatter("Fx_Diamond", S.main, n=n, size=size, speed=speed, life=(16, 26), y=y, delay=delay, gravity=-5, spin=220, c2=S.core, spread=0.8)


def build():
    E = []
    # 通常攻撃: 長槍の突き（左右の振りは穂先の角度で）
    E.append(make(P + "atk_cast", thrust(4.2, 0.26, 8, -1.7, 0) + [tassel(3)], 22))
    E.append(make(P + "atk_cast2", thrust(4.2, 0.26, 8, -1.7, -9) + [flat_streak("spear2", S.main, 3.0, 0.16, 7, z=-1.5, yaw=8, delay=2, a=200, y=0.2), tassel(3)], 22))
    E.append(make(P + "atk_hit", hit_burst(S, 0.95, extra=[flat_streak("pierce", S.core, 2.6, 0.2, 7, z=0.0), scales_burst(5)]), 28))
    # S1 竜槍・連突き: 三連の突きが扇に走る
    E.append(make(P + "s1_cast", thrust(4.4, 0.26, 8, -1.8, 0) + thrust(4.0, 0.22, 8, -1.7, -10, delay=3, c=S.main) + thrust(4.0, 0.22, 8, -1.7, 10, delay=6, c=S.main)
             + [glow_core("flare", S.core, 1.8, 9, z=-0.5), ground_pulse(S.main, 0.3, 2.0, 14, y=-0.85), tassel(5, delay=2)], 30))
    E.append(make(P + "s1_impact", [glow_core("flare", S.core, 2.6, 10, z=-3.2), Node("star", tex="Fx_Star", life=14, loc=Loc.fixed(0, 0.2, -3.2), scale=Scl.ease(1.2, 3.8, "out"), color=fade(S.main)),
                                    burst_lines(S.core, n=12, length=1.2, y=0.2, speed=(5, 11)), under(S.main, 4.0, 16, z=-3.0), ground_pulse(S.main, 0.3, 2.6, 16, y=-0.8, delay=1),
                                    scales_burst(8, y=0.2)], 30))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0, extra=[flat_streak("pierce", S.core, 2.4, 0.2, 7, z=0.0), scales_burst(4)]), 26))
    # S2 竜牙の踏み込み: 銀青の竜が走る（牙の筋）→ 敵を打ち上げる
    fangs = [flat_streak(f"fang{i}", S.main if i else S.core, 6.0 - i * 0.8, 0.5 - i * 0.12, 14, z=-3.2, yaw=a, a=235, y=0.15) for i, a in enumerate((0, -9, 9))]
    E.append(make(P + "s2_cast", fangs + [speed_lines(S.accent, 12, 3.6), glow_core("flare", S.core, 2.2, 9), ground_pulse(S.main, 0.3, 2.0, 14), tassel(6)], 30))
    E.append(make(P + "s2_impact", [ground_pulse(S.core, 0.4, 3.0, 16, y=-0.8, a=255), ground_pulse(S.main, 0.4, 3.6, 22, y=-0.8, delay=3), glow_core("flare", S.core, 3.0, 12),
                                    under(S.main, 4.4, 18), decal(S.main, 4.4, 30, y=-0.84, tex="Fx_Crack", a=220, grow=0.8),
                                    # 打ち上げ: 地面から竜牙（縦長の破片）が突き上がる
                                    Node("fangs", tex="Fx_Shard", life=(14, 20), count=9, billboard="billboard", gen=Gen.circle(1.3, rotate=False), loc=Loc.pva(pos=((0, -0.8, 0), (0, -0.8, 0)), vel=((0, 5, 0), (0, 9, 0)), acc=(0, -14, 0)),
                                         scale=Scl.ease((0.5, 1.7, 1), (0.3, 1.0, 1)), color=fade(S.core, 240)),
                                    pillar(S.main, 1.4, 4.0, 18, y=-0.8), scales_burst(10, y=0.0, speed=(3, 7))], 36))
    E.append(make(P + "s2_hit", hit_burst(S, 1.0, extra=[scales_burst(5)]), 26))
    # ULT 昇竜天翔: 銀青の竜が纏わり（軽減の殻）→ 飛び込み連撃の竜巻
    coil = Node("coil", tex="Fx_Spiral", life=300, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 220)), loc=Loc.fixed(0, 0.1, 0), scale=Scl.fixed(3.4), color=Col.fixed(*S.main, 130), fade_in=12, fade_out=30)
    E.append(make(P + "ult_cast", [coil, Node("coil2", tex="Fx_Spiral", life=300, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, -300)), loc=Loc.fixed(0, 0.6, 0), scale=Scl.fixed(2.4), color=Col.fixed(*S.core, 110), fade_in=12, fade_out=30),
                                   Node("shell", tex="Fx_Hex", life=300, billboard="billboard", scale=Scl.fixed(3.4), color=Col.fixed(*S.main, 120), fade_in=10, fade_out=30),
                                   Node("aura", tex="Fx_Glow", life=300, scale=Scl.fixed(2.6), color=Col.fixed(*S.dark, 90), fade_in=12, fade_out=30, blend="normal"),
                                   decal(S.main, 5.0, 50, y=-0.85, spin=60, a=220), ground_ring(S.core, 0.4, 3.6, 20, y=-0.85, alpha=255), glow_core("flare", S.core, 3.0, 12), pillar(S.main, 1.2, 4.6, 22),
                                   Node("motes", tex="Fx_Glow", life=(24, 40), count="inf", interval=(2, 4), gen=Gen.circle(0.9, rotate=False), delay=8, loc=Loc.pva(pos=((0, -0.9, 0), (0, -0.9, 0)), vel=((0, 0.8, 0), (0, 2.0, 0))),
                                        scale=Scl.ease(0.24, 0.04), color=morph(S.core, S.main, 220, 0)), tassel(8, delay=2)], 320))
    rise_dragon = [Node("dragon", tex="Fx_Spiral", life=36, billboard="yfixed", rot=Rot.fixed(0, 0, 0), loc=Loc.fixed(0, 2.4, 0), scale=Scl.ease((1.4, 2.4, 1), (2.6, 5.4, 1), "out"), color=fade(S.main, 230)),
                   pillar(S.core, 1.6, 7.5, 26, y=-0.8), pillar(S.main, 3.2, 6.0, 30, y=-0.8, a=170)]
    E.append(make(P + "ult_impact", rise_dragon + [ground_pulse(S.core, 0.5, 4.2, 18, y=-0.8, a=255), ground_pulse(S.accent, 0.5, 5.0, 22, y=-0.8, delay=4), decal(S.main, 7.0, 60, y=-0.85, spin=-70, a=220),
                                                  glow_core("flare", S.core, 4.0, 14), under(S.dark, 6.0, 30, a=170), burst_lines(S.core, n=16, length=1.4, y=0.3, speed=(6, 13)),
                                                  Node("slash", tex="Fx_Streak", life=10, count=5, billboard="billboard", gen=Gen.circle(0.5, rotate=False), delay=2, interval=(3, 4), rot=Rot.pva(0, ((0, 0, 20), (0, 0, 160))),
                                                       scale=Scl.fixed(3.6, 0.3, 1), color=fade(S.core, 235)),
                                                  scales_burst(18, y=0.2, size=0.7, speed=(3, 9)), tassel(10, delay=3)], 60))
    E.append(make(P + "ult_hit", hit_burst(S, 1.15, extra=[flat_streak("pierce", S.core, 2.8, 0.22, 7, z=0.0), scales_burst(6)]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
