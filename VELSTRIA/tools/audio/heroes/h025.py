"""H025 ルミナ（MLBB: ミヤ）のスキル・パッシブの音（通常攻撃の音は武器ごとの組で別に作る）。

月の弓使い。弓と弦（張る・放つ）、矢の飛ぶ風、ガラス・風鈴・シンギングボウルの澄んだ響き（月光）、氷の檻（ひび・砕け・霜）。
電子音・合成の音は使わない（どの層も、その材質の録音）。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import build_audio as B  # noqa: E402,F401


# sim の時刻（Kit_H025 の LuminaTuning・FX_H025・docs/vfx/H025.md）:
#   S1 月弦分矢: 自己強化。0.04 秒に肩の閃光、0.04〜0.34 秒に青い気。発動で飛ぶ矢は無い（矢は通常攻撃のたび）。命中の音は無い（通常攻撃）。
#   S2 月蝕の矢: 0〜8/30 秒に弓を天へ引いて放つ。0.65 秒（s2Delay）に着弾（ダメージ・バインド 1.2 秒 = 命中の音）、
#               着弾の 0.33 秒後（0.98 秒）に 6 本の小さな矢が散る（当たった敵に命中の音）。
#   奥義 隠れ月光: 0 秒に姿が薄れ、0.03〜0.45 秒に頭上の三日月、0.05〜0.53 秒に光の柱が降りる。ダメージは無い。
#   パッシブ 月環の導き: 段が増えた時（3 秒止んでいた時だけ鳴る）。弓の先の小さな水色の閃き。
# 音量はロームの測定（docs/audio/MLBB_H029.md・MLBB_H034.md）を物差しに: 発動 -20.5、奥義 -19、命中 -23、パッシブ -25 LUFS。

def build():
    hero = "H025"

    # S1 月弦分矢: 0 で矢をつがえる（弦と矢の擦れ）→ 0.03 で握りの革がきしむ → 0.04 の閃光にガラスの澄んだ一打と風鈴 →
    # 0.04〜0.34 の気（布が空気をはらむ風）→ 低いボウルの響きが下で支えて 0.9 秒で消える
    s1 = mix([
        (0.0, sn("crossbow1,composite,string", 0, p=1.1, g=-6, hp=1200, length=0.32)),
        (0.02, sn("UCnS_LeatherGlove", 0, p=1.15, g=-14, hp=600, start=0.3, length=0.3)),
        (0.04, sn("Wine Glass Hit Higher", 1, p=0.9, g=-6, hit=True, length=0.7)),
        (0.05, sn("windchimes,Pacific", 0, p=0.9, g=-4, hp=2500, length=0.95)),
        (0.02, rise(sn("Whoosh,Organic,Fabric,Glove", p=0.8, g=-6, hp=300), 0.15)),
        (0.04, sn("SINGING_BOWL_Strike_Sustain_D_02", p=0.5, g=-4, lp=700, length=0.95)),
    ])
    write(f"skill_{hero}_s1_cast", tail(reverb(s1, 0.5, 0.12, 25), 0.75, 1.0), "cast",
          "矢をつがえる弦と革のきしみ → ガラスの一打と風鈴（月光）+ 布の風 + 低いボウルの響き")

    # S2: the release transient follows the authored clip/FX (16/60s); impact stays at 0.65s.
    # 0.65 着弾（矢が地に刺さる 3 つの打撃・氷のひびが走る・低い芯・ガラスの響き）→ 0.98 小さな矢が 6 方へ散る（氷の破片の風・矢の風）
    s2 = mix([
        (0.0, rise(sn("crossbow1,composite,string", 0, p=0.9, g=-8, hp=900, length=0.4), 0.2)),
        (0.05, rise(sn("wood_creaking_tree_005", 0, p=1.3, g=-12, hp=700, start=0.4, length=0.3), 0.2)),
        (0.08, sn("Leather_Creak_11", 0, p=1.2, g=-16, hp=800, start=0.5, length=0.25)),
        (8/30, sn("carbonbolt", p=0.85, g=0, hit=True, pre=0.005)),
        (8/30 + 0.01, sn("Vaeyanbow", p=1.0, g=0, hp=600, hit="peak", pre=0.12)),
        (8/30 + 0.04, sn("Vaeyanbow", p=1.2, g=-5, hp=900, hit="peak", pre=0.1)),
        (8/30 + 0.01, sn("Hawk's Arrow", p=1.3, g=-8, hp=1500, start=0.45, length=0.3)),
        (0.65, sn("BOW Arrow Hit 05", p=0.9, g=-2, hit=True, length=0.45)),
        (0.68, sn("BOW Arrow Hit 05", p=1.05, g=-7, hit=True, length=0.35)),
        (0.71, sn("BOW Arrow Hit 05", p=0.8, g=-9, hit=True, length=0.35)),
        (0.65, sn("ice_freeze_crack_04", 1, p=0.95, g=-6, hit=True)),
        (0.65, sn("10 Hit Deep Thud", p=1.2, g=-8, lp=220, length=0.35, hit=True)),
        (0.66, sn("Wine Glass Hit Higher", 0, p=0.75, g=-12, hit=True, length=0.5)),
        (0.95, sn("Glass Crystal Fragments", p=1.2, g=-10, hp=2000, start=1.15, length=0.45)),
        (0.98, sn("Vaeyanbow", p=1.4, g=-8, hp=1200, hit="peak", pre=0.04)),
        (1.0, sn("Vaeyanbow", p=1.6, g=-11, hp=1500, hit="peak", pre=0.04)),
    ])
    write(f"skill_{hero}_s2_cast", tail(reverb(s2, 0.45, 0.1, 26), 1.3, 1.6), "cast",
          "弓を引き絞る（弦・木・革）→ 弦の弾けと天へ抜ける矢 → 0.65 着弾（矢が地に刺さる・氷のひび・低い芯）→ 0.98 小さな矢が散る")
    # 命中（着弾 0.65 のバインドと、散った小さな矢）: 矢が刺さる打撃 + 氷の檻が閉じるひび + 霜の砕け + 低い芯
    for k, (ci, ice, p) in enumerate([(0, "Ice_impact_lite_02", 0.95), (1, "Ice_smash_light_02", 1.05), (2, "shatter_ice_001", 1.0)],
                                     start=1):
        x = mix([
            (0, sn("BOW Arrow Hit 05", p=0.85 + 0.07 * k, g=0, hit=True, length=0.4)),
            (0, sn(ice, p=p, g=-5, hit=True, length=0.4)),
            (0.03, sn("ice_freeze_crack_04", ci, p=1.0 + 0.05 * k, g=-9, hp=1500, length=0.45, hit=True)),
            (0.05, sn("ICE Thin Smashed Brittle Fragments 55", 0, p=1.1, g=-16, hp=3000, length=0.45, hit=True)),
            (0, sn("10 Hit Deep Thud", p=1.3, g=-12, lp=250, length=0.25, hit=True)),
        ])
        write(f"skill_{hero}_s2_hit_{k}", x, "hit", "矢が刺さる + 氷の檻のひび・砕け + 霜 + 低い芯")

    # 奥義 隠れ月光: 0 で身を翻す布の風（姿が薄れる）→ 0.03〜0.45 三日月が灯る（ボウルの打ち・ガラス・風鈴）→ 0.05〜0.53 光の柱が降りる
    # （ガラスの破片が流れ落ちる風・高い風）→ 足元の閃き（ガラスの一打 0.1）→ 加速の風が抜けて 1.6 秒で消える。下は低いボウルのうねり
    ult = mix([
        (0.0, sn("Whoosh,Organic,Fabric,Glove", p=0.75, g=-2, hp=250, hit="peak", pre=0.03)),
        (0.02, sn("SINGING_BOWL_Strike_Sustain_D_02", p=1.0, g=-4, hp=200, length=1.5)),
        (0.02, sn("SINGING_BOWL_Strike_Sustain_D_02", p=0.5, g=-3, lp=600, length=1.6)),
        (0.03, sn("windchimes,Pacific", 0, p=1.0, g=-2, hp=2500, length=1.45)),
        (0.05, sn("Glass Crystal Fragments", p=1.0, g=-6, hp=2500, start=0.9, length=0.7)),
        (0.1, sn("Wine Glass Hit Higher", 1, p=1.1, g=-6, hit=True, length=0.6)),
        (0.25, rise(sn("Airy-Whoosh Wind Gust 11", p=1.1, g=-8, hp=500, length=1.0), 0.15)),
    ])
    write(f"skill_{hero}_ult_cast", tail(reverb(ult, 0.7, 0.16, 27), 1.3, 1.65), "ult",
          "身を翻す布の風 → 三日月と光の柱（ボウル・ガラス・風鈴・ガラス片の流れ）→ 加速の風 + 低いボウルのうねり")

    # パッシブ（段が増えた）: 弓の先の小さな閃き = 弦が小さく鳴る + ガラスの小さな一打 + 風鈴のきらめき
    pas = mix([
        (0.0, sn("ZITHER String Plucks 01", p=1.5, g=-12, hp=1500, length=0.35, hit=True)),
        (0.0, sn("Wine Glass Hit Higher", 2, p=1.0, g=-4, hit=True, length=0.4)),
        (0.02, sn("windchimes,Pacific", 0, p=1.2, g=-8, hp=4000, start=0.1, length=0.5)),
    ])
    write(f"skill_{hero}_passive", tail(pas, 0.45, 0.6), "passive", "弓の先の閃き（弦の小さな鳴り + ガラスの一打 + 風鈴）")
    return hero
