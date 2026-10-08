"""H013 獣刻のダガン（Fredrinn 型: 結晶の鎧・突き・鑑定士の怒り）。琥珀 + 結晶の桃紫。近接ヴァンガード。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(255, 245, 225), main=(255, 170, 70), accent=(255, 120, 200), dark=(120, 50, 40))
P = "H013_"


def crystals(n=8, radius=1.8, h=(1.4, 2.6), delay=0, life=(22, 34), c=None):
    """地面から突き出す結晶（縦長の菱形が伸びて消える）。"""
    return Node("crystals", tex="Fx_Shard", life=life, count=n, delay=delay, billboard="yfixed", gen=Gen.circle(radius, rotate=False),
                loc=Loc.fixed(0, 0.0, 0), scale=Scl.ease((0.3, 0.2, 1), (0.8, h[1], 1), "out"), color=Col.ease(rgba(c or S.accent, 255), rgba(c or S.accent, 0), "in"))


def build():
    E = []
    # 通常攻撃: 骨の棍棒の叩きつけ（重い弧 + 土煙）
    heavy = lambda flip: melee_swing(S, flip=flip, size=1.15) + [Node("dust", tex="Fx_Smoke", blend="normal", life=22, count=3, gen=Gen.circle(0.6), loc=Loc.pva(pos=((0, -0.8, -1.2), (0, -0.8, -1.2)), vel=((0, 0.3, 0), (0, 0.9, 0))),
                                                                  scale=Scl.ease(0.6, 1.4), color=Col.ease(rgba((220, 190, 150), 120), rgba((220, 190, 150), 0), "in"))]
    E.append(make(P + "atk_cast", heavy(False), 26))
    E.append(make(P + "atk_cast2", heavy(True), 26))
    E.append(make(P + "atk_hit", hit_burst(S, 1.0, extra=[scatter("Fx_Shard", S.accent, n=4, size=0.5, speed=(2, 5))]), 28))
    # S1 ピアッシングストライク: 長い突き + 結晶の穂先
    E.append(make(P + "s1_cast", [glow_core("flare", S.core, 1.8, 8, z=-0.5), flat_streak("charge", S.main, 2.6, 0.4, 8, z=-0.8)], 22))
    E.append(make(P + "s1_impact", [flat_streak("spear", S.core, 6.0, 0.6, 12, z=-2.8), flat_streak("spear2", S.accent, 6.0, 0.9, 14, z=-2.8, a=170), under(S.main, 4.6, 16, z=-2.6),
                                    glow_core("tip", S.core, 2.4, 10, z=-5.4), crystals(5, 1.0, delay=2), burst_lines(S.main, n=8, length=1.2, y=0.2, delay=2)], 32))
    E.append(make(P + "s1_hit", hit_burst(S, 1.0), 26))
    # S2 ブレイブアサルト: ダッシュ斬り → 着地の亀裂
    E.append(make(P + "s2_cast", [speed_lines(S.main, 12, 3.2), glow_core("flare", S.core, 2.2, 9), flat_streak("lunge", S.accent, 4.0, 0.7, 12, z=-1.6, a=200)], 28))
    E.append(make(P + "s2_impact", [ground_pulse(S.core, 0.4, 3.0, 16, a=255), ground_pulse(S.main, 0.4, 3.6, 20, delay=3), decal(S.accent, 4.2, 40, tex="Fx_Crack", grow=0.5, a=235),
                                    glow_core("flare", S.core, 2.8, 10), under(S.dark, 4.4, 18, a=180), crystals(6, 1.4, delay=2), flecks(S.main, n=12, y=0.0, speed=(3, 8))], 40))
    E.append(make(P + "s2_hit", hit_burst(S, 0.95), 24))
    # ULT 鑑定士の怒り: 跳んで叩きつけ → 扇状に結晶の爆発（大きな亀裂と柱）
    E.append(make(P + "ult_cast", [glow_core("flare", S.core, 3.0, 12), decal(S.main, 4.6, 24, spin=60), speed_lines(S.accent, 10, 3.6), ground_pulse(S.main, 0.4, 3.4, 18)], 30))
    E.append(make(P + "ult_impact", [ground_pulse(S.core, 0.5, 4.6, 18, a=255), ground_pulse(S.main, 0.5, 5.4, 22, delay=3), ground_pulse(S.accent, 0.5, 5.4, 26, delay=7),
                                     decal(S.accent, 7.0, 56, tex="Fx_Crack", grow=0.5, a=240), decal(S.main, 6.4, 56, spin=-40),
                                     glow_core("flare", S.core, 4.2, 12), under(S.dark, 6.4, 30, a=190), crystals(12, 2.8, h=(2, 3.6), delay=2), crystals(8, 1.4, delay=4, c=S.main),
                                     Node("shock", tex="Fx_RingSoft", life=16, loc=Loc.fixed(0, 0.6, 0), scale=Scl.ease(1.0, 6.4, "out"), color=fade(S.core, 220)),
                                     scatter("Fx_Shard", S.accent, n=18, size=0.7, speed=(4, 10), life=(24, 40)), flecks(S.main, n=20, y=0.2, speed=(3, 10))], 64))
    E.append(make(P + "ult_hit", hit_burst(S, 1.2, extra=[scatter("Fx_Shard", S.accent, n=6, size=0.6)]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
