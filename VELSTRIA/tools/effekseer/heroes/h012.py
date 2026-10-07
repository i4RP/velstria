"""H012 玻璃歌のエリネ（Gusion 型: ダガー投擲・瞬間移動・5 連射）。氷の青緑 + 白 + 淡い紫。近接アサシン。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(245, 255, 255), main=(120, 235, 245), accent=(200, 160, 255), dark=(20, 110, 140))
P = "H012_"


def shards_out(n=10, speed=(4, 9), size=(0.3, 1.1), delay=0, c=None, life=(12, 18), y=0.0):
    return Node("shards", tex="Fx_Shard", life=life, count=n, delay=delay, billboard="billboard", gen=Gen.sphere(0.05, rx=(-60, 60), ry=(-180, 180)),
                loc=Loc.pva(pos=((0, y, 0), (0, y, 0)), vel=((0, speed[0], 0), (0, speed[1], 0)), acc=(0, -6, 0)),
                rot=Rot.pva(0, ((0, 0, -300), (0, 0, 300))), scale=Scl.ease((size[0], size[1], 1), (size[0] * 0.5, size[1] * 0.5, 1)), color=fade(c or S.core, 240))


def build():
    E = []
    # 通常攻撃: 硝子の短剣（素早い突き 2 連）
    E.append(make(P + "atk_cast", [flat_streak("stab", S.core, 2.6, 0.2, 8, z=-1.0), flat_streak("stab2", S.main, 2.0, 0.14, 8, z=-0.9, yaw=10), glow_core("flare", S.core, 1.2, 7, z=-0.4),
                                   flecks(S.core, n=4, speed=(2, 5), size=0.18, y=0.2, c2=S.main, gravity=-2, spread=0.5)], 22))
    E.append(make(P + "atk_cast2", [flat_streak("stab", S.core, 2.6, 0.2, 8, z=-1.0, yaw=-8), flat_streak("stab2", S.main, 2.0, 0.14, 8, z=-0.9, yaw=-18), glow_core("flare", S.core, 1.2, 7, z=-0.4)], 22))
    E.append(make(P + "atk_hit", hit_burst(S, 0.9, extra=[shards_out(6)]), 28))
    # S1 ソードスパイク: 前へ投げた短剣が飛び、着弾で硝子が砕ける（再使用で背後へ）
    E.append(make(P + "s1_cast", [flight("dagger", S.core, "Fx_Shard", 1.6, 12, 5.0, y=0.4, aspect=0.45), flight("glint", S.main, "Fx_Core", 1.0, 12, 5.0, y=0.4),
                                  Node("trail", tex="Fx_Streak", life=14, billboard="fixed", rot=Rot.fixed(90, 90, 0), loc=Loc.fixed(0, 0.4, -2.6), scale=Scl.ease((2.0, 0.3, 1), (5.4, 0.1, 1), "out"), color=fade(S.main, 200)),
                                  glow_core("flare", S.core, 1.4, 8, z=-0.4)], 26))
    E.append(make(P + "s1_impact", [glow_core("flare", S.core, 2.8, 10, z=-4.8), Node("star", tex="Fx_Star", life=14, loc=Loc.fixed(0, 0.3, -4.8), scale=Scl.ease(1.2, 3.8, "out"), color=fade(S.main)),
                                    shards_out(12, delay=0), ground_pulse(S.main, 0.3, 2.4, 14, y=-0.8), under(S.main, 3.4, 14, z=-4.8)], 30))
    E.append(make(P + "s1_hit", hit_burst(S, 0.95, extra=[shards_out(6)]), 26))
    # S2 シャドウブレイド: 5 本の刃が扇状に走る（地面に刃の筋が 5 本）→ 着地
    fan = [flat_streak(f"b{i}", S.core if i == 2 else S.main, 5.4, 0.24, 14, z=-2.8, yaw=a, a=235, y=0.1) for i, a in enumerate((-36, -18, 0, 18, 36))]
    E.append(make(P + "s2_cast", fan + [glow_core("flare", S.core, 2.0, 9), speed_lines(S.accent, 8, 2.6), ground_pulse(S.accent, 0.3, 1.8, 14)], 28))
    E.append(make(P + "s2_impact", [ground_pulse(S.core, 0.4, 3.0, 16, a=255), ground_pulse(S.main, 0.4, 3.4, 18, delay=3), glow_core("flare", S.core, 3.0, 10), shards_out(16, speed=(5, 11), size=(0.35, 1.3)),
                                    under(S.main, 4.0, 16), burst_lines(S.core, n=10, length=1.2)], 32))
    E.append(make(P + "s2_hit", hit_burst(S, 0.9), 24))
    # ULT インカンデッセンス: 高速ブリンク（残像）→ 着地でリセットの閃光と刃のルーン
    E.append(make(P + "ult_cast", [speed_lines(S.main, 14, 4.0), glow_core("flare", S.core, 3.0, 12), ground_pulse(S.main, 0.4, 3.0, 16),
                                   Node("ghost", tex="Fx_Star", life=16, loc=Loc.fixed(0, 0.8, 0), scale=Scl.ease(1.2, 4.0, "out"), color=fade(S.accent, 230))], 30))
    runes = Node("orb", tex="Fx_Glow", life=70, loc=Loc.fixed(0, 0.9, 0), rot=Rot.pva(0, (0, 220, 0)), scale=Scl.fixed(0.01), color=Col.fixed(255, 255, 255, 0))
    for i in range(4):
        a = math.radians(90 * i)
        runes.add(Node(f"d{i}", tex="Fx_Shard", life=70, billboard="billboard", loc=Loc.fixed(math.sin(a) * 1.2, 0, -math.cos(a) * 1.2), scale=Scl.fixed(0.55, 1.5, 1),
                       color=Col.fixed(*S.core, 255), fade_in=6, fade_out=14))
    E.append(make(P + "ult_impact", [runes, decal(S.main, 5.0, 60, spin=80), ground_pulse(S.core, 0.4, 3.6, 18, a=255), glow_core("flare", S.core, 3.4, 12), under(S.main, 4.6, 24),
                                     Node("reset", tex="Fx_RingSoft", life=22, loc=Loc.fixed(0, 0.9, 0), scale=Scl.ease(0.8, 4.4, "out"), color=fade(S.accent, 230)), shards_out(14, speed=(4, 10)),
                                     rise("Fx_Glow", S.core, count=14, radius=1.3, size=0.26, life=(30, 50), y=-0.7)], 74))
    E.append(make(P + "ult_hit", hit_burst(S, 1.1, extra=[shards_out(8)]), 28))
    return E


if __name__ == "__main__":
    build_set(build())
