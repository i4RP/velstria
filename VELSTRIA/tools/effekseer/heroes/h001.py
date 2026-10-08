"""H001 城門の誓衛アルデン（Gloo 型: くっつく粘液・寄生）。粘液の黄緑 + 青緑 + 白のハイライト。近接ヴァンガード。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(240, 255, 235), main=(140, 245, 100), accent=(70, 220, 190), dark=(40, 120, 50))
P = "H001_"


def splat(size=1.0, y=0.0, delay=0, n=8):
    """粘液の飛沫（blob が広がって飛び散る）。"""
    return [Node("blobs", tex="Fx_Blob", blend="normal", life=(14, 22), count=n, delay=delay, billboard="billboard", gen=Gen.sphere(0.05, rx=(-70, 70), ry=(-180, 180)),
                 loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, 3, 0), (0, 8, 0)), acc=(0, -14, 0)), scale=Scl.ease(0.7 * size, 0.2 * size), color=Col.ease(rgba(S.main, 235), rgba(S.dark, 0), "in")),
            Node("ring", tex="Fx_RingSoft", life=12, delay=delay, loc=Loc.fixed(0, y, 0), scale=Scl.ease(0.6 * size, 2.8 * size, "out"), color=fade(S.core, 200))]


def build():
    E = []
    # 通常攻撃: 粘液をまとった剣・盾の殴り
    sw = lambda flip: [crescent("slash", S.main, 3.4, 10, y=0.2, z=-1.6), arc_slash("arc", S.accent, 2.6, 11, sweep=(60, -60) if flip else (-60, 60), y=0.2, width=0.45),
                       Node("drip", tex="Fx_Blob", blend="normal", life=(12, 18), count=3, billboard="billboard", gen=Gen.sphere(0.2, rotate=False), loc=Loc.pva(pos=((0, 0.2, -1.2), (0, 0.2, -1.2)), vel=((0, 1, 0), (0, 3, 0)), acc=(0, -10, 0)),
                            scale=Scl.ease(0.4, 0.1), color=Col.ease(rgba(S.main, 230), rgba(S.dark, 0), "in"))]
    E.append(make(P + "atk_cast", sw(False), 24))
    E.append(make(P + "atk_cast2", sw(True), 24))
    E.append(make(P + "atk_hit", hit_burst(S, 0.9, ring_c=S.accent) + splat(0.8, n=5), 28))
    # S1 たたきつけ: 体を伸ばして地面を叩く → 粘液が残り、後で爆発
    E.append(make(P + "s1_cast", [flat_streak("stretch", S.main, 4.0, 0.7, 10, z=-1.6, a=220), glow_core("flare", S.core, 1.8, 8, z=-0.5), under(S.main, 3.0, 12, z=-1.0)], 24))
    E.append(make(P + "s1_impact", [ground_pulse(S.main, 0.4, 3.2, 18, y=-0.85, a=240), Node("puddle", tex="Fx_Blob", blend="normal", life=70, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(0, -0.84, -2.0), scale=Scl.ease(1.0, 2.6, "out"),
                                                                                          color=Col.ease(rgba(S.main, 220), rgba(S.dark, 0), "in")), glow_core("flare", S.core, 2.4, 10, z=-2.0)] + splat(1.3, n=10), 78))
    E.append(make(P + "s1_hit", hit_burst(S, 0.9, ring_c=S.accent) + splat(0.8, n=4), 26))
    # S2 ぶんさん: 複数のスライムに分裂して進み、突進して合体
    E.append(make(P + "s2_cast", [Node("clones", tex="Fx_Blob", blend="normal", life=20, count=5, billboard="billboard", gen=Gen.circle(0.5, rotate=False), loc=Loc.pva(vel=((0, 0.3, -4), (0, 1.2, -8))), scale=Scl.ease(0.8, 0.5), color=Col.ease(rgba(S.main, 230), rgba(S.dark, 0), "in")),
                                  speed_lines(S.accent, 10, 3.0), glow_core("flare", S.core, 1.8, 9)], 28))
    E.append(make(P + "s2_impact", [ground_pulse(S.main, 0.4, 3.2, 16, y=-0.85, a=240), ground_pulse(S.accent, 0.4, 3.6, 20, delay=3, y=-0.85), glow_core("flare", S.core, 2.6, 10), under(S.dark, 4.0, 18, a=170)] + splat(1.2, n=9), 34))
    E.append(make(P + "s2_hit", hit_burst(S, 0.85, ring_c=S.accent), 24))
    # ULT からみつき: 跳びついて巨大な粘液、へばりつく糸
    E.append(make(P + "ult_cast", [glow_core("flare", S.core, 2.6, 12), ground_pulse(S.accent, 0.4, 3.0, 16), decal(S.main, 4.4, 24, spin=70), speed_lines(S.main, 8, 3.0)], 30))
    E.append(make(P + "ult_impact", [ground_pulse(S.core, 0.5, 4.2, 18, y=-0.85, a=255), ground_pulse(S.main, 0.5, 5.0, 24, y=-0.85, delay=4), glow_core("flare", S.core, 3.6, 12), under(S.dark, 6.0, 40, a=190),
                                     Node("puddle", tex="Fx_Blob", blend="normal", life=84, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(0, -0.84, 0), scale=Scl.ease(2.0, 5.4, "out"), color=Col.ease(rgba(S.main, 225), rgba(S.dark, 0), "in")),
                                     Node("strings", tex="Fx_Chain", life=(30, 44), count=9, billboard="yfixed", rot=Rot.fixed(0, 0, 90), gen=Gen.circle(1.8, rotate=False), loc=Loc.pva(pos=((0, 0.2, 0), (0, 0.2, 0)), vel=((0, 1.2, 0), (0, 2.2, 0))),
                                          scale=Scl.ease((0.4, 1.0, 1), (0.6, 3.2, 1), "out"), color=fade(S.accent, 230))] + splat(1.8, n=14), 92))
    E.append(make(P + "ult_hit", hit_burst(S, 1.1, ring_c=S.accent) + splat(1.0, n=6), 28))
    return E


if __name__ == "__main__":
    build_set(build())
