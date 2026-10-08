"""H007 岩脈のガルク（Paquito 型: 格闘コンビネーション・チャンプスタンス）。金 + 赤橙の拳。近接ヴァンガード。"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from kit import *

S = Style(core=(255, 250, 230), main=(255, 205, 70), accent=(255, 95, 60), dark=(130, 70, 20))
P = "H007_"


def pow_burst(size=1.0, y=0.0, delay=0, c=None):
    """パンチの着弾（大きな光芒 + 衝撃輪 + 放射線）。"""
    c = c or S.main
    return [glow_core("flare", S.core, 2.6 * size, 8, y=y, delay=delay), Node("star", tex="Fx_Star", life=12, delay=delay, loc=Loc.fixed(0, y, 0), scale=Scl.ease(1.6 * size, 4.4 * size, "out"), color=fade(c)),
            Node("ring", tex="Fx_Ring", life=10, delay=delay, loc=Loc.fixed(0, y, 0), scale=Scl.ease(0.5 * size, 3.2 * size, "out"), color=fade(S.core, 230)),
            burst_lines(S.core, n=12, length=1.1 * size, y=y, delay=delay), under(S.accent, 3.4 * size, 14, y=y, delay=delay, a=150)]


def build():
    E = []
    # 通常攻撃: 左右のパンチ（短い突き + 衝撃）
    E.append(make(P + "atk_cast", [flat_streak("punch", S.core, 3.0, 0.5, 8, z=-1.3), flat_streak("trail", S.main, 2.6, 0.9, 10, z=-1.0, a=170), glow_core("flare", S.core, 1.2, 7, z=-1.6, y=0.1)], 20))
    E.append(make(P + "atk_cast2", [flat_streak("punch", S.core, 3.0, 0.5, 8, z=-1.3, yaw=-10), flat_streak("trail", S.accent, 2.6, 0.9, 10, z=-1.0, yaw=-10, a=170), glow_core("flare", S.core, 1.2, 7, z=-1.6, y=0.1)], 20))
    E.append(make(P + "atk_hit", pow_burst(0.8), 24))
    # S1 ヘビーレフトパンチ: 強い左の一撃 + 金の障壁（シールド）
    E.append(make(P + "s1_cast", [glow_core("flare", S.core, 2.0, 9, z=-0.5), Node("shield", tex="Fx_Hex", life=36, loc=Loc.fixed(0, 0.2, 0), scale=Scl.ease(2.0, 3.2, "out"), color=Col.ease(rgba(S.main, 200), rgba(S.main, 0), "in"), fade_in=4)], 36))
    E.append(make(P + "s1_impact", [flat_streak("fist", S.core, 6.0, 1.0, 12, z=-2.8), flat_streak("fist2", S.accent, 6.0, 1.5, 14, z=-2.8, a=170)] + pow_burst(1.5, delay=2) + [crescent("wave", S.main, 5.0, 14, z=-2.4, y=0.1, a=210)], 32))
    E.append(make(P + "s1_hit", pow_burst(0.9), 24))
    # S2 ジャブ: ダッシュしながらの連打
    E.append(make(P + "s2_cast", [speed_lines(S.accent, 14, 3.4), glow_core("flare", S.core, 2.0, 8), flat_streak("jab1", S.core, 3.4, 0.4, 7, z=-1.4, yaw=-8), flat_streak("jab2", S.core, 3.4, 0.4, 7, z=-1.4, yaw=8, delay=3)], 26))
    E.append(make(P + "s2_impact", pow_burst(1.3) + pow_burst(1.0, delay=5) + [ground_pulse(S.main, 0.4, 3.2, 16), under(S.dark, 4.0, 16, a=170)], 32))
    E.append(make(P + "s2_hit", pow_burst(0.85), 22))
    # ULT ノックアウトストライク: エルボー → 後退しつつアッパー（真上へ突き上げる柱）
    E.append(make(P + "ult_cast", [glow_core("flare", S.core, 2.6, 10), ground_pulse(S.main, 0.4, 3.2, 16), speed_lines(S.main, 10, 3.2), decal(S.main, 4.4, 24, spin=70)], 30))
    E.append(make(P + "ult_impact", [ground_pulse(S.core, 0.5, 4.4, 18, a=255), ground_pulse(S.accent, 0.5, 5.0, 22, delay=4), decal(S.accent, 6.0, 50, tex="Fx_Crack", grow=0.5, a=230),
                                     pillar(S.main, 2.4, 7.0, 22, delay=3), pillar(S.core, 1.0, 8.0, 18, delay=3), glow_core("flare", S.core, 4.0, 12), under(S.accent, 6.0, 24, a=170),
                                     Node("upper", tex="Fx_Star", life=16, loc=Loc.ease((0, 0, 0), (0, 3.4, 0), "out"), scale=Scl.ease(2.0, 5.0, "out"), color=fade(S.core)),
                                     flecks(S.main, n=22, y=0.2, speed=(4, 11)), scatter("Fx_Diamond", S.main, n=10, size=0.6, speed=(3, 8), life=(20, 32))], 56))
    E.append(make(P + "ult_hit", pow_burst(1.3), 26))
    return E


if __name__ == "__main__":
    build_set(build())
