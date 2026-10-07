"""H009 機巧士オリン（Kimmy 型: 移動しながら射撃・スラスター・重力）。化学の黄緑 + 青緑 + 重力の紫。遠隔レンジャー。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(250, 255, 235), main=(190, 255, 110), accent=(90, 235, 215), dark=(30, 110, 80))
GRAV = (170, 110, 255)
P = "H009_"


def build():
    E = []
    # 通常攻撃: 連弩の速射（小さな黄緑の弾）
    E.append(make(P + "atk_cast", ranged_muzzle(S, 0.85), 22))
    E.append(make(P + "atk_travel", [Node("bolt", tex="Fx_Arrow", life=600, billboard="fixed", rot=Rot.fixed(90, 90, 0), scale=Scl.fixed(1.5, 0.3, 1), color=Col.fixed(*S.core, 255)),
                                     Node("core", tex="Fx_Core", life=600, scale=Scl.fixed(0.55), color=Col.fixed(*S.main, 255)), Node("halo", tex="Fx_Glow", life=600, scale=Scl.fixed(1.3), color=Col.fixed(*S.accent, 130)),
                                     trail_dust(S.main, size=0.34, c2=S.accent, interval=1)], 40, loop=True))
    E.append(make(P + "atk_hit", hit_burst(S, 0.8, fleck=6), 26))
    # S1 反重力スラスター: 噴射 + 周囲へ化学ボルト 4 発
    E.append(make(P + "s1_cast", [Node("jet", tex="Fx_Core", life=18, count=6, interval=2, billboard="billboard", loc=Loc.pva(pos=((0, -0.2, 0.3), (0, -0.2, 0.3)), vel=((0, -3, 2), (0, -5, 4))), scale=Scl.ease(1.4, 0.2), color=morph(S.main, S.accent, 255, 0)),
                                  glow_core("flare", S.core, 2.4, 10, y=0.0), ground_pulse(S.accent, 0.3, 2.6, 16), speed_lines(S.main, 8, 2.8),
                                  Node("bolts", tex="Fx_Bolt", life=10, count=4, delay=4, billboard="billboard", gen=Gen.circle(1.4, rotate=False), loc=Loc.fixed(0, 0.4, 0), scale=Scl.fixed(0.5, 1.8, 1), color=Col.fixed(*S.main, 255))], 34))
    E.append(make(P + "s1_travel", projectile(S, "orb", 0.9), 40, loop=True))
    E.append(make(P + "s1_impact", hit_burst(S, 1.2, extra=[ground_pulse(S.accent, 0.3, 2.4, 14, y=-0.8)]), 30))
    E.append(make(P + "s1_hit", hit_burst(S, 0.9), 26))
    # S2 スターリアムビーム: 直線の太い光線（ブリンク + 強化射撃）
    E.append(make(P + "s2_cast", [Node("beam", tex="Fx_Beam", life=22, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.fixed(0, 0.2, -4.2), scale=Scl.ease((8.4, 1.4, 1), (8.4, 0.5, 1), "out"), color=fade(S.core, 255)),
                                  Node("beamB", tex="Fx_Beam", life=24, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.fixed(0, 0.15, -4.2), scale=Scl.ease((8.4, 2.6, 1), (8.4, 0.9, 1), "out"), color=fade(S.accent, 190)),
                                  glow_core("flare", S.core, 2.6, 12, z=-0.4), ground_pulse(S.main, 0.3, 2.2, 14)], 30))
    E.append(make(P + "s2_impact", [glow_core("flare", S.core, 2.4, 10), Node("star", tex="Fx_Star", life=14, scale=Scl.ease(1.0, 3.6, "out"), color=fade(S.main)), under(S.accent, 3.0, 14)], 26))
    E.append(make(P + "s2_hit", hit_burst(S, 0.9), 24))
    # ULT トラクションパルス: 重力弾 → 着弾で重力場が収縮して吸い込む（紫の渦）
    E.append(make(P + "ult_cast", [glow_core("charge", GRAV, 2.6, 14, z=-0.6), spin_flat("coil", GRAV, 3.0, 0.6, 16, y=0.0, tex="Fx_Spiral", spin=-600, a=230, curve="in"), ground_pulse(S.accent, 0.3, 2.6, 16)], 30))
    E.append(make(P + "ult_travel", projectile(Style(S.core, GRAV, S.accent, (60, 30, 110)), "spiral", 1.0), 40, loop=True))
    E.append(make(P + "ult_impact", [Node("well", tex="Fx_Glow", blend="normal", life=70, scale=Scl.ease(2.4, 3.4, "lin"), color=Col.ease(rgba((50, 20, 110), 190), rgba((50, 20, 110), 0), "in"), fade_in=4),
                                     spin_flat("swirl", GRAV, 6.6, 1.0, 60, y=0.0, tex="Fx_Spiral", spin=-480, a=240, curve="in"), spin_flat("swirl2", S.accent, 4.4, 0.6, 50, y=0.1, tex="Fx_Spiral", spin=-700, a=180, curve="in"),
                                     decal(GRAV, 6.4, 64, spin=-90), ground_pulse(S.core, 4.6, 0.5, 40, y=-0.8, a=220), glow_core("core", S.core, 3.0, 14, delay=40, grow=(0.3, 1.0)),
                                     Node("pulse", tex="Fx_RingSoft", life=18, delay=48, loc=Loc.fixed(0, 0.4, 0), scale=Scl.ease(0.6, 5.6, "out"), color=fade(GRAV, 230))], 84))
    E.append(make(P + "ult_hit", hit_burst(S, 1.1, extra=[Node("zap", tex="Fx_Core", life=12, scale=Scl.ease(0.6, 2.4, "out"), color=fade(GRAV, 220))]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
