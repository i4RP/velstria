"""H025 月弦のルミナ（Miya 型: 月光の矢・扇状に分かれる矢・月影ステップ・月の祝福）。翠緑 + 白銀 + 淡い月光の黄。遠隔レンジャー。

段: atk_cast / atk_travel / atk_hit / s1_cast / s1_travel / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit /
    ult_cast / ult_travel / ult_impact / ult_hit（H003 と同じ構成）
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *  # noqa: E402

S = Style(core=(240, 255, 240), main=(120, 235, 165), accent=(255, 244, 180), dark=(30, 110, 75))
P = "H025_"


def moon_flash(size=2.0, life=10, z=-0.5, y=0.0, delay=0, c=None, a=230):
    """三日月の閃光（矢の発射・命中のたびに一瞬走る）。"""
    return crescent("moon", c or S.accent, size, life, y=y, z=z, delay=delay, a=a, flat=False, grow=(0.5, 1.0))


def moon_motes(n=10, radius=1.4, life=(30, 50), delay=0, y=-0.6, count=None):
    """立ち昇る月光の粒（翠と月光の黄）。"""
    return rise("Fx_Glow", S.accent, n=n, radius=radius, life=life, size=0.26, y=y, delay=delay, count=count)


def arrow_fan(angles, length=3.6, life=12, z=-1.8, c=None, width=0.24, delay=0):
    """扇状に走る月光の矢の筋（地面と平行）。"""
    return [flat_streak(f"ray{i}", c or (S.core if a == 0 else S.main), length, width, life, z=z, yaw=a, a=235, y=0.1, delay=delay) for i, a in enumerate(angles)]


def build():
    E = []
    # 通常攻撃: 月光の矢
    E.append(make(P + "atk_cast", ranged_muzzle(S, 1.0) + [moon_flash(1.9, 10, z=-0.7)], 24))
    E.append(make(P + "atk_travel", projectile(S, "arrow", 1.0) + [Node("moondust", tex="Fx_Star", life=(10, 16), count="inf", interval=(5, 7), detach=True, gen=Gen.sphere(0.3, rx=(-90, 90), ry=(-180, 180), rotate=False),
                                                                      scale=Scl.ease(0.5, 0.05), color=fade(S.accent, 220))], 40, loop=True))
    E.append(make(P + "atk_hit", hit_burst(S, 0.95, extra=[moon_flash(1.6, 10, z=0.0, y=0.1), ground_pulse(S.main, 0.3, 1.7, 14, y=-0.7)]), 28))
    # S1 Lumina式・一閃: 扇状に分かれる月矢
    E.append(make(P + "s1_cast", arrow_fan((-24, 0, 24), 3.2, 11, z=-1.5) + [glow_core("flare", S.core, 1.8, 9, z=-0.5), moon_flash(2.4, 11, z=-0.9, y=0.1),
                                                                         ground_pulse(S.main, 0.3, 2.0, 14, y=-0.85), flecks(S.accent, n=6, speed=(2, 5), size=0.2, y=0.1, c2=S.main, gravity=-2, spread=0.5)], 28))
    side = [Node(f"split{i}", tex="Fx_Arrow", life=600, billboard="fixed", rot=Rot.fixed(90, 90 + a, 0), loc=Loc.fixed(x, 0, -0.1), scale=Scl.fixed(1.5, 0.3, 1), color=Col.fixed(*S.main, 235))
            for i, (a, x) in enumerate(((16, -0.3), (-16, 0.3)))]
    E.append(make(P + "s1_travel", projectile(S, "arrow", 1.15) + side, 40, loop=True))
    E.append(make(P + "s1_impact", hit_burst(S, 1.2, extra=[moon_flash(2.8, 12, z=0.0, y=0.1), moon_flash(2.2, 12, z=0.0, y=0.1, delay=3, c=S.main), ground_pulse(S.accent, 0.3, 2.6, 16, y=-0.8)]), 32))
    E.append(make(P + "s1_hit", hit_burst(S, 0.9, extra=[moon_flash(1.5, 9, z=0.0, y=0.1)]), 26))
    # S2 星環シフト: 月影に身を隠す短距離ブリンク（残像 + 次の矢の強化の輝き）
    E.append(make(P + "s2_cast", [speed_lines(S.main, 12, 3.4), glow_core("flare", S.core, 2.2, 10, z=0.3), under(S.main, 3.0, 14, z=0.3),
                                  Node("ghost", tex="Fx_Star", life=14, loc=Loc.fixed(0, 0, 0.4), scale=Scl.ease(1.0, 3.2, "out"), color=fade(S.accent, 210)),
                                  ground_pulse(S.accent, 0.3, 2.2, 14, y=-0.85), moon_flash(2.2, 12, z=0.8, y=0.2, a=200)], 30))
    E.append(make(P + "s2_impact", [glow_core("flare", S.core, 2.6, 10), Node("star", tex="Fx_Star", life=14, scale=Scl.ease(1.0, 3.4, "out"), color=fade(S.accent)),
                                    moon_flash(3.0, 12, z=0.0, y=0.1), ground_pulse(S.core, 0.3, 2.6, 16, y=-0.85, a=255), ground_pulse(S.main, 0.3, 3.0, 20, y=-0.85, delay=3),
                                    under(S.main, 3.8, 16), burst_lines(S.core, n=10, length=1.0), moon_motes(10, 1.0, (20, 34), delay=2, y=-0.5)], 36))
    E.append(make(P + "s2_hit", hit_burst(S, 0.85), 24))
    # ULT 月華の天弦: 月光を纏う（月の輪が周回する 6 秒） → 貫通する大矢
    orbit_moons = Node("orbit", tex="Fx_Glow", life=360, loc=Loc.fixed(0, 0.2, 0), rot=Rot.pva(0, (0, 300, 0)), scale=Scl.fixed(0.01), color=Col.fixed(255, 255, 255, 0))
    for i, a in enumerate((0, 120, 240)):
        px, pz = math.sin(math.radians(a)) * 1.3, -math.cos(math.radians(a)) * 1.3
        orbit_moons.add(Node(f"m{i}", tex="Fx_Crescent", life=360, billboard="billboard", loc=Loc.fixed(px, 0.0, pz), scale=Scl.fixed(1.1), color=Col.fixed(*S.accent, 245), fade_in=10, fade_out=24))
        orbit_moons.add(Node(f"g{i}", tex="Fx_Glow", life=360, loc=Loc.fixed(px, 0.0, pz), scale=Scl.fixed(1.8), color=Col.fixed(*S.main, 110), fade_in=10, fade_out=24))
    E.append(make(P + "ult_cast", [orbit_moons, rune(S.main, 5.0, 60, y=-0.85, alpha=230), ground_ring(S.core, 0.4, 4.0, 20, y=-0.85, alpha=255), ground_ring(S.accent, 0.4, 4.0, 24, y=-0.85, delay=8),
                                   glow_core("flare", S.core, 3.4, 14), pillar(S.accent, 1.0, 4.6, 22, y=0.0), under(S.main, 4.0, 20, y=0.0),
                                   Node("aura", tex="Fx_Glow", life=360, scale=Scl.fixed(2.6), color=Col.fixed(*S.main, 70), fade_in=12, fade_out=30),
                                   Node("motes", tex="Fx_Glow", life=(24, 40), count="inf", interval=(2, 3), gen=Gen.circle(0.9, rotate=False), delay=10,
                                        loc=Loc.pva(pos=((0, -0.9, 0), (0, -0.9, 0)), vel=((0, 0.8, 0), (0, 2.0, 0))), scale=Scl.ease(0.26, 0.04), color=morph(S.core, S.accent, 220, 0))], 380))
    E.append(make(P + "ult_travel", projectile(S, "arrow", 2.2) + [Node("beam", tex="Fx_Beam", life=600, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.fixed(0, 0, 1.4), scale=Scl.fixed(4.4, 0.9, 1), color=Col.fixed(*S.main, 150)),
                                                                   Node("moon", tex="Fx_Crescent", life=600, billboard="billboard", scale=Scl.fixed(2.8), color=Col.fixed(*S.accent, 190)),
                                                                   Node("ring", tex="Fx_Wheel", life=600, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 360)), scale=Scl.fixed(2.4), color=Col.fixed(*S.core, 150))], 60, loop=True))
    E.append(make(P + "ult_impact", [glow_core("flare", S.core, 4.2, 12), Node("star", tex="Fx_Star", life=16, scale=Scl.ease(1.6, 5.6, "out"), color=fade(S.accent)),
                                     moon_flash(5.2, 14, z=0.0, y=0.1), moon_flash(4.0, 14, z=0.0, y=0.1, delay=3, c=S.main), ground_pulse(S.core, 0.4, 3.4, 16, y=-0.7, a=255),
                                     ground_pulse(S.main, 0.4, 4.0, 22, y=-0.7, delay=4), under(S.main, 5.0, 18), spark_lines(S.core, n=14, speed=(5, 12), life=(9, 15), length=1.2, y=0),
                                     scatter("Fx_Crescent", S.accent, n=8, size=0.9, speed=(3, 7), life=(18, 30), gravity=-1, spin=200, c2=S.main, y=0.0),
                                     sparks(S.accent, n=12, speed=(2, 6), life=(16, 28), size=0.3, gravity=-5, y=0, c2=S.main)], 44))
    E.append(make(P + "ult_hit", hit_burst(S, 1.1, extra=[moon_flash(2.0, 12, z=0.0, y=0.1)]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
