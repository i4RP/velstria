"""H030 星砲のライナ（Layla 型: 連射する星の砲弾・反動で下がる射撃・星砕の大砲）。桃 + 白 + 金。遠隔レンジャー。

段: atk_cast / atk_travel / atk_hit / s1_cast / s1_travel / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit /
    ult_cast / ult_travel / ult_impact / ult_hit（H003 と同じ構成）
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *  # noqa: E402

S = Style(core=(255, 248, 240), main=(255, 125, 185), accent=(255, 214, 96), dark=(150, 38, 95))
P = "H030_"


def star_flash(size=2.0, life=10, z=-0.5, y=0.0, delay=0, c=None, a=240, spin=0):
    """星形の閃光（砲口・着弾のたびに一瞬走る）。"""
    return Node("starflash", tex="Fx_Star", life=life, delay=delay, loc=Loc.fixed(0, y, z), rot=Rot.pva(0, (0, 0, spin)) if spin else None,
                scale=Scl.ease(size * 0.4, size, "out"), color=fade(c or S.accent, a))


def star_scatter(n=6, size=0.6, speed=(2, 6), life=(16, 28), delay=0, y=0.0):
    """回りながら散る小さな星。"""
    return scatter("Fx_Star", S.accent, n=n, size=size, speed=speed, life=life, y=y, delay=delay, gravity=-3, spin=260, c2=S.main)


def cannon_smoke(n=3, z=-0.5, size=(0.5, 1.3), delay=0, life=(16, 24)):
    """砲口の硝煙（桃みがかった通常合成の煙）。"""
    return Node("smoke", tex="Fx_Smoke", blend="normal", life=life, count=n, delay=delay, gen=Gen.sphere(0.2, rx=(-40, 40), ry=(-180, 180), rotate=False),
                loc=Loc.pva(pos=((0, 0, z), (0, 0, z)), vel=((0, 0.3, 0), (0, 1.0, 0))), scale=Scl.ease(size[0], size[1]), color=Col.ease(rgba(S.dark, 150), rgba(S.dark, 0), "in"))


def shell_rays(angles, length=3.4, life=11, z=-1.7, width=0.26, delay=0, c=None):
    """扇状に走る砲弾の筋（地面と平行）。"""
    return [flat_streak(f"ray{i}", c or (S.core if a == 0 else S.main), length, width, life, z=z, yaw=a, a=235, y=0.1, delay=delay) for i, a in enumerate(angles)]


def build():
    E = []
    # 通常攻撃: 星砲の砲弾
    E.append(make(P + "atk_cast", ranged_muzzle(S, 1.1) + [star_flash(2.0, 10, z=-0.7), cannon_smoke(2)], 24))
    E.append(make(P + "atk_travel", projectile(S, "orb", 1.0) + [Node("shell", tex="Fx_Star", life=600, rot=Rot.pva(0, (0, 0, 420)), scale=Scl.fixed(1.2), color=Col.fixed(*S.accent, 230)),
                                                              Node("starfall", tex="Fx_Star", life=(10, 16), count="inf", interval=(4, 6), detach=True, gen=Gen.sphere(0.3, rx=(-90, 90), ry=(-180, 180), rotate=False),
                                                                   scale=Scl.ease(0.5, 0.05), color=fade(S.main, 220))], 40, loop=True))
    E.append(make(P + "atk_hit", hit_burst(S, 0.95, extra=[star_flash(1.8, 10, z=0.0, y=0.1), star_scatter(4, 0.5), ground_pulse(S.main, 0.3, 1.7, 14, y=-0.7)]), 28))
    # S1 連射する砲弾: 三連の砲火が前へ走る
    E.append(make(P + "s1_cast", shell_rays((0,), 3.8, 10, z=-1.9) + shell_rays((-12, 12), 3.2, 10, z=-1.6, delay=3) + shell_rays((0, -18, 18), 3.0, 10, z=-1.5, delay=6, c=S.accent)
                  + [glow_core("flare", S.core, 1.9, 9, z=-0.5), star_flash(2.4, 11, z=-0.9, y=0.1), star_flash(2.0, 10, z=-0.9, y=0.1, delay=3, c=S.main), star_flash(2.0, 10, z=-0.9, y=0.1, delay=6),
                     ground_pulse(S.main, 0.3, 2.0, 14, y=-0.85), cannon_smoke(3), flecks(S.accent, n=6, speed=(2, 5), size=0.2, y=0.1, c2=S.main, gravity=-2, spread=0.5)], 30))
    E.append(make(P + "s1_travel", projectile(S, "orb", 1.2) + [Node("shell", tex="Fx_Star", life=600, rot=Rot.pva(0, (0, 0, 540)), scale=Scl.fixed(1.5), color=Col.fixed(*S.core, 235))], 40, loop=True))
    E.append(make(P + "s1_impact", hit_burst(S, 1.2, extra=[star_flash(3.0, 12, z=0.0, y=0.1), star_flash(2.2, 12, z=0.0, y=0.1, delay=3, c=S.main), ground_pulse(S.accent, 0.3, 2.6, 16, y=-0.8), star_scatter(8, 0.7)]), 32))
    E.append(make(P + "s1_hit", hit_burst(S, 0.9, extra=[star_flash(1.6, 9, z=0.0, y=0.1), star_scatter(3, 0.45)]), 26))
    # S2 反動の射撃: 砲口から前へ大きな閃光、術者は反動で後ろへ下がる（背後へ流れる線 + 煙）
    E.append(make(P + "s2_cast", [speed_lines(S.main, 12, 3.4, behind=-0.2), glow_core("flare", S.core, 2.4, 10, z=-0.8), star_flash(3.0, 11, z=-1.0, y=0.1), flat_streak("blast", S.core, 4.4, 0.6, 10, z=-2.2, a=240),
                                  under(S.main, 3.0, 14, z=0.2), cannon_smoke(4, z=0.3, size=(0.7, 1.8)), ground_pulse(S.accent, 0.3, 2.2, 14, y=-0.85), flecks(S.accent, n=8, speed=(2, 6), size=0.2, y=0.1, c2=S.main, gravity=-2)], 30))
    E.append(make(P + "s2_impact", [glow_core("flare", S.core, 2.6, 10), Node("star", tex="Fx_Star", life=14, scale=Scl.ease(1.0, 3.4, "out"), color=fade(S.accent)),
                                    star_flash(3.0, 12, z=0.0, y=0.1, spin=120), ground_pulse(S.core, 0.3, 2.6, 16, y=-0.85, a=255), ground_pulse(S.main, 0.3, 3.0, 20, y=-0.85, delay=3),
                                    under(S.main, 3.8, 16), burst_lines(S.core, n=10, length=1.0), star_scatter(6, 0.6, delay=2), rise("Fx_Glow", S.accent, n=10, radius=1.0, life=(20, 34), size=0.26, delay=2, y=-0.5)], 36))
    E.append(make(P + "s2_hit", hit_burst(S, 0.85, extra=[star_flash(1.5, 9, z=0.0, y=0.1)]), 24))
    # ULT 星砕の大砲: 砲を構えて星の力を溜める → 長い貫通ビーム
    E.append(make(P + "ult_cast", [decal(S.accent, 6.0, 52, y=-0.85, spin=70, a=230), decal(S.main, 4.0, 52, y=-0.84, tex="Fx_Hex", spin=-90, a=190), ground_ring(S.core, 0.4, 4.0, 20, y=-0.85, alpha=255),
                                   ground_ring(S.main, 0.4, 4.6, 26, y=-0.85, delay=8), glow_core("charge", S.core, 3.6, 22, z=-1.2, grow=(0.2, 1.0)), star_flash(5.0, 20, z=-1.2, spin=200),
                                   under(S.main, 4.4, 24, z=-1.2), flat_streak("beam", S.core, 9.0, 1.4, 16, z=-5.0, delay=14, a=240), flat_streak("beamB", S.main, 9.0, 2.6, 18, z=-5.0, delay=14, a=150),
                                   pillar(S.accent, 1.0, 4.6, 22, y=0.0), cannon_smoke(5, z=-0.8, size=(0.8, 2.0), delay=14, life=(20, 30)),
                                   rise("Fx_Glow", S.accent, n=14, radius=1.0, life=(24, 40), size=0.26, y=-0.9)], 56))
    E.append(make(P + "ult_travel", projectile(S, "orb", 2.4) + [Node("beam", tex="Fx_Beam", life=600, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.fixed(0, 0, 3.4), scale=Scl.fixed(8.8, 1.8, 1), color=Col.fixed(*S.main, 160)),
                                                                Node("beamcore", tex="Fx_Beam", life=600, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.fixed(0, 0, 3.0), scale=Scl.fixed(7.6, 0.8, 1), color=Col.fixed(*S.core, 210)),
                                                                Node("star", tex="Fx_Star", life=600, rot=Rot.pva(0, (0, 0, 300)), scale=Scl.fixed(3.6), color=Col.fixed(*S.accent, 200)),
                                                                Node("ring", tex="Fx_Wheel", life=600, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 360)), scale=Scl.fixed(2.6), color=Col.fixed(*S.core, 150))], 60, loop=True))
    E.append(make(P + "ult_impact", [glow_core("flare", S.core, 4.6, 12), Node("star", tex="Fx_Star", life=16, scale=Scl.ease(1.8, 6.4, "out"), color=fade(S.accent)),
                                     star_flash(5.6, 14, z=0.0, y=0.1, spin=160), star_flash(4.2, 14, z=0.0, y=0.1, delay=3, c=S.main), ground_pulse(S.core, 0.4, 3.6, 16, y=-0.7, a=255),
                                     ground_pulse(S.main, 0.4, 4.4, 22, y=-0.7, delay=4), ground_pulse(S.accent, 0.4, 5.0, 26, y=-0.7, delay=7), decal(S.accent, 6.4, 46, y=-0.84, spin=-60, a=210),
                                     under(S.main, 5.4, 18), spark_lines(S.core, n=14, speed=(5, 12), life=(9, 15), length=1.2, y=0), star_scatter(14, 0.9, speed=(3, 8), life=(18, 32)),
                                     sparks(S.accent, n=12, speed=(2, 6), life=(16, 28), size=0.3, gravity=-5, y=0, c2=S.main)], 48))
    E.append(make(P + "ult_hit", hit_burst(S, 1.1, extra=[star_flash(2.2, 12, z=0.0, y=0.1), star_scatter(5, 0.5)]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
