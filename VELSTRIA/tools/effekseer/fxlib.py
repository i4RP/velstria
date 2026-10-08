"""効果の部品（閃光・衝撃波・火花・魔法陣・軌跡…）。ヒーローごとに色（Palette）と数値を変えて組み合わせる。

単位: 長さ m / 時間 フレーム(60fps) / 速度 m/s。効果は「前 = -Z」へ作る。
色は (R, G, B) 0..255。alpha は部品が決める。
"""
from efkgen import Col, Gen, Loc, Node, Ring, Rot, Scl, Effect


class Palette:
    def __init__(self, core, main, accent, dark=None):
        self.core, self.main, self.accent = core, main, accent
        self.dark = dark or tuple(int(c * 0.35) for c in main)


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def fade(c, a0=255, a1=0, curve="in"):
    """色 c を a0 → a1 のアルファで消す。"""
    return Col.ease(rgba(c, a0), rgba(c, a1), curve)


def morph(c0, c1, a0=255, a1=0, curve="in"):
    return Col.ease(rgba(c0, a0), rgba(c1, a1), curve)


# --- 単発の部品 -----------------------------------------------------------------------------

def flare(c, size=2.0, life=10, y=0.9, delay=0, tex="Fx_Core", grow="out", start=0.3):
    """中心の閃光。"""
    return Node("flare", tex=tex, life=life, delay=delay, loc=Loc.fixed(0, y, 0), scale=Scl.ease(size * start, size, grow), color=morph(c, c, 255, 0))


def star(c, size=2.4, life=12, y=0.9, delay=0, spin=0):
    """十字の光芒。"""
    return Node("star", tex="Fx_Star", life=life, delay=delay, loc=Loc.fixed(0, y, 0),
                scale=Scl.ease(size * 0.4, size, "out"), rot=Rot.pva(0, (0, 0, spin)) if spin else None, color=fade(c))


def ground_ring(c, r0=0.4, r1=3.0, life=18, y=0.06, delay=0, tex="Fx_Ring", curve="out", alpha=230):
    """地面に広がる輪（半径 r0→r1 m）。"""
    return Node("ground_ring", tex=tex, life=life, delay=delay, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(0, y, 0),
                scale=Scl.ease(r0 * 2, r1 * 2, curve), color=fade(c, alpha))


def ring_wave(c, r0=0.3, r1=2.0, life=16, y=0.9, delay=0, tilt=0):
    """立った（ビルボード）衝撃波の輪。"""
    return Node("ring_wave", tex="Fx_RingSoft", life=life, delay=delay, loc=Loc.fixed(0, y, 0),
                scale=Scl.ease(r0 * 2, r1 * 2, "out"), color=fade(c, 220))


def rune(c, size=3.0, life=40, y=0.05, delay=0, spin=40, grow=True, fade_in=4, alpha=230):
    """地面の魔法陣（回りながら現れて消える）。"""
    return Node("rune", tex="Fx_Rune", life=life, delay=delay, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, spin)) if False else Rot.fixed(90, 0, 0),
                loc=Loc.fixed(0, y, 0), scale=Scl.ease(size * (0.55 if grow else 1) , size, "out"),
                color=Col.ease(rgba(c, alpha), rgba(c, 0), "in"), fade_in=fade_in)


def sparks(c, n=16, speed=(2.5, 6.0), life=(16, 28), size=0.35, delay=0, spread=1.0, gravity=-6.0, y=0.9, c2=None, tex="Fx_Glow"):
    """放射状に飛び散る火花。spread=1 で全方位、0.3 で上向きの円錐。"""
    r = 90 * spread
    return Node("sparks", tex=tex, life=life, count=n, delay=delay, gen=Gen.sphere(0.05, rx=(-r, r), ry=(-180, 180)),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, speed[0], 0), (0, speed[1], 0)), acc=(0, gravity, 0) if gravity else 0),
                scale=Scl.ease(size, size * 0.15), color=morph(c, c2 or c, 255, 0))


def spark_lines(c, n=10, speed=(4, 9), life=(8, 14), length=0.9, y=0.9, delay=0):
    """短い線状の飛び散り（ヒットの斬撃感）。"""
    return Node("spark_lines", tex="Fx_Streak", life=life, count=n, delay=delay, billboard="directional",
                gen=Gen.sphere(0.05, rx=(-80, 80), ry=(-180, 180)), loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, speed[0], 0), (0, speed[1], 0))),
                scale=Scl.ease((length, 0.12, 1), (length * 1.4, 0.04, 1)), color=fade(c))


def glow_pillar(c, w=1.0, h=4.0, life=18, delay=0, tex="Fx_Streak"):
    """立ち昇る光柱（縦に伸びる）。"""
    return Node("pillar", tex=tex, life=life, delay=delay, billboard="yfixed", loc=Loc.fixed(0, h * 0.5, 0),
                rot=Rot.fixed(0, 0, 90), scale=Scl.ease((w * 0.4, h * 0.6, 1), (w, h, 1), "out"), color=fade(c, 230))


def motes(c, n=12, radius=1.2, life=(30, 50), size=0.22, rise=1.0, delay=0, y=0.2, tex="Fx_Glow"):
    """漂って昇る光の粒（余韻）。"""
    return Node("motes", tex=tex, life=life, count=n, interval=(2, 4), delay=delay, gen=Gen.circle(radius, rotate=False),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, rise * 0.6, 0), (0, rise * 1.4, 0))),
                scale=Scl.ease(size, size * 0.2), color=fade(c, 220))


def orbit(c, tex="Fx_Wheel", n=2, radius=0.9, life=300, spin=360, size=0.7, y=1.0, flat=True, blend="add", loop=False):
    """術者の周りを回る物（光輪など）。n 個を等間隔に置き、全体を回す。親ノード 1 つ + 子 n 個。"""
    parent = Node("orbit", tex="Fx_Glow", life=life, count=1 if not loop else "inf", loc=Loc.fixed(0, y, 0),
                  rot=Rot.pva(0, (0, spin, 0)), scale=Scl.fixed(0.01), color=fade(c, 0, 0, "lin"))
    for i in range(n):
        a = 360.0 * i / n
        import math
        px, pz = math.sin(math.radians(a)) * radius, -math.cos(math.radians(a)) * radius
        parent.add(Node(f"orbiter{i}", tex=tex, blend=blend, life=life, loc=Loc.fixed(px, 0, pz), billboard="fixed" if flat else "billboard",
                        rot=Rot.pva((90, 0, 0), (0, 0, 720)) if flat else None, scale=Scl.fixed(size), color=fade(c, 255, 255, "lin"), fade_out=8))
    return parent


def speed_lines(c, n=14, length=3.0, life=(8, 14), radius=1.0, delay=0, y=0.6):
    """進行方向と逆（後ろ +Z）へ流れる線（疾走感）。"""
    return Node("speed_lines", tex="Fx_Streak", life=life, count=n, interval=(0, 1), delay=delay, billboard="fixed",
                gen=Gen.circle(radius, rotate=False), rot=Rot.fixed(90, 90, 0),
                loc=Loc.pva(pos=((0, y, 0), (0, y + 1.0, 0)), vel=((0, 0, 8), (0, 0, 14))), scale=Scl.ease((length, 0.1, 1), (length * 0.4, 0.03, 1)), color=fade(c, 200))


def trail_emitter(c, rate=2, life=(12, 22), size=0.4, y=0.0, tex="Fx_Glow", n="inf"):
    """動く効果が通った跡に残る粒（効果ごとゲームが動かす前提。親に縛らない）。"""
    return Node("trail", tex=tex, life=life, count=n, interval=(rate, rate + 1), detach=True, loc=Loc.fixed(0, y, 0),
                scale=Scl.ease(size, size * 0.1), color=fade(c, 200))


def under_glow(c, size=2.0, life=14, y=0.9, delay=0, a=150, grow=(0.5, 1.0), loop=False):
    """明るい地面でも読めるよう、加算の光の下に敷く彩度の高い下地（通常合成の暗めの光）。"""
    dark = tuple(int(v * 0.55) for v in c)
    return Node("under", tex="Fx_Glow", blend="normal", life=600 if loop else life, delay=delay, loc=Loc.fixed(0, y, 0),
                scale=Scl.fixed(size) if loop else Scl.ease(size * grow[0], size * grow[1], "out"),
                color=Col.fixed(*dark, a) if loop else Col.ease(rgba(dark, a), rgba(dark, 0), "in"))
