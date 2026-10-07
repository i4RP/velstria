"""H003 月弓のフィリエル（Karrie 型: 光輪・ライトホイールマーク）の効果。月白 + 淡い金 + 月光の青。

段: atk_cast / atk_travel / atk_hit / s1_cast / s1_travel / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit /
    ult_cast / ult_travel / ult_impact / ult_hit
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from fxlib import *  # noqa: E402

CORE = (255, 250, 235)   # 白金
GOLD = (255, 214, 120)   # 金
MOON = (170, 205, 255)   # 月光の青
VIOLET = (150, 130, 255)  # 差し色


def flat_streak(name, c, length, width, life, z=-0.4, yaw=0, y=0.0, delay=0, a=230, tex="Fx_Streak", stretch=True):
    """地面と平行に前（-Z）へ伸びる光の筋。yaw 度だけ左右へ振る。"""
    return Node(name, tex=tex, life=life, delay=delay, billboard="fixed", rot=Rot.fixed(90, 90 + yaw, 0), loc=Loc.fixed(0, y, z),
                scale=Scl.ease((length * 0.5, width, 1), (length, width * 0.6, 1), "out") if stretch else Scl.fixed(length, width, 1),
                color=fade(c, a))


def wheel(name, c, size0, size1, life, y=0.9, spin=720, delay=0, a=255, x=0.0, z=0.0, tex="Fx_Wheel", curve="out", blend="add", fade_in=0):
    """地面と平行に回る光輪。"""
    return Node(name, tex=tex, blend=blend, life=life, delay=delay, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, spin)),
                loc=Loc.fixed(x, y, z), scale=Scl.ease(size0, size1, curve), color=fade(c, a), fade_in=fade_in)


# ---- 通常攻撃（弓） -------------------------------------------------------------------------

def atk_cast():
    fx = Effect("H003_atk_cast", frames=24)
    fx.add(Node("flare", tex="Fx_Core", life=8, loc=Loc.fixed(0, 0, -0.2), scale=Scl.ease(0.5, 1.4, "out"), color=fade(CORE)),
           Node("star", tex="Fx_Star", life=10, loc=Loc.fixed(0, 0, -0.3), scale=Scl.ease(0.8, 2.0, "out"), color=fade(GOLD)),
           flat_streak("beam", CORE, 2.2, 0.34, 9, z=-1.1),
           flat_streak("beamL", GOLD, 1.4, 0.2, 9, z=-0.8, yaw=14),
           flat_streak("beamR", GOLD, 1.4, 0.2, 9, z=-0.8, yaw=-14),
           Node("glints", tex="Fx_Glow", life=(10, 16), count=6, gen=Gen.sphere(0.05, rx=(-30, 30), ry=(-25, 25)),
                loc=Loc.pva(vel=((0, 2.5, 0), (0, 5.5, 0))), scale=Scl.ease(0.22, 0.04), color=morph(CORE, GOLD)))
    return fx


def atk_travel():
    fx = Effect("H003_atk_travel", frames=40, loop=True)
    fx.add(Node("arrow", tex="Fx_Arrow", life=600, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.fixed(0, 0, -0.1),
                scale=Scl.fixed(2.1, 0.42, 1), color=Col.fixed(255, 248, 225, 255)),
           Node("core", tex="Fx_Core", life=600, scale=Scl.fixed(0.75), color=Col.fixed(255, 240, 200, 255)),
           Node("halo", tex="Fx_Glow", life=600, scale=Scl.fixed(1.7), color=Col.fixed(255, 214, 120, 120)),
           Node("tail", tex="Fx_Glow", life=(10, 16), count="inf", interval=1, detach=True, scale=Scl.ease(0.5, 0.06), color=morph(GOLD, MOON, 200, 0)),
           Node("glint", tex="Fx_Star", life=(12, 20), count="inf", interval=(3, 5), detach=True, gen=Gen.sphere(0.25, rx=(-90, 90), ry=(-180, 180), rotate=False),
                scale=Scl.ease(0.55, 0.05), color=fade(CORE, 230)))
    return fx


def atk_hit():
    fx = Effect("H003_atk_hit", frames=30)
    fx.add(Node("flare", tex="Fx_Core", life=9, loc=Loc.fixed(0, 0.1, 0), scale=Scl.ease(0.8, 2.4, "out"), color=fade(CORE)),
           Node("star", tex="Fx_Star", life=14, loc=Loc.fixed(0, 0.1, 0), scale=Scl.ease(1.0, 3.2, "out"), color=fade(GOLD)),
           ground_ring(MOON, 0.3, 1.8, 14, y=-0.7),
           Node("ring", tex="Fx_RingSoft", life=12, loc=Loc.fixed(0, 0.1, 0), scale=Scl.ease(0.6, 2.6, "out"), color=fade(CORE, 200)),
           spark_lines(GOLD, n=8, speed=(4, 9), life=(8, 13), length=0.9, y=0.1),
           sparks(CORE, n=8, speed=(1.5, 4.5), life=(14, 24), size=0.24, gravity=-5, y=0.1, c2=GOLD))
    return fx


# ---- S1 スピニング光輪 ---------------------------------------------------------------------

def s1_cast():
    fx = Effect("H003_s1_cast", frames=34)
    fx.add(rune(GOLD, 3.0, 28, y=-0.85, alpha=200),
           wheel("wheel", CORE, 0.4, 1.7, 16, y=0.0, z=-1.2, spin=900),
           Node("flare", tex="Fx_Core", life=10, loc=Loc.fixed(0, 0, -0.9), scale=Scl.ease(0.5, 1.8, "out"), color=fade(CORE)),
           ground_ring(MOON, 0.5, 2.2, 18, y=-0.85),
           flat_streak("beam", GOLD, 2.6, 0.3, 10, z=-1.4))
    return fx


def s1_travel():
    fx = Effect("H003_s1_travel", frames=60, loop=True)
    fx.add(wheel("wheelA", CORE, 1.8, 1.8, 600, y=0.0, spin=1000),
           wheel("wheelB", GOLD, 2.6, 2.6, 600, y=-0.05, spin=-640, a=150),
           Node("halo", tex="Fx_Glow", life=600, scale=Scl.fixed(3.2), color=Col.fixed(255, 214, 120, 110)),
           Node("ghost", tex="Fx_Wheel", life=14, count="inf", interval=2, detach=True, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 600)),
                scale=Scl.ease(1.7, 1.1, "out"), color=morph(GOLD, MOON, 170, 0)),
           Node("dust", tex="Fx_Glow", life=(14, 24), count="inf", interval=1, detach=True, gen=Gen.circle(0.5, rotate=False),
                loc=Loc.pva(vel=((0, 0.3, 0), (0, 1.2, 0))), scale=Scl.ease(0.34, 0.05), color=morph(CORE, GOLD, 220, 0)))
    return fx


def s1_impact():
    fx = Effect("H003_s1_impact", frames=90)
    fx.add(rune(MOON, 6.2, 80, y=-0.85, alpha=210),
           ground_ring(CORE, 0.3, 3.4, 16, y=-0.85, alpha=255),
           ground_ring(GOLD, 0.3, 3.4, 18, y=-0.85, delay=14),
           ground_ring(MOON, 0.3, 3.4, 20, y=-0.85, delay=28),
           wheel("wheel", CORE, 1.3, 1.9, 76, y=0.0, spin=1100, a=240),
           Node("flare", tex="Fx_Core", life=12, scale=Scl.ease(0.8, 2.8, "out"), color=fade(CORE)),
           Node("haze", tex="Fx_Glow", life=76, scale=Scl.fixed(4.6), color=Col.ease(rgba(GOLD, 70), rgba(GOLD, 0), "in")),
           motes(GOLD, n=18, radius=2.6, life=(40, 66), size=0.28, rise=1.1, y=-0.8))
    return fx


def s1_hit():
    fx = Effect("H003_s1_hit", frames=26)
    fx.add(Node("star", tex="Fx_Star", life=12, scale=Scl.ease(0.7, 2.2, "out"), color=fade(MOON)),
           Node("ring", tex="Fx_RingSoft", life=14, scale=Scl.ease(0.5, 2.1, "out"), color=fade(CORE, 220)),
           wheel("mini", GOLD, 0.2, 0.9, 20, y=0.0, spin=900),
           sparks(CORE, n=6, speed=(1.5, 3.5), life=(14, 22), size=0.2, gravity=-3, y=0, c2=MOON))
    return fx


# ---- S2 ファントムステップ ---------------------------------------------------------------------

def s2_cast():
    fx = Effect("H003_s2_cast", frames=30)
    fx.add(Node("flare", tex="Fx_Core", life=10, loc=Loc.fixed(0, 0, 0.3), scale=Scl.ease(0.8, 2.6, "out"), color=fade(CORE)),
           ground_ring(MOON, 0.3, 2.2, 14, y=-0.85),
           # 後ろ（+Z）へ流れる速度線
           Node("lines", tex="Fx_Streak", life=(9, 14), count=14, interval=(0, 1), billboard="fixed", rot=Rot.fixed(90, 90, 0),
                gen=Gen.circle(0.7, rotate=False), loc=Loc.pva(pos=((0, -0.6, 0.4), (0, 0.6, 0.4)), vel=((0, 0, 7), (0, 0, 13))),
                scale=Scl.ease((3.0, 0.14, 1), (1.4, 0.04, 1)), color=fade(GOLD, 220)),
           Node("ghost", tex="Fx_Star", life=14, loc=Loc.fixed(0, 0, 0.4), scale=Scl.ease(1.0, 3.0, "out"), color=fade(MOON, 200)),
           flat_streak("after", CORE, 3.4, 0.5, 12, z=1.6, stretch=False))
    return fx


def s2_impact():
    fx = Effect("H003_s2_impact", frames=34)
    fx.add(wheel("w1", CORE, 0.4, 1.8, 14, y=0.0, x=-0.45, spin=900),
           wheel("w2", GOLD, 0.4, 1.8, 14, y=0.0, x=0.45, spin=-900),
           Node("flare", tex="Fx_Core", life=10, scale=Scl.ease(0.8, 2.4, "out"), color=fade(CORE)),
           Node("star", tex="Fx_Star", life=14, scale=Scl.ease(1.0, 3.4, "out"), color=fade(GOLD)),
           ground_ring(MOON, 0.3, 2.6, 16, y=-0.85),
           spark_lines(CORE, n=10, speed=(4, 10), life=(8, 14), length=1.0, y=0))
    return fx


def s2_hit():
    fx = Effect("H003_s2_hit", frames=24)
    fx.add(Node("star", tex="Fx_Star", life=10, scale=Scl.ease(0.6, 1.8, "out"), color=fade(CORE)),
           Node("ring", tex="Fx_RingSoft", life=12, scale=Scl.ease(0.4, 1.7, "out"), color=fade(GOLD, 220)),
           sparks(GOLD, n=5, speed=(1.5, 3.2), life=(12, 20), size=0.18, gravity=-3, y=0, c2=CORE))
    return fx


# ---- ULT スピーディ光輪（二刀の光輪を纏う。6 秒） ------------------------------------------------

def ult_cast():
    fx = Effect("H003_ult_cast", frames=400, loop=False)
    orbit = Node("orbit", tex="Fx_Glow", life=380, loc=Loc.fixed(0, 0, 0), rot=Rot.pva(0, (0, 380, 0)), scale=Scl.fixed(0.01), color=Col.fixed(255, 255, 255, 0))
    for i, a in enumerate((0, 180)):
        px, pz = math.sin(math.radians(a)) * 1.25, -math.cos(math.radians(a)) * 1.25
        orbit.add(Node(f"w{i}", tex="Fx_Wheel", life=380, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 540)), loc=Loc.fixed(px, 0.0, pz),
                       scale=Scl.fixed(1.35), color=Col.fixed(255, 236, 190, 255), fade_in=10, fade_out=24))
        orbit.add(Node(f"g{i}", tex="Fx_Glow", life=380, loc=Loc.fixed(px, 0.0, pz), scale=Scl.fixed(1.9), color=Col.fixed(255, 214, 120, 120), fade_in=10, fade_out=24))
    fx.add(orbit,
           rune(GOLD, 5.0, 60, y=-0.85, alpha=230),
           ground_ring(CORE, 0.4, 4.2, 20, y=-0.85, alpha=255),
           ground_ring(MOON, 0.4, 4.2, 24, y=-0.85, delay=8),
           Node("flare", tex="Fx_Core", life=14, scale=Scl.ease(1.0, 3.6, "out"), color=fade(CORE)),
           Node("pillar", tex="Fx_Streak", life=22, billboard="yfixed", rot=Rot.fixed(0, 0, 90), loc=Loc.fixed(0, 1.2, 0),
                scale=Scl.ease((0.4, 1.0, 1), (1.0, 4.5, 1), "out"), color=fade(GOLD, 230)),
           Node("aura", tex="Fx_Glow", life=380, scale=Scl.fixed(2.6), color=Col.fixed(255, 214, 120, 70), fade_in=12, fade_out=30),
           Node("motes", tex="Fx_Glow", life=(24, 40), count="inf", interval=(2, 3), gen=Gen.circle(0.9, rotate=False), delay=10,
                loc=Loc.pva(pos=((0, -0.9, 0), (0, -0.9, 0)), vel=((0, 0.8, 0), (0, 2.0, 0))), scale=Scl.ease(0.26, 0.04), color=morph(CORE, GOLD, 220, 0)))
    return fx


def ult_travel():
    fx = Effect("H003_ult_travel", frames=60, loop=True)
    fx.add(Node("beam", tex="Fx_Arrow", life=600, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.fixed(0, 0, -0.4), scale=Scl.fixed(4.6, 1.1, 1), color=Col.fixed(255, 248, 225, 255)),
           Node("core", tex="Fx_Core", life=600, scale=Scl.fixed(1.8), color=Col.fixed(255, 240, 200, 255)),
           Node("halo", tex="Fx_Glow", life=600, scale=Scl.fixed(4.2), color=Col.fixed(255, 214, 120, 130)),
           wheel("wheel", GOLD, 2.0, 2.0, 600, y=0.0, spin=900, a=200),
           Node("tail", tex="Fx_Glow", life=(12, 20), count="inf", interval=1, detach=True, scale=Scl.ease(1.0, 0.1), color=morph(GOLD, MOON, 200, 0)),
           Node("ghost", tex="Fx_Wheel", life=16, count="inf", interval=3, detach=True, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 500)),
                scale=Scl.ease(2.0, 1.2, "out"), color=morph(GOLD, MOON, 150, 0)))
    return fx


def ult_impact():
    fx = Effect("H003_ult_impact", frames=40)
    fx.add(Node("flare", tex="Fx_Core", life=12, scale=Scl.ease(1.2, 4.2, "out"), color=fade(CORE)),
           Node("star", tex="Fx_Star", life=16, scale=Scl.ease(1.6, 5.4, "out"), color=fade(GOLD)),
           ground_ring(CORE, 0.4, 3.0, 16, y=-0.7, alpha=255),
           ground_ring(MOON, 0.4, 3.6, 22, y=-0.7, delay=4),
           wheel("w", GOLD, 0.6, 2.8, 16, y=0.0, spin=900),
           spark_lines(CORE, n=14, speed=(5, 12), life=(9, 15), length=1.2, y=0),
           sparks(GOLD, n=12, speed=(2, 6), life=(16, 28), size=0.3, gravity=-5, y=0, c2=MOON))
    return fx


def ult_hit():
    fx = Effect("H003_ult_hit", frames=28)
    fx.add(Node("star", tex="Fx_Star", life=12, scale=Scl.ease(0.9, 2.8, "out"), color=fade(CORE)),
           Node("ring", tex="Fx_RingSoft", life=14, scale=Scl.ease(0.6, 2.4, "out"), color=fade(GOLD, 230)),
           wheel("mini", MOON, 0.3, 1.2, 16, y=0.0, spin=800),
           sparks(CORE, n=6, speed=(2, 4), life=(14, 22), size=0.2, gravity=-3, y=0, c2=GOLD))
    return fx


def build_all():
    for make in (atk_cast, atk_travel, atk_hit, s1_cast, s1_travel, s1_impact, s1_hit, s2_cast, s2_impact, s2_hit,
                 ult_cast, ult_travel, ult_impact, ult_hit):
        fx = make()
        print(os.path.basename(fx.build()))


if __name__ == "__main__":
    build_all()
