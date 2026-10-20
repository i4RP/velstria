"""H028 ザイル（MLBB: セイバー）のスキル・パッシブの音（通常攻撃の音は武器ごとの組で別に作る）。

飛ぶ剣の暗殺者。刃が空を切る風（剣・ナイフの振り）、鋼の鳴り（抜く・弾く・刃のきらめき）、肉と鎧を断つ斬撃、回る剣の風切り。
電子音・合成の音は使わない（どの層も、その材質の録音）。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import build_audio as B  # noqa: E402,F401


# sim の時刻（Kit_H028 の Tune・FX_H028・docs/vfx/H028.md）:
#   S1 環剣: 0〜0.2 秒に剣を体の周りで一回し、0.2 秒に 5 本の剣が飛び出し、0.47 秒（pulseFirst）に輪に着いて 4.8 秒回る。
#            輪の接触ダメージは 0.47 秒から 0.48 秒おき、剣撃（通常攻撃・スキルの命中の 0.1 秒後）も S1 の命中の音。
#   S2 断空突進: 3m を 0.2 秒で駆け、通り道の敵に命中の音。着いたら刃に赤い光（次の通常攻撃の強化）。
#   奥義 三連断空: 対象へ突進（動画 0.14〜0.19 秒。演出は 0.2 秒に置く）→ 到着の瞬間・+0.39・+0.78 秒に 3 連撃（命中の音。3 撃目が重い）。
#                 演出の斬撃は 0.2 / 0.59 / 0.98 秒。
#   パッシブ 空断の理: 防御ダウンの層が増えた時（3 秒止んでいた時だけ鳴る）。visor の瞬きと胸の前の細い斬線。
# 音量はロームの測定（docs/audio/MLBB_H029.md・MLBB_H034.md）を物差しに: 発動 -20.5、命中 -23。奥義は 3 連の斬撃で畳みかけるので
# 発動 -18・命中 -20。

CLOTH = "Just Whoosh 3 _ Whoosh Essentials/Whoosh_Cloth_Leather_Fight_174"


def build():
    hero = "H028"

    # S1 環剣: 0〜0.2 剣を体の周りで一回し（長い刃の振り・体の風）→ 0.2 剣が 5 本飛び出す（抜く鋼の鳴り・ばねの弾け・短い刃の風 3 つ）→
    # 0.47 輪に着く鋼の鳴り → 0.5〜1.5 回る剣の風切りが続いて薄れる
    whirl = [(0.5 + 0.16 * i, sn("metal knife swing - 4", p=1.0 + 0.06 * (i % 2), g=4 - 1.5 * i, hp=300, hit="peak", pre=0.04))
             for i in range(7)]
    s1 = mix([
        (0.02, sn("SWING SCRAPE Swift Melee", p=1.0, g=0, hit="peak", pre=0.08)),
        (0.0, sn(CLOTH, p=0.9, g=-8, hp=250, hit="peak", pre=0.1)),
        (0.2, sn("Knife_Sword_Shing", 0, p=1.05, g=-2, hit=True)),
        (0.2, sn("Switchblades,OTF", p=0.9, g=-4, hit=True, length=0.3)),
        (0.21, sn("whoosh_weapon_knife_swing_04", 0, p=1.2, g=-6, hit="peak", pre=0.02)),
        (0.25, sn("whoosh_weapon_knife_swing_04", 0, p=1.35, g=-8, hit="peak", pre=0.02)),
        (0.29, sn("whoosh_weapon_knife_swing_04", 0, p=1.5, g=-10, hit="peak", pre=0.02)),
        (0.47, sn("large metal knife ring - 8", p=0.9, g=-4, hp=1500, hit=True, length=0.6)),
    ] + whirl)
    write(f"skill_{hero}_s1_cast", tail(reverb(s1, 0.4, 0.1, 41), 1.3, 1.6), "cast",
          "剣を一回し（長い刃の振り・体の風）→ 0.2 剣が飛び出す（抜く鋼・ばね・刃の風）→ 0.47 輪に着く鋼の鳴り → 回る剣の風切り", cap=1.6)
    # 命中（輪の接触・剣撃）: 刃が抜ける風 + 鋼の打ち + 肉を断つ + 鎧の鋼 + 体への芯
    for k, hi in enumerate([0, 1, 2], start=1):
        x = mix([
            (0, sn("whoosh_weapon_knife_swing_04", 0, p=1.1 + 0.08 * k, g=-6, hit="peak", pre=0.01)),
            (0, sn("Knife_Sword_Hit_Multiple", hi, p=0.95, g=0, hit=True, length=0.25)),
            (0.005, sn("medium metal blade wet impact in to flesh", p=0.9 + 0.07 * k, g=-3, hit=True, length=0.3)),
            (0.01, sn("SWORD Hit Metal 02", p=1.0 + 0.05 * k, g=-12, hp=1500, hit=True, length=0.3)),
            (0, sn("Body Hits - Deep Punch 02", p=1.1, g=-10, hit=True)),
        ])
        write(f"skill_{hero}_s1_hit_{k}", x, "hit", "刃が抜ける風 + 鋼の打ち + 肉を断つ + 鎧の鋼 + 体への芯")

    # S2 断空突進: 0 で踏み込む（土の足音）→ 0〜0.2 駆ける体の風と刃が滑る風 → 0.2 刃に光が宿る（抜き身の鋼の鳴り・刃のきらめき）
    s2 = mix([
        (0.0, sn("PM_SDNG_Single_Step_Footstep_46", p=0.9, g=-4, hit=True)),
        (0.0, sn(CLOTH, p=1.15, g=-2, hp=300, hit="peak", pre=0.1)),
        (0.02, sn("Sword Slide Swish", p=1.1, g=0, hp=400, length=0.35)),
        (0.2, sn("Knife_Sword_Shing", 1, p=1.0, g=-4, hit=True, length=0.6)),
        (0.2, sn("Sword Ring Scrape Gleam", p=1.0, g=-10, hp=3000, start=0.6, length=0.6)),
    ])
    write(f"skill_{hero}_s2_cast", tail(s2, 0.7, 0.9), "cast", "踏み込み → 駆ける体の風・刃が滑る風 → 0.2 刃に宿る鋼の鳴り")
    # 命中（通り道で斬る）: 振り抜く刃の斬撃 + 肉を断つ + 鋼の擦れ + 体への芯
    for k, si in enumerate([0, 2, 1], start=1):
        x = mix([
            (0, sn("Sword Slash Impact V2 Assorted 18", p=0.95 + 0.05 * k, g=0, hit="peak", pre=0.01, length=0.4)),
            (0.005, sn("medium metal blade wet impact in to flesh", p=0.85 + 0.06 * k, g=-4, hit=True, length=0.3)),
            (0.01, sn("Sword Scrapes Multiple, Battle", si, p=1.0, g=-12, hp=2000, hit=True, length=0.3)),
            (0, sn("Body Hits - Deep Punch 02", p=1.0, g=-10, hit=True)),
        ])
        write(f"skill_{hero}_s2_hit_{k}", x, "hit", "振り抜く刃の斬撃 + 肉を断つ + 鋼の擦れ + 体への芯")

    # 奥義 三連断空: 0〜0.2 突進（体の風・長い刃が滑る風）→ 0.2 一撃目の振り（剣の斬撃・刃と鋼の擦れ）→ 0.59 二撃目（逆の振り）→
    # 0.98 三撃目（重い振り・長い刃の振り・鋼の擦れ・刃の鳴り・低い芯）→ 1.6 秒で消える。打撃の芯は命中の音（1 撃ごと）
    ult = mix([
        (0.0, sn(CLOTH, p=1.2, g=-4, hp=300, hit="peak", pre=0.12)),
        (0.0, sn("SWING SCRAPE Swift Melee", p=1.15, g=-6, hit="peak", pre=0.15)),
        (0.2, sn("SH101_Sword Attack", p=1.0, g=0, hit="peak", pre=0.03)),
        (0.2, sn("Sword Slide Cuts, Metallic", 2, p=1.0, g=-6, hit=True, length=0.35)),
        (0.53, sn("SWING SCRAPE Swift Melee", p=1.1, g=-2, hit="peak", pre=0.06)),
        (0.58, sn("Sword Slash Impact V2 Assorted 18", p=1.05, g=-4, hit="peak", pre=0.01, length=0.4)),
        (0.59, sn("Sword Slide Cuts, Metallic", 3, p=1.1, g=-6, hit=True, length=0.35)),
        (0.9, sn("LowSwings31", 0, p=0.9, g=-1, hp=150, hit="peak", pre=0.08, length=0.3)),
        (0.9, sn("SWING SCRAPE Swift Melee", p=0.85, g=-2, hit="peak", pre=0.08)),
        (0.98, sn("Sword Slide Cuts, Metallic", 4, p=0.9, g=-3, hit=True, length=0.4)),
        (0.98, sn("large metal knife ring - 8", p=0.8, g=-6, hp=1200, hit=True, length=0.6)),
        (0.98, sn("10 Hit Deep Thud", p=1.0, g=-4, lp=220, hit=True, length=0.4)),
    ])
    write(f"skill_{hero}_ult_cast", tail(reverb(ult, 0.45, 0.1, 42), 1.35, 1.65), "ult",
          "突進の風 → 0.2・0.59 の斬撃（剣の振り・鋼の擦れ）→ 0.98 重い三撃目（重い振り・鋼・刃の鳴り・低い芯）", target=-18.0, cap=1.7)
    # 命中（3 連撃）: 重い刃が肉と鎧を断つ（深い斬り・鋼の打ち・体の砕け）+ 低い芯
    for k, (stab, hi) in enumerate([("slash and remove from flesh - hard - 1", 0), ("slash and remove from flesh - hard - 4", 2),
                                    ("slash and remove from flesh - medium - 14", 1)], start=1):
        x = mix([
            (0, sn(stab, p=0.85 + 0.04 * k, g=0, hit=True, length=0.4)),
            (0, sn("Knife_Sword_Hit_Multiple", hi, p=0.85, g=-3, hit=True, length=0.25)),
            (0.005, sn("SWORD Hit Metal 02", p=0.9 + 0.05 * k, g=-6, hit=True, length=0.4)),
            (0.01, sn("Heavy Body Crunch", 0, p=0.95, g=-12, hit=True, length=0.3)),
            (0, sn("Body Hits - Deep Punch 02", p=0.8, g=-4, hit=True)),
        ])
        write(f"skill_{hero}_ult_hit_{k}", x, "hit", "重い刃が肉と鎧を断つ（深い斬り・鋼・体の砕け）+ 低い芯", target=-20.0)

    # パッシブ（防御ダウンの層）: 細い斬線 = 刃の小さな弾けと鋼の鳴り
    pas = mix([(0, sn("Switchblades,OTF", p=1.1, g=0, hit=True, length=0.25)),
               (0.01, sn("large metal knife ring - 8", p=1.2, g=-8, hp=3000, hit=True, length=0.35)),
               (0.0, sn("whoosh_weapon_knife_swing_04", 0, p=1.6, g=-14, hp=1500, hit="peak", pre=0.02))])
    write(f"skill_{hero}_passive", tail(pas, 0.3, 0.45), "passive", "細い斬線（刃の小さな弾け + 鋼の鳴り）")
    return hero
