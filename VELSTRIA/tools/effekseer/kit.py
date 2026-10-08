"""ヒーロー別の効果を組み立てる共通の型（fxlib の部品の上）。

Style(core, main, accent) = 色。各 builder は Node のリスト（または Node）を返す。長さ m・時間フレーム・速度 m/s。
効果は前 = -Z。地面に平らな板は `flat=True`（回転 (90,90+yaw,0)）。
"""
import math
from fxlib import *  # noqa: F401,F403
from efkgen import Col, Gen, Loc, Node, Ring, Rot, Scl, Effect


class Style:
    def __init__(self, core, main, accent, dark=None):
        self.core, self.main, self.accent = core, main, accent
        self.dark = dark or tuple(int(v * 0.5) for v in main)


def flat_streak(name, c, length, width, life, z=-0.4, yaw=0, y=0.0, delay=0, a=230, tex="Fx_Streak", stretch=True, x=0.0):
    return Node(name, tex=tex, life=life, delay=delay, billboard="fixed", rot=Rot.fixed(90, 90 + yaw, 0), loc=Loc.fixed(x, y, z),
                scale=Scl.ease((length * 0.5, width, 1), (length, width * 0.6, 1), "out") if stretch else Scl.fixed(length, width, 1), color=fade(c, a))


def spin_flat(name, c, size0, size1, life, y=0.0, spin=720, delay=0, a=255, x=0.0, z=0.0, tex="Fx_Wheel", curve="out", blend="add", fade_in=0):
    """地面と平行に回る板（光輪・魔法陣・渦）。"""
    return Node(name, tex=tex, blend=blend, life=life, delay=delay, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, spin)),
                loc=Loc.fixed(x, y, z), scale=Scl.ease(size0, size1, curve), color=fade(c, a), fade_in=fade_in)


def arc_slash(name, c, radius, life, sweep=(-70, 70), y=0.0, z=0.0, delay=0, width=0.5, tilt=0, a=240, x=0.0):
    """前方へ弧を描く斬撃（Ring の欠けた輪）。sweep = 開始・終了角（度）。"""
    return Node(name, tex="Fx_Streak", kind="ring", life=life, delay=delay, billboard="fixed", rot=Rot.fixed(90 + tilt, 90, 0), loc=Loc.fixed(x, y, z),
                ring=Ring(outer=radius, inner=max(0.0, radius - width), outer_end=radius * 1.12, inner_end=max(0.0, radius * 1.12 - width * 0.5),
                          vertices=28, angle=sweep, curve="out"), color=fade(c, a))


def crescent(name, c, size, life, y=0.0, z=-0.8, delay=0, yaw=0, spin=0, a=240, x=0.0, flat=True, grow=(0.6, 1.0)):
    """三日月の斬撃板（Fx_Crescent）。前へ開く。"""
    return Node(name, tex="Fx_Crescent", life=life, delay=delay, billboard="fixed" if flat else "billboard",
                rot=Rot.fixed(90, 90 + yaw, 0) if flat else None, loc=Loc.fixed(x, y, z), scale=Scl.ease(size * grow[0], size * grow[1], "out"), color=fade(c, a))


def glow_core(name, c, size, life, y=0.0, z=0.0, delay=0, a=255, grow=(0.4, 1.0), tex="Fx_Core", x=0.0):
    return Node(name, tex=tex, life=life, delay=delay, loc=Loc.fixed(x, y, z), scale=Scl.ease(size * grow[0], size * grow[1], "out"), color=fade(c, a))


def under(c, size, life=14, y=0.0, z=0.0, delay=0, a=140):
    """明るい地面で読める下地（通常合成の暗めの光）。"""
    d = tuple(int(v * 0.5) for v in c)
    return Node("under", tex="Fx_Glow", blend="normal", life=life, delay=delay, loc=Loc.fixed(0, y, z), scale=Scl.ease(size * 0.6, size, "out"), color=Col.ease(rgba(d, a), rgba(d, 0), "in"))


def ground_pulse(c, r0, r1, life=18, y=-0.85, delay=0, a=240, tex="Fx_Ring"):
    return Node("pulse", tex=tex, life=life, delay=delay, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(0, y, 0), scale=Scl.ease(r0 * 2, r1 * 2, "out"), color=fade(c, a))


def decal(c, size, life=50, y=-0.84, delay=0, spin=0, a=220, tex="Fx_Rune", grow=0.6, fade_in=4, z=0.0, x=0.0):
    """地面の紋様（魔法陣・亀裂）。spin = 度/秒。"""
    rot = Rot.pva((90, 0, 0), (0, 0, spin)) if spin else Rot.fixed(90, 0, 0)
    return Node("decal", tex=tex, life=life, delay=delay, billboard="fixed", rot=rot, loc=Loc.fixed(x, y, z),
                scale=Scl.ease(size * grow, size, "out"), color=Col.ease(rgba(c, a), rgba(c, 0), "in"), fade_in=fade_in)


def burst_lines(c, n=10, speed=(4, 10), life=(8, 13), length=1.0, y=0.0, delay=0, tex="Fx_Streak"):
    return Node("lines", tex=tex, life=life, count=n, delay=delay, billboard="directional", gen=Gen.sphere(0.05, rx=(-80, 80), ry=(-180, 180)),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, speed[0], 0), (0, speed[1], 0))),
                scale=Scl.ease((length, 0.13, 1), (length * 1.4, 0.04, 1)), color=fade(c))


def flecks(c, n=10, speed=(1.5, 5), life=(14, 26), size=0.26, y=0.0, delay=0, gravity=-5, c2=None, tex="Fx_Glow", spread=1.0):
    r = 90 * spread
    return Node("flecks", tex=tex, life=life, count=n, delay=delay, gen=Gen.sphere(0.05, rx=(-r, r), ry=(-180, 180)),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, speed[0], 0), (0, speed[1], 0)), acc=(0, gravity, 0) if gravity else 0),
                scale=Scl.ease(size, size * 0.15), color=morph(c, c2 or c, 255, 0))


def scatter(tex, c, n=10, speed=(2, 5), life=(18, 30), size=0.5, y=0.0, delay=0, gravity=-3, spin=240, c2=None, spread=0.8):
    """絵のある粒（蝶・花びら・破片…）が回りながら散る。"""
    r = 90 * spread
    return Node("scatter", tex=tex, life=life, count=n, delay=delay, billboard="billboard", gen=Gen.sphere(0.05, rx=(-r, r), ry=(-180, 180)),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, speed[0], 0), (0, speed[1], 0)), acc=(0, gravity, 0) if gravity else 0),
                rot=Rot.pva(0, ((0, 0, -spin), (0, 0, spin))), scale=Scl.ease(size, size * 0.4), color=morph(c, c2 or c, 255, 0))


def rise(tex, c, n=10, radius=1.2, life=(30, 50), size=0.3, speed=(0.8, 2.0), y=-0.8, delay=0, interval=(2, 4), spin=0, count=None):
    """足もとから立ち昇る粒（余韻・オーラ）。count="inf" で続ける。"""
    return Node("rise", tex=tex, life=life, count=count or n, interval=interval, delay=delay, billboard="billboard", gen=Gen.circle(radius, rotate=False),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, speed[0], 0), (0, speed[1], 0))),
                rot=Rot.pva(0, ((0, 0, -spin), (0, 0, spin))) if spin else None, scale=Scl.ease(size, size * 0.2), color=fade(c, 230))


def pillar(c, w, h, life=20, delay=0, y=0.0, tex="Fx_Beam", a=235):
    """縦に伸びる光柱（常にこちらを向く縦長の板）。"""
    return Node("pillar", tex=tex, life=life, delay=delay, billboard="yfixed", rot=Rot.fixed(0, 0, 90), loc=Loc.fixed(0, y + h * 0.5, 0),
                scale=Scl.ease((w * 0.3, h * 0.5, 1), (w, h, 1), "out"), color=fade(c, a))


def speed_lines(c, n=14, length=3.0, life=(9, 14), radius=0.7, delay=0, y=0.0, behind=0.4):
    """後ろ（+Z）へ流れる線。疾走・ダッシュ。"""
    return Node("speed_lines", tex="Fx_Streak", life=life, count=n, interval=(0, 1), delay=delay, billboard="fixed", rot=Rot.fixed(90, 90, 0),
                gen=Gen.circle(radius, rotate=False), loc=Loc.pva(pos=((0, y - 0.5, behind), (0, y + 0.6, behind)), vel=((0, 0, 7), (0, 0, 13))),
                scale=Scl.ease((length, 0.14, 1), (length * 0.45, 0.04, 1)), color=fade(c, 220))


def flight(name, c, tex, size, life, dist, y=0.0, delay=0, a=255, flat=True, spin=0, aspect=1.0, z0=-0.5):
    """発動の瞬間に前方へ飛ぶ物（投擲・斬撃の飛翔）。dist m を life フレームで進む。"""
    rot = Rot.fixed(90, 90, 0) if flat else None
    if spin:
        rot = Rot.pva((90, 0, 0), (0, 0, spin)) if flat else Rot.pva(0, (0, 0, spin))
    return Node(name, tex=tex, life=life, delay=delay, billboard="fixed" if flat else "billboard", rot=rot,
                loc=Loc.ease((0, y, z0), (0, y, z0 - dist), "out"), scale=Scl.fixed(size * aspect, size, 1), color=fade(c, a))


def trail_dust(c, tex="Fx_Glow", size=0.5, life=(10, 16), interval=1, a=200, c2=None):
    """飛翔体の通った跡（親ノードに縛らない粒）。"""
    return Node("trail", tex=tex, life=life, count="inf", interval=interval, detach=True, scale=Scl.ease(size, size * 0.12), color=morph(c, c2 or c, a, 0))


def trail_ghost(c, tex, size0, size1, life=14, interval=2, spin=0, flat=True, a=160, c2=None):
    return Node("ghost", tex=tex, life=life, count="inf", interval=interval, detach=True, billboard="fixed" if flat else "billboard",
                rot=Rot.pva((90, 0, 0), (0, 0, spin)) if flat and spin else (Rot.fixed(90, 90, 0) if flat else None),
                scale=Scl.ease(size0, size1, "out"), color=morph(c, c2 or c, a, 0))


# --- ひな型: 通常攻撃・投射物・被弾 -------------------------------------------------------------

def hit_burst(s, size=1.0, motif="star", ring_c=None, y=0.0, fleck=8, extra=None):
    """命中の基本形: 閃光 + 光芒 + 輪 + 線 + 火花。motif で絵を足す。"""
    n = [glow_core("flare", s.core, 2.2 * size, 9, y=y), under(s.main, 2.8 * size, 14, y=y),
         Node("star", tex="Fx_Star", life=14, loc=Loc.fixed(0, y, 0), scale=Scl.ease(1.0 * size, 3.2 * size, "out"), color=fade(s.main)),
         Node("ring", tex="Fx_RingSoft", life=12, loc=Loc.fixed(0, y, 0), scale=Scl.ease(0.6 * size, 2.8 * size, "out"), color=fade(ring_c or s.core, 210)),
         burst_lines(s.main, n=8, length=0.9 * size, y=y), flecks(s.core, n=fleck, y=y, c2=s.accent, size=0.24 * size)]
    if extra:
        n += extra if isinstance(extra, list) else [extra]
    return n


def melee_swing(s, flip=False, size=1.0, motif="crescent"):
    """近接の通常攻撃（打撃の瞬間）: 弧の斬撃 + 風 + 火花。flip = 逆向きの振り。"""
    a0, a1 = (60, -60) if flip else (-60, 60)
    return [crescent("slash", s.core, 3.4 * size, 9, y=0.2, z=-1.6 * size, yaw=0, a=250, flat=True),
            arc_slash("arc", s.main, 2.6 * size, 10, sweep=(a0, a1), y=0.2, z=0.0, width=0.45 * size),
            flat_streak("air", s.accent, 2.2 * size, 0.28, 9, z=-1.0, yaw=-12 if flip else 12, a=200),
            flecks(s.core, n=5, speed=(2, 5), size=0.2, y=0.2, c2=s.main, gravity=-2, spread=0.6)]


def ranged_muzzle(s, size=1.0, tex="Fx_Core"):
    return [glow_core("flare", s.core, 1.5 * size, 8, z=-0.2, tex=tex), under(s.main, 1.8 * size, 10),
            Node("star", tex="Fx_Star", life=10, loc=Loc.fixed(0, 0, -0.3), scale=Scl.ease(0.8 * size, 2.0 * size, "out"), color=fade(s.main)),
            flat_streak("beam", s.core, 2.2 * size, 0.32, 9, z=-1.1), flat_streak("beamL", s.main, 1.4 * size, 0.2, 9, z=-0.8, yaw=14),
            flat_streak("beamR", s.main, 1.4 * size, 0.2, 9, z=-0.8, yaw=-14),
            flecks(s.core, n=5, speed=(2.5, 5.5), size=0.2, life=(10, 16), gravity=0, c2=s.main, spread=0.4)]


def projectile(s, kind="orb", size=1.0):
    """飛翔体（ループ）。kind: orb / arrow / wheel / bolt / seed / shard / blob / spiral / butterfly。"""
    n = []
    if kind == "arrow":
        n += [Node("arrow", tex="Fx_Arrow", life=600, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.fixed(0, 0, -0.1), scale=Scl.fixed(2.1 * size, 0.42 * size, 1), color=Col.fixed(*s.core, 255))]
    elif kind == "wheel":
        n += [spin_flat("wheelA", s.core, 1.8 * size, 1.8 * size, 600, spin=1000), spin_flat("wheelB", s.main, 2.6 * size, 2.6 * size, 600, y=-0.05, spin=-640, a=150)]
    elif kind == "shard":
        n += [Node("shard", tex="Fx_Shard", life=600, billboard="fixed", rot=Rot.fixed(90, 90 + 90, 0), scale=Scl.fixed(0.5 * size, 1.5 * size, 1), color=Col.fixed(*s.core, 255))]
    elif kind == "blob":
        n += [Node("blob", tex="Fx_Blob", blend="normal", life=600, scale=Scl.fixed(1.0 * size), color=Col.fixed(*s.main, 235)),
              Node("spec", tex="Fx_Core", life=600, loc=Loc.fixed(-0.1, 0.1, 0), scale=Scl.fixed(0.4 * size), color=Col.fixed(255, 255, 255, 200))]
    elif kind == "spiral":
        n += [spin_flat("spiral", s.main, 2.0 * size, 2.0 * size, 600, tex="Fx_Spiral", spin=700), spin_flat("spiral2", s.accent, 3.0 * size, 3.0 * size, 600, tex="Fx_Spiral", spin=-420, a=150)]
    elif kind == "butterfly":
        n += [Node("bf", tex="Fx_Butterfly", life=600, billboard="billboard", rot=Rot.pva(0, (0, 0, 0)), scale=Scl.fixed(1.2 * size), color=Col.fixed(*s.main, 255))]
    elif kind == "seed":
        n += [Node("seed", tex="Fx_Petal", life=600, billboard="fixed", rot=Rot.pva((90, 90, 0), (0, 0, 480)), scale=Scl.fixed(1.1 * size, 0.7 * size, 1), color=Col.fixed(*s.main, 255))]
    elif kind == "bolt":
        n += [Node("bolt", tex="Fx_Bolt", life=600, billboard="billboard", scale=Scl.fixed(0.6 * size, 2.2 * size, 1), color=Col.fixed(*s.core, 255))]
    n += [Node("core", tex="Fx_Core", life=600, scale=Scl.fixed(0.75 * size), color=Col.fixed(*s.core, 255)),
          Node("halo", tex="Fx_Glow", life=600, scale=Scl.fixed(1.9 * size), color=Col.fixed(*s.main, 130)),
          Node("under", tex="Fx_Glow", blend="normal", life=600, scale=Scl.fixed(2.1 * size), color=Col.fixed(*s.dark, 90)),
          trail_dust(s.main, size=0.5 * size, c2=s.accent),
          Node("glint", tex="Fx_Star", life=(12, 20), count="inf", interval=(3, 5), detach=True, gen=Gen.sphere(0.25, rx=(-90, 90), ry=(-180, 180), rotate=False),
               scale=Scl.ease(0.55 * size, 0.05), color=fade(s.core, 230))]
    return n


def make(name, nodes, frames=40, loop=False):
    fx = Effect(name, frames=frames, loop=loop)
    for n in nodes:
        fx.add(*n) if isinstance(n, (list, tuple)) else fx.add(n)
    return fx


def build_set(effects):
    import os
    for fx in effects:
        print(os.path.basename(fx.build()))
