"""H029 ボルグ（MLBB: ティグラル）のキットの段に重ねる効果（Effects/Effekseer/Kit/H029_*.efk。FX_H029.swift の FXCue.efk が再生する）。

形の主役（爆炎・S 字の地割れ・四芒星の岩盤・渦の刃・範囲の輪）は SkillFX（Blender の模型とコマ送りのメッシュ）。ここは粒の細部だけ:
飛び散る金の光の筋・火花・白い岩の欠片・きらめき・白い星の閃き。実機の中・高画質では後処理の中で描かれてブルームが掛かり、
シミュレータ・低画質は重ね描き（CI の撮影にも写る。RealityKit の粒子は CI に写らない）。
MLBB の画面収録（2026-10-18、44 秒、1108×512・30fps・62.3 px/m）で見た大きさ・色・時刻（docs/vfx/H029.md）。時間はフレーム（60fps）。
  H029_wave_burst  聖槌波の 2・3 回目の爆ぜ（帯の中心）。白金の芯 → 放射状の金の光の筋（約 3.5 m）・上へ散る火花・きらめき。3D の上
  H029_slam        崩落聖域の崩落（範囲の半径 2.78 m で作る。再生の倍率 = 半径 / 2.78）。範囲を覆う白熱の芯 → 外へ走る金の光の筋 24 本・
                    跳ねて落ちる白い岩の欠片・金の火花・縁のきらめき。3D の上
  H029_dash_hit    聖槌突撃の衝突（被弾者）。白い 4 本の光芒の星（約 2.5 m）と白金の芯。3D の上
効果は前 = -Z。
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from efkgen import Col, Effect, Gen, Loc, Node, Rot, Scl  # noqa: E402
from kit import burst_lines, flecks, glow_core, scatter  # noqa: E402

P = "H029_"
WHITE = (255, 252, 232)
GOLD = (255, 214, 92)
HOT = (255, 238, 140)
ORANGE = (255, 146, 48)
ROCK = (236, 230, 218)


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def fade(c, a0=255, a1=0, curve="in"):
    return Col.ease(rgba(c, a0), rgba(c, a1), curve)


def morph(c0, c1, a0=255, a1=0, curve="in"):
    return Col.ease(rgba(c0, a0), rgba(c1, a1), curve)


def wave_burst():
    """聖槌波の爆ぜ（帯の中心の地面）。"""
    fx = Effect(P + "wave_burst", frames=44, kit=True)
    lines = burst_lines(HOT, n=14, speed=(9, 16), life=(9, 14), length=2.0, y=0.3)
    sparks = flecks(GOLD, n=16, speed=(3, 8), life=(18, 32), size=0.28, y=0.3, gravity=-9, c2=ORANGE)
    fx.add(
        glow_core("flash", WHITE, 3.2, 8, y=0.5),
        Node("burst", tex="Fx_Burst", blend="add", life=10, loc=Loc.fixed(0, 0.45, 0), scale=Scl.ease(3.4, 5.2, "out"),
             rot=Rot.pva(((0, 0, 0), (0, 0, 360))), color=morph(HOT, ORANGE, 250, 0)),
        lines,
        sparks,
        Node("glints", tex="Fx_Star4", blend="add", life=(10, 16), count=5, delay=3, gen=Gen.circle(1.3, division=5, rotate=False),
             loc=Loc.fixed(0, 0.5, 0), scale=Scl.ease(0.8, 1.6, "out"), color=fade(WHITE, 230)),
    )
    return fx


def slam():
    """崩落の瞬間から（範囲の半径 2.78 m で作る）。"""
    fx = Effect(P + "slam", frames=70, kit=True)
    shards = scatter("Fx_Shard", ROCK, n=16, speed=(4, 9), life=(30, 46), size=1.0, y=0.3, gravity=-14, spin=360, spread=0.7)
    shards.blend = "normal"
    fx.add(
        glow_core("flash", WHITE, 8.0, 12, y=0.9),
        Node("burst", tex="Fx_Burst", blend="add", life=14, loc=Loc.fixed(0, 0.6, 0), scale=Scl.ease(8.4, 11.6, "out"),
             rot=Rot.pva(((0, 0, 0), (0, 0, 360))), color=morph(HOT, ORANGE, 255, 0)),
        burst_lines(HOT, n=24, speed=(10, 18), life=(10, 16), length=3.2, y=0.4),
        shards,
        flecks(GOLD, n=28, speed=(4, 10), life=(18, 34), size=0.32, y=0.4, gravity=-9, c2=ORANGE),
        Node("glints", tex="Fx_Star4", blend="add", life=(12, 20), count=8, delay=4, gen=Gen.circle(2.6, division=8, rotate=False),
             loc=Loc.fixed(0, 0.4, 0), scale=Scl.ease(1.0, 2.0, "out"), color=fade(WHITE, 230)),
    )
    return fx


def dash_hit():
    """突進の衝突（被弾者の体の中ほど）。MLBB の 5.5 秒: 白い 4 本の光芒の星が 2〜3 コマ。"""
    fx = Effect(P + "dash_hit", frames=20, kit=True)
    fx.add(
        Node("star", tex="Fx_Star4", blend="add", life=8, scale=Scl.ease(3.0, 4.2, "out"), rot=Rot.pva(((0, 0, -8), (0, 0, 8))),
             color=fade(WHITE, 255)),
        Node("burst", tex="Fx_Burst", blend="add", life=7, scale=Scl.ease(1.6, 2.4, "out"), rot=Rot.pva(((0, 0, 0), (0, 0, 360))),
             color=morph(WHITE, HOT, 240, 0)),
        glow_core("flash", WHITE, 1.8, 6),
        burst_lines(WHITE, n=8, speed=(6, 11), life=(6, 10), length=1.1),
    )
    return fx


def build():
    return [wave_burst(), slam(), dash_hit()]


if __name__ == "__main__":
    for e in build():
        print(e.build())
