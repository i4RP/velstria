"""H026 紫電のエウリア（Eudora 型: 分岐する雷・雷球の麻痺・天雷）。紫 + 黒藍 + 電光の白と水色。遠隔アルカニスト。

段: atk_cast / atk_travel / atk_hit / s1_cast / s1_travel / s1_impact / s1_hit / s2_cast / s2_impact / s2_hit /
    ult_cast / ult_telegraph / ult_impact / ult_hit（H016 と同じ構成）
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *  # noqa: E402

S = Style(core=(245, 240, 255), main=(165, 105, 255), accent=(120, 225, 255), dark=(45, 18, 105))
P = "H026_"


def zigzag(n=6, seg=1.1, spread=22, c=None, width=0.2, life=9, y=0.15, z0=-0.4, delay=0, name="zig", a=240):
    """前（-Z）へ走るぎざぎざの稲妻（短い筋を左右交互に振って折れ線にする）。"""
    out = []
    x, z = 0.0, z0
    for i in range(n):
        yaw = spread if i % 2 == 0 else -spread
        rad = math.radians(yaw)
        # 筋の中心は、直前の端点から進行方向へ seg / 2 の位置
        cx, cz = x - math.sin(rad) * seg * 0.5, z - math.cos(rad) * seg * 0.5
        out.append(flat_streak(f"{name}{i}", c or (S.core if i % 2 == 0 else S.accent), seg * 1.15, width, life, z=cz, x=cx, yaw=yaw, y=y, delay=delay + (i >> 1), a=a, stretch=False))
        x, z = x - math.sin(rad) * seg, z - math.cos(rad) * seg
    return out


def bolt_up(h=7.0, w=1.0, life=10, delay=0, x=0.0, z=0.0, c=None, y=0.0):
    """天から落ちる雷（縦の稲妻）。"""
    return Node("bolt", tex="Fx_Bolt", life=life, delay=delay, billboard="yfixed", loc=Loc.fixed(x, y + h * 0.5, z), scale=Scl.ease((w * 0.6, h, 1), (w, h * 1.02, 1), "out"), color=fade(c or S.core, 255))


def arcs(n=6, radius=1.0, life=(8, 14), size=(0.5, 1.6), delay=0, c=None, y=0.0):
    """球状に弾ける細い雷（電弧）。"""
    return Node("arcs", tex="Fx_Bolt", life=life, count=n, delay=delay, billboard="billboard", gen=Gen.sphere(radius * 0.2, rx=(-90, 90), ry=(-180, 180), rotate=False),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, 0.5, 0), (0, 1.5, 0))), rot=Rot.pva(0, ((0, 0, -200), (0, 0, 200))),
                scale=Scl.ease((size[0] * 0.5, size[1], 1), (size[0] * 0.25, size[1] * 0.7, 1)), color=fade(c or S.accent, 240))


def build():
    E = []
    # 通常攻撃: 杖の先から紫電の弾
    E.append(make(P + "atk_cast", ranged_muzzle(S, 1.0) + [arcs(3, 0.6, (8, 12), (0.4, 1.0), c=S.core)], 24))
    E.append(make(P + "atk_travel", projectile(S, "orb", 1.0) + [Node("spark", tex="Fx_Bolt", life=(5, 8), count="inf", interval=(3, 5), billboard="billboard", gen=Gen.sphere(0.35, rx=(-90, 90), ry=(-180, 180), rotate=False),
                                                                    rot=Rot.pva(0, ((0, 0, -300), (0, 0, 300))), scale=Scl.fixed(0.35, 1.0, 1), color=fade(S.accent, 240))], 40, loop=True))
    E.append(make(P + "atk_hit", hit_burst(S, 0.95, extra=[arcs(4, 0.8, (8, 12), (0.5, 1.2))]), 28))
    # S1 紫電の走り: 前へ分岐して走る稲妻
    branches = zigzag(6, 1.0, 20, name="main", life=10) + zigzag(4, 0.9, 38, name="brL", life=9, delay=1, c=S.main, width=0.14, z0=-1.6, a=220)
    E.append(make(P + "s1_cast", branches + [glow_core("flare", S.core, 1.8, 9, z=-0.4), arcs(4, 0.8, (8, 12), (0.5, 1.2)), ground_pulse(S.main, 0.3, 2.0, 14, y=-0.85)], 28))
    E.append(make(P + "s1_travel", projectile(S, "bolt", 1.4) + [Node("fork", tex="Fx_Bolt", life=(5, 9), count="inf", interval=(2, 3), billboard="billboard", gen=Gen.sphere(0.5, rx=(-90, 90), ry=(-180, 180), rotate=False),
                                                                    rot=Rot.pva(0, ((0, 0, -400), (0, 0, 400))), scale=Scl.fixed(0.5, 1.6, 1), color=fade(S.accent, 235))], 40, loop=True))
    E.append(make(P + "s1_impact", hit_burst(S, 1.2, extra=[bolt_up(4.5, 0.8, 9), arcs(8, 1.2, (8, 14), (0.6, 1.8)), ground_pulse(S.main, 0.3, 2.6, 16, y=-0.8)]), 32))
    E.append(make(P + "s1_hit", hit_burst(S, 0.9, extra=[arcs(4, 0.8, (8, 12), (0.5, 1.3))]), 26))
    # S2 麻痺の雷球: 紫の雷球が脈打つ → 着弾の放電とスタンの輪
    E.append(make(P + "s2_cast", [glow_core("orb", S.core, 2.4, 14, z=-0.8), under(S.main, 3.2, 16, z=-0.8), Node("halo", tex="Fx_Glow", life=16, loc=Loc.fixed(0, 0, -0.8), scale=Scl.ease(1.0, 3.4, "out"), color=fade(S.main, 200)),
                                  arcs(8, 1.0, (8, 14), (0.5, 1.5), c=S.accent, y=0.0), ground_pulse(S.accent, 0.3, 2.2, 16, y=-0.85), decal(S.main, 3.6, 24, y=-0.85, spin=120, a=200)], 30))
    E.append(make(P + "s2_impact", [glow_core("flare", S.core, 3.2, 12), Node("star", tex="Fx_Star", life=16, scale=Scl.ease(1.4, 4.4, "out"), color=fade(S.accent)),
                                    ground_pulse(S.core, 0.4, 3.0, 16, y=-0.8, a=255), ground_pulse(S.main, 0.4, 3.6, 22, y=-0.8, delay=3), decal(S.main, 4.6, 40, y=-0.84, spin=-100, a=220),
                                    decal(S.accent, 3.0, 40, y=-0.83, tex="Fx_Hex", spin=140, a=190), under(S.dark, 4.0, 22, a=170), arcs(12, 1.6, (8, 14), (0.7, 2.0)),
                                    # スタンの印: 頭上で回る電光の輪
                                    Node("stun", tex="Fx_Wheel", life=44, billboard="fixed", rot=Rot.pva((90, 0, 0), (0, 0, 480)), loc=Loc.fixed(0, 1.2, 0), scale=Scl.fixed(1.6), color=Col.ease(rgba(S.accent, 230), rgba(S.accent, 0), "in"), fade_in=4)], 50))
    E.append(make(P + "s2_hit", hit_burst(S, 0.95, extra=[arcs(5, 0.9, (8, 12), (0.5, 1.4))]), 26))
    # ULT 九天雷鳴: 予告の紫の陣 → 天から無数の雷が降り注ぐ
    E.append(make(P + "ult_cast", [glow_core("flare", S.core, 2.6, 12), ground_pulse(S.main, 0.4, 3.0, 16, y=-0.85), decal(S.accent, 4.2, 30, y=-0.84, spin=100), arcs(10, 1.2, (8, 14), (0.6, 1.8)),
                                   pillar(S.main, 1.6, 5.0, 20)], 34))
    E.append(make(P + "ult_telegraph", [decal(S.main, 7.0, 44, y=-0.84, spin=50, a=180, grow=0.9, fade_in=8), decal(S.accent, 4.6, 44, y=-0.83, tex="Fx_Hex", spin=-80, a=150, grow=0.9, fade_in=8),
                                        Node("warn", tex="Fx_Ring", life=44, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(0, -0.82, 0), scale=Scl.fixed(6.6),
                                             color=Col.ease(rgba(S.main, 120), rgba(S.accent, 230), "lin"), fade_in=6)], 48))
    strikes = []
    for i, (dx, dz, d) in enumerate(((0, 0, 0), (1.8, -1.2, 5), (-1.9, 0.9, 9), (0.8, 2.0, 13), (-0.9, -2.2, 17), (2.4, 1.4, 21), (-2.6, -0.6, 25))):
        strikes += [Node(f"bolt{i}", tex="Fx_Bolt", life=10, delay=d, billboard="yfixed", loc=Loc.fixed(dx, 4.2, dz), scale=Scl.ease((0.7, 8.4, 1), (1.1, 8.6, 1), "out"), color=fade(S.core, 255)),
                    Node(f"flash{i}", tex="Fx_Core", life=10, delay=d, loc=Loc.fixed(dx, 0.0, dz), scale=Scl.ease(0.8, 2.8, "out"), color=fade(S.core)),
                    Node(f"ring{i}", tex="Fx_Ring", life=14, delay=d, billboard="fixed", rot=Rot.fixed(90, 0, 0), loc=Loc.fixed(dx, -0.8, dz), scale=Scl.ease(0.6, 3.6, "out"), color=fade(S.accent, 230))]
    E.append(make(P + "ult_impact", [decal(S.main, 8.0, 90, y=-0.85, spin=60, a=235), decal(S.accent, 5.4, 90, y=-0.84, tex="Fx_Hex", spin=-70, a=190), ground_pulse(S.core, 0.5, 4.4, 18, y=-0.8, a=255),
                                     ground_pulse(S.main, 0.5, 5.2, 24, y=-0.8, delay=5), under(S.dark, 7.0, 60, a=170)] + strikes +
             [arcs(18, 3.0, (8, 16), (0.7, 2.2), delay=4), flecks(S.accent, n=18, y=0.2, speed=(3, 9), c2=S.main, delay=2), rise("Fx_Glow", S.accent, count=26, radius=2.6, size=0.3, life=(30, 46), interval=(1, 2), y=-0.7)], 100))
    E.append(make(P + "ult_hit", hit_burst(S, 1.1, extra=[bolt_up(4.0, 0.7, 9), arcs(6, 1.0, (8, 12), (0.5, 1.5))]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
