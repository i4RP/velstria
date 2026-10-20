# MARK: H032 ディアス（ディロス）— 奈落の刃を両腕に付けた戦士。重い金属の刃の振り・刃と鎧の打撃・肉を斬る音・闇の低いうねり
# 闇のうねりは本物の録音（厚い鉄板の低いうなり・遠い雷の地鳴り）。MLBB の録画はまだ無い。物差しはロームの測定（MLBB_H029.md・MLBB_H034.md）。
# sim の時刻（Kit_H032.DiasTuning）: S1 は 0.26 秒から 0.2 秒おきに輪 3 つ（0.26・0.46・0.66。強化は 5 つ）、ダメージは 1.0・0.3・0.3。
# S2 は 1040/秒で最大 415（0.4 秒）の突進、当たった所で命中。再使用（致命の一撃）は 0.06 秒の溜め（強化 0.19）→ 1200/秒で最大 283 跳び、
# 当たってから +0.15・+0.217 秒に 2・3 撃目（どれも S2 の命中）。奥義は 0.76 秒溜めて直線へ放つ（命中は放った時）。
# 演出（FX_H032）: S1 は輪の 0.08 秒前に斬撃、0.02 秒前に渦。奥義の鎌の軌跡 0・0.1・0.24・0.4、槍 0.45、放つ 0.76。
"""H032 ディアス（MLBB: ディロス）のスキル・パッシブの音。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import build_audio as B  # noqa: E402,F401

GROAN = "heavy sheet metal low groan 13"        # 厚い鉄板の低いうなり（闇のうねり）
RUMBLE = "Thunder_Rumble_Deep_Fienup_003"       # 遠い雷の深い地鳴り（闇の低音）
AXE = "Metal Bang_Collins Axe"                  # 斧と鎖を打ち合わせた重い金属の打撃
SCRAPE = "SWING SCRAPE Swift"                   # 長い刃を振り抜く金属の擦れ
RING = "Sword Ring Scrape Gleam 02"             # 刃が鳴る擦れのきらめき


def build():
    hero = "H032"
    # S1 赤拳連斬: 3 つの輪ごとに、0.08 秒前からの刃の振り（最大を輪の時刻に）+ 輪の時刻に刃の鳴り。1 つ目は強く（ダメージ 1.0）、
    # 2・3 つ目は小さく（0.3）。1 つ目の下に鉄板の低いうなり → 1.2 秒で消える
    swings = [("NormalSwings39", 1.0, 0), ("HighSwings15", 0.95, -5), ("NormalSwings39", 1.1, -5)]
    s1 = []
    for n, (part, p, g) in enumerate(swings):
        t = 0.26 + 0.2 * n
        s1 += [(t - 0.14, sn(part, p=p, g=g, hp=200, hit="peak", pre=0.14, length=0.3)),
               (t, sn("Knife_Sword_Shing", n % 2, p=0.8 + 0.05 * n, g=g - 6, hp=1200, length=0.35, hit=True, pre=0.005)),
               (t, sn(AXE, 2 * n, p=0.9, g=g - 8, length=0.3, hit=True, pre=0.005))]
    s1 += [(0.0, rise(sn(SCRAPE, p=0.8, g=-12, hp=1500, length=0.25), 0.2)),
           (0.24, rise(sn(GROAN, g=-8, lp=300, start=0.6, length=0.9), 0.06)),
           (0.26, sn(RUMBLE, g=-4, lp=150, start=3.0, length=0.8))]
    write(f"skill_{hero}_s1_cast", tail(reverb(mix(s1), 0.5, 0.1, 51), 0.95, 1.25), "cast",
          "刃の振り ×3（0.26・0.46・0.66 秒の輪）+ 刃の鳴り + 鉄の打撃 + 鉄板のうなり・地鳴り")
    # 命中: 刃が肉と鎧を斬る（斬撃の打撃・刃が肉に食い込む・体の砕け）+ 低い芯
    for k, (part, gi, p) in enumerate([("Sword Slash Impact V2", 0, 1.0), ("Melee_Sword_Attack_04", 1, 0.95),
                                        ("medium metal blade wet impact", 2, 1.05)], start=1):
        x = mix([(0, sn(part, p=p, g=0, length=0.45, hit=True, pre=0.005)),
                 (0, sn("Two-Handed Axe Flesh Hit", gi, p=0.9, g=-6, length=0.4, hit=True, pre=0.005)),
                 (0, sn("Heavy Body Crunch", 1, p=0.9, g=-8, length=0.3, hit=True, pre=0.005)),
                 (0, sn(GROAN, g=-14, lp=200, start=0.7, length=0.35))])
        write(f"skill_{hero}_s1_hit_{k}", tail(x, 0.35, 0.5), "hit", "刃が肉と鎧を斬る + 体の砕け + 鉄板の低い芯")

    # S2 紅蓮の踏込（突進）: 0 で踏み込む重い振り（低い風切り）+ 鎧と鎖の揺れ → 0〜0.4 の突進の風（亡霊の尾）+ 刃の擦れ → 鉄板のうねり
    s2 = mix([
        (0.0, sn("LowSwings31", 0, p=0.85, g=0, hp=120, hit="peak", pre=0.12, length=0.55)),
        (0.02, sn("ARMOR Body Drop Chain Leather", p=1.1, g=-8, hp=500, length=0.35, hit=True, pre=0.005)),
        (0.05, sn("DesignedSwings12", p=0.9, g=-6, hp=200, start=0.05, length=0.45)),
        (0.1, sn(RING, g=-2, hp=2000, start=0.1, length=0.45)),
        (0.0, rise(sn(GROAN, g=-6, lp=400, start=1.2, length=0.7), 0.1)),
        (0.0, sn(RUMBLE, g=-8, lp=150, start=3.0, length=0.7)),
    ])
    write(f"skill_{hero}_s2_cast", tail(reverb(s2, 0.4, 0.08, 52), 0.55, 0.8), "cast",
          "踏み込む重い振り + 鎧と鎖 → 突進の風 + 刃の擦れ → 鉄板のうねり")
    # 再使用（致命の一撃）: 0〜0.15 跳ぶ風 → 0.2〜0.45 回る刃の輪（金属の擦れの振り ×3、打撃は命中の音）→ 大きな三日月の払い → 闇の低音
    r1 = mix([
        (0.0, sn("Swing 3 Large", p=0.85, g=-2, hp=150, hit="peak", pre=0.15, length=0.3)),
        (0.18, sn(SCRAPE, p=1.0, g=0, hp=600, hit="peak", pre=0.04, length=0.35)),
        (0.33, sn(SCRAPE, p=1.1, g=-4, hp=800, hit="peak", pre=0.04, length=0.3)),
        (0.4, sn("HighSwings15", p=0.9, g=-4, hp=300, hit="peak", pre=0.06, length=0.25)),
        (0.15, sn(RING, g=-6, hp=2500, start=0.3, length=0.5)),
        (0.18, sn(AXE, 4, p=0.8, g=-8, lp=2500, length=0.4, hit=True, pre=0.005)),
        (0.15, rise(sn(GROAN, g=-4, lp=300, start=2.6, length=0.7), 0.05)),
    ])
    write(f"skill_{hero}_s2_r1_cast", tail(reverb(r1, 0.5, 0.1, 53), 0.65, 0.9), "cast",
          "跳ぶ風 → 回る刃の擦れ ×3 → 三日月の払い → 鉄板の低音")
    # 命中（突進・致命の一撃の 1〜3 撃）: 刃と鎧のぶつかり（斧と鎖の打撃・盾の金属）+ 肉を斬る + 低い芯
    for k, (ai, si, p) in enumerate([(0, 0, 1.0), (2, 2, 0.94), (4, 4, 1.06)], start=1):
        x = mix([(0, sn(AXE, ai, p=p, g=0, length=0.35, hit=True, pre=0.005)),
                 (0, sn("Metal Shield Block Hits", si, p=0.9, g=-8, lp=8000, length=0.3, hit=True, pre=0.005)),
                 (0, sn("wet stab slash and remove from flesh - hard - 1", 0, p=p, g=-6, length=0.3, hit=True, pre=0.005)),
                 (0, sn(GROAN, g=-10, lp=200, start=2.8, length=0.35))])
        write(f"skill_{hero}_s2_hit_{k}", tail(x, 0.35, 0.5), "hit", "刃と鎧のぶつかり（斧と鎖・盾の金属）+ 肉を斬る + 低い芯")

    # 奥義 奈落の一撃: 0〜0.5 鎌の振り 4 つ（0・0.1・0.24・0.4、低い風切り）と鉄板のうなり・地鳴りがふくらむ → 0.45 槍が伸びる刃の擦れ →
    # 0.76 に放つ（長い刃の振り抜き・斧と鎖の重い打撃・肉を貫く・地鳴りの山）→ 1.6 秒まで闇のうねりの尾
    sweeps = [(0.0, "LowSwings31", 0, 1.0, -6), (0.1, "DesignedSwings12", 0, 1.1, -8), (0.24, "LowSwings31", 1, 0.95, -6), (0.4, "DesignedSwings12", 0, 1.0, -6)]
    ult = mix([(t, sn(part, i, p=p, g=g, hp=150, hit="peak", pre=0.06, length=0.3)) for t, part, i, p, g in sweeps] + [
        (0.0, rise(sn(GROAN, g=-4, lp=600, start=0.2, length=0.76), 0.7)),
        (0.05, rise(sn(RUMBLE, g=-2, lp=180, start=0.4, length=0.71), 0.6)),
        (0.45, rise(sn("Sword Scrapes Multiple, Battle", 1, p=0.85, g=-6, hp=1500, length=0.31), 0.2)),
        (0.62, sn(SCRAPE, p=0.8, g=0, hp=200, hit="peak", pre=0.14, length=0.4)),
        (0.76, sn(AXE, 0, p=0.75, g=0, length=0.6, hit=True, pre=0.005)),
        (0.76, sn("wet stab slash and remove from flesh - hard - 4", 0, p=0.85, g=-4, length=0.35, hit=True, pre=0.005)),
        (0.76, sn(GROAN, g=0, lp=250, start=2.4, length=0.9, hit=True, pre=0.005)),
        (0.76, sn(RUMBLE, g=0, lp=200, start=0.4, length=0.9)),
    ])
    write(f"skill_{hero}_ult_cast", tail(reverb(ult, 0.6, 0.12, 54), 1.35, 1.65), "ult",
          "鎌の振り ×4 と闇のうねりの溜め → 槍が伸びる刃の擦れ → 0.76 秒に放つ（刃の振り抜き・斧と鎖の打撃・地鳴り）", target=-16.5)
    # 命中: 刃の槍が体を貫く（大きな刃の突き刺し・斧と鎖の打撃・体の砕け）+ 鉄板の低音
    for k, (si, ai, p) in enumerate([(0, 1, 0.9), (1, 3, 0.95), (0, 5, 0.85)], start=1):
        x = mix([(0, sn("wet stab slash and remove from flesh - hard - 4" if k != 2 else "wet stab slash and remove from flesh - hard - 1",
                        si, p=p, g=0, length=0.4, hit=True, pre=0.005)),
                 (0, sn(AXE, ai, p=0.8, g=-3, length=0.4, hit=True, pre=0.005)),
                 (0, sn("Heavy Body Crunch", 1, p=0.85, g=-6, length=0.3, hit=True, pre=0.005)),
                 (0, sn(GROAN, g=-6, lp=200, start=3.0, length=0.45))])
        write(f"skill_{hero}_ult_hit_{k}", tail(x, 0.4, 0.55), "hit", "刃の槍が体を貫く + 斧と鎖の打撃 + 体の砕け + 鉄板の低音")

    # パッシブ（レイジが 50 たまった）: 両手の刃が鳴る（刃の擦れのきらめき）+ 鉄板の低いうなり
    pas = mix([(0, sn(RING, g=6, hp=1500, start=0.0, length=0.6)),
               (0, sn("Knife_Sword_Shing", 1, p=0.75, g=0, hp=1500, length=0.35, hit=True, pre=0.005)),
               (0.0, rise(sn(GROAN, g=-16, lp=300, start=3.0, length=0.7), 0.15))])
    write(f"skill_{hero}_passive", tail(pas, 0.5, 0.75), "passive", "両手の刃が鳴る + 鉄板の低いうなり")
    return hero
