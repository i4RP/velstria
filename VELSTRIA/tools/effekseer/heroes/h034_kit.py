"""H034 ゴルム（MLBB: フランコ）のキットの段に重ねる効果（Effects/Effekseer/Kit/H034_*.efk。FX_H034.swift の FXCue.efk が再生する）。

MLBB の画面収録（franco_sfx。1108×512・30fps・62.3 px/m）で測った大きさ・色・時刻（docs/vfx/H034.md）。時間はフレーム（60fps。録画の 1 コマ = 2 フレーム）。
  H034_hit_spark  命中の閃き（鉤の命中・奥義の 1 撃ごと・S2 の被弾）。白い芯 1 コマ → 淡い黄の棘の光芒（約 2.2 m）→ 4 コマで消える。3D の上の層
  H034_s2_slam    S2 の叩きつけ（範囲の半径 2.57 m で作る。再生の倍率 = 半径 / 2.57）。黄の円の閃光 → 外の細い赤い線 → 外向きの炎の舌の輪
                   （中心 2.1〜2.2 m・外縁 2.4 m・舌の先 2.5 m）→ 0.47 秒で消える。中心の焦げ跡と放射状のひびは 0.67 秒まで。3D に隠れる
  H034_ult_final  奥義の 6 撃目（最後の撃の 0.17 秒前から）。対象の足元の淡い黄緑の円（半径 1.6 → 1.9 m、縁が明るい）・立ちのぼる黄の光の棘
                   （約 3.5 m）・暗いひび（最後の撃の 0.4 秒後まで）・最後の撃の閃光。3D に隠れる
効果は前 = -Z。地面の板は fixed で (90, 0, 0)。
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from efkgen import Col, Effect, Gen, Loc, Node, Rot, Scl  # noqa: E402

P = "H034_"


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def fade(c, a0=255, a1=0, curve="in"):
    return Col.ease(rgba(c, a0), rgba(c, a1), curve)


def morph(c0, c1, a0=255, a1=0, curve="in"):
    return Col.ease(rgba(c0, a0), rgba(c1, a1), curve)


def flat(name, tex, d0, d1, life, y=0.06, delay=0, color=None, blend="normal", curve="out", fade_in=0, x=0.0, z=0.0, spin=0):
    """地面に寝かせた板（直径 d0 → d1 m）。"""
    rot = Rot.pva((90, 0, 0), (0, 0, spin)) if spin else Rot.fixed(90, 0, 0)
    return Node(name, tex=tex, blend=blend, life=life, delay=delay, billboard="fixed", rot=rot, loc=Loc.fixed(x, y, z),
                scale=Scl.ease(d0, d1, curve) if d0 != d1 else Scl.fixed(d0), color=color or Col.fixed(), fade_in=fade_in)


# ---- 命中の閃き -----------------------------------------------------------------------------

def hit_spark():
    """白い芯（1 コマ = 2 フレーム）→ 淡い黄の棘の光芒（#F9F4B1 / #F7EA9A、橙の棘 #E99065・先 #FBFE7D）→ 8 フレームで消える。"""
    fx = Effect(P + "hit_spark", frames=14, kit=True)
    fx.add(
        Node("flash", tex="Fx_Core", blend="add", life=4, scale=Scl.ease(1.3, 1.7, "out"),
             color=fade(hexc("#FEFFE2"), 255, 0, "lin")),
        Node("burst", tex="Fx_Burst", blend="add", life=8, scale=Scl.ease(1.7, 2.3, "out"), rot=Rot.pva(((0, 0, 0), (0, 0, 360))),
             color=morph(hexc("#FBF7C6"), hexc("#F7EA9A"), 255, 0)),
        Node("spikes", tex="Fx_Burst", blend="add", life=7, delay=1, scale=Scl.ease(2.0, 2.5, "out"), rot=Rot.pva(((0, 0, 0), (0, 0, 360))),
             color=morph(hexc("#E99065"), hexc("#FBFE7D"), 200, 0)),
        Node("star", tex="Fx_Star4", blend="add", life=6, scale=Scl.ease(1.0, 1.6, "out"), rot=Rot.pva(((0, 0, -20), (0, 0, 20))),
             color=fade(hexc("#FBFE7D"), 230)),
    )
    return fx


# ---- S2 の叩きつけ --------------------------------------------------------------------------

# 炎の輪の画像（Fx_FlameRing）: 画像の端 = 大きい舌の先。帯は画像の半径の 0.70〜0.86、舌は 0.86〜1.0。
# 範囲の半径 2.57 m で舌の先 2.5 m（0.97 R）・帯の外縁 2.15 m・内縁 1.75 m（録画: 内縁 1.95〜2.0・帯の中心 2.1〜2.2・外縁 2.4・先 2.5 m）
RING_TIP = 2.5


def s2_slam():
    fx = Effect(P + "s2_slam", frames=48, kit=True)
    d_full = RING_TIP * 2
    d_start = d_full * (1.41 / 2.15)  # 叩きつけの次のコマ（I+1）の輪の中心 1.41 m → 満ちた輪 2.15 m
    fx.add(
        # 叩きつけの閃光（I+0、次のコマで薄れる）: 黄に白飛びする芯（半径 0.8 m）と、橙へ落ちる満ちた円（半径 2.0 m）
        flat("flash_disc", "Fx_SoftDisc", 4.2, 4.4, 5, y=0.07, color=morph(hexc("#F9D46E"), hexc("#D19F5E"), 245, 0, "lin")),
        flat("flash_mid", "Fx_SoftDisc", 3.0, 3.2, 4, y=0.072, blend="add", color=fade(hexc("#F1B267"), 200, 0, "lin")),
        flat("flash_core", "Fx_Glow", 2.6, 2.9, 4, y=0.075, blend="add", color=fade(hexc("#FDFF7C"), 255, 0, "lin")),
        # 外の細い赤い線（I+0〜I+2。半径 1.8 → 2.05 m。Fx_ThinRing の線は画像の半径の 0.95）
        flat("red_line", "Fx_ThinRing", 1.8 * 2 / 0.95, 2.05 * 2 / 0.95, 6, y=0.078, color=fade(hexc("#D85D4E"), 255, 0, "in")),
        # 輪の内の橙の円（I+1〜I+4）
        flat("inner_disc", "Fx_SoftDisc", 3.6, 3.9, 10, y=0.065, delay=2, color=fade(hexc("#E97947"), 190, 0, "in")),
        # 外向きの炎の舌の輪: I+1〜I+3 で一気に広がり（6 フレーム）、I+8 から赤く暗くなって I+14 で消える
        flat("ring_grow", "Fx_FlameRing", d_start, d_full, 6, y=0.08, delay=2, curve="out",
             color=Col.fixed(255, 255, 255, 255)),
        flat("ring", "Fx_FlameRing", d_full, d_full * 1.02, 20, y=0.08, delay=8,
             color=Col.ease((255, 255, 255, 255), (150, 95, 85, 0), "in")),
        # 舌の根元のまばらな黄のハイライト（#FDF191。加算）
        flat("ring_core", "Fx_FlameRingCore", d_start, d_full, 6, y=0.085, delay=2, blend="add", curve="out",
             color=fade(hexc("#FDF191"), 230, 160, "lin")),
        flat("ring_core_hold", "Fx_FlameRingCore", d_full, d_full * 1.01, 8, y=0.085, delay=8, blend="add",
             color=fade(hexc("#FDF191"), 160, 0, "in")),
        # 中心の焦げ跡（I+4〜I+20。暗い芯 1 m → 1.7 m で消える）と、薄い放射状のひび
        flat("scorch", "Fx_Scorch", 3.4, 3.5, 34, y=0.062, delay=8, fade_in=4, color=fade(hexc("#1E1A10"), 200, 0, "in")),
        flat("cracks", "Fx_CrackRadial", 3.0, 3.0, 30, y=0.063, delay=8, fade_in=4, color=fade(hexc("#2A2118"), 120, 0, "in")),
        # 内の円の放射状の土の筋（I+1〜I+5）
        Node("dust", tex="Fx_Streak", blend="normal", life=(8, 12), count=16, delay=2, billboard="fixed",
             gen=Gen.circle((0.6, 1.5), division=16), rot=Rot.fixed(90, 90, 0), loc=Loc.fixed(0, 0.066, 0),
             scale=Scl.ease((0.7, 0.2, 1), (1.0, 0.12, 1), "out"), color=fade(hexc("#B0683E"), 140, 0, "in")),
    )
    return fx


# ---- 奥義の 6 撃目 ---------------------------------------------------------------------------

def ult_final():
    """最後の撃の 0.17 秒前（10 フレーム前）から。対象の足元（原点）。"""
    fx = Effect(P + "ult_final", frames=60, kit=True)
    fx.add(
        # 淡い黄緑の円（半径 1.6 → 1.9 m。#9CB670、縁 #FBFFA3）
        flat("disc", "Fx_Glow", 3.6, 4.2, 20, y=0.07, color=fade(hexc("#9CB670"), 140, 0, "in")),
        flat("rim", "Fx_RingSoft", 1.6 * 2 / 0.9, 1.95 * 2 / 0.9, 18, y=0.075, blend="add", color=fade(hexc("#FBFFA3"), 230, 0, "in")),
        # 立ちのぼる黄の光の棘（約 3.5 m。#EBEE84 / #FBFF9F）
        Node("spikes", tex="Fx_Spike", blend="add", life=(10, 14), count=12, delay=3, interval=0.6, billboard="yfixed",
             gen=Gen.circle((0.2, 1.4), division=12, rotate=False), loc=Loc.fixed(0, 1.6, 0),
             scale=Scl.ease((0.45, 1.2, 1), (0.3, 3.4, 1), "out"), color=morph(hexc("#FBFF9F"), hexc("#EBEE84"), 255, 0)),
        # 暗いひびの網（#28201C。最後の撃の 0.4 秒後まで）
        flat("cracks", "Fx_CrackRadial", 3.4, 3.6, 40, y=0.065, delay=5, fade_in=2, color=fade(hexc("#28201C"), 220, 0, "in")),
        flat("scorch", "Fx_Scorch", 2.8, 3.0, 36, y=0.062, delay=6, fade_in=4, color=fade(hexc("#2A2418"), 120, 0, "in")),
        # 最後の撃の大きな閃光（10 フレーム目）
        Node("flash", tex="Fx_Glow", blend="add", life=8, delay=10, loc=Loc.fixed(0, 0.9, 0), scale=Scl.ease(2.4, 3.4, "out"),
             color=fade(hexc("#FBFFA3"), 255, 0, "in")),
        flat("flash_ground", "Fx_Glow", 3.4, 4.2, 8, y=0.08, delay=10, blend="add", color=fade(hexc("#F4EE90"), 220, 0, "in")),
    )
    return fx


def build():
    return [hit_spark(), s2_slam(), ult_final()]


if __name__ == "__main__":
    for e in build():
        print(e.build())
