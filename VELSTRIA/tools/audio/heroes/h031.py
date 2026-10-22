# MARK: H031 オーリア（オーロラ）— 氷の魔法使い。本物の氷の録音: ひび・割れ・砕け・氷塊の着弾・氷河のきしみ・ドライアイスの霜の音
# MLBB の録画はまだ無い。物差しはロームの測定（docs/audio/MLBB_H029.md・MLBB_H034.md）: 発動 -20.5、奥義 -16、命中 -23 LUFS。
# sim の時刻（Kit_H031.Tune）: S1 は 0.56 秒に隕石が落ち、0.47 秒後から 0.15 秒おきに雹 5 つ（1.03〜1.63 秒。雹も S1 の命中）。
# S2 は 0.56 秒に扇の命中、0.76 秒に凍った地面（0.13 秒おきに 3 回）。奥義は 0.26 秒に霜の道、1.49 秒に氷河が砕ける（どちらも奥義の命中）。
# 演出（FX_H031）: S1 の刃が寄る 0.06〜0.28・落下 0.33・着弾 0.57。S2 の払い 0.2・霜風 0.3〜0.57・凍った地面 0.77。奥義の道 0.27・氷河 0.27〜1.5。
"""H031 オーリア（MLBB: オーロラ）のスキル・パッシブの音。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import build_audio as B  # noqa: E402,F401

DRYICE = "dry ice sizzle - serrated"              # ドライアイスに熱い刃を当てた霜の音（しゅうしゅう・きしみ）
FREEZE = "ice_freeze_crack_04"                     # 凍りつく氷のひび
SIZZLE = "ICEMisc_Ice Sizzle_05"                   # 氷のしゅわしゅわ（霜の床）
FISSURE = "ice, surface cracking, fissure, fast"   # 氷の面を走るひび
BIG = "Ice,Impact,Large,Slide_18"                  # 大きな氷塊の着弾（低音と砕け）
BERG = "Iceberg,Designed,Impact,Crack,Shatter,Huge_08"   # 氷山の割れ（氷の録音を重ねた素材。0.1 秒に低い芯）


def build():
    hero = "H031"
    # S1 雪華の烈風: 0〜0.3 霜が集まる（ドライアイスのきしみ・氷のきしみ）→ 0.33〜0.56 氷塊が落ちる風（氷の欠片の風切り）→
    # 0.56 の着弾（大きな氷塊・砕けた氷の飛び散り・ひび・氷山の低音）→ 1.03〜1.63 の雹 5 つ（小さな氷の砕け）→ 霜の床のしゅわしゅわ
    hails = [("Ice_smash_light_02", 0, 1.1), ("Ice_impact_lite_02", 0, 1.0), ("thick ice hits impacts debris bright 03", 0, 1.05),
             ("Ice_impact_lite_02", 0, 0.92), ("thick ice hits impacts debris bright 03", 2, 1.0)]
    s1 = mix([
        (0.0, rise(sn(DRYICE, g=0, hp=1500, start=0.3, length=0.4), 0.25)),
        (0.06, sn("thin ice creaks", 0, p=1.1, g=-2, hp=1500, length=0.3)),
        (0.33, rise(sn("MAGIC ICE Whoosh", p=1.1, g=-4, hp=300, hit="peak", pre=0.23, length=0.3), 0.15)),
        (0.56, sn(BIG, g=0, length=1.0, hit=True, pre=0.005)),
        (0.56, sn("KETTLEBELL SMASH DEBRIS 02", 0, p=1.05, g=-4, length=0.6, hit=True, pre=0.005)),
        (0.6, sn("Bluezone_BC0278_ice_crack_break_002", 0, g=-10, hp=1200, start=0.1, length=0.6)),
        (0.56, sn(BERG, 0, g=-8, lp=200, length=0.7, hit=True, pre=0.005)),
        (0.7, sn(SIZZLE, g=-18, hp=2500, start=1.0, length=1.2)),
    ] + [(1.03 + 0.15 * n, sn(part, i, p=p, g=-10, hp=800, length=0.25, hit=True, pre=0.005)) for n, (part, i, p) in enumerate(hails)])
    write(f"skill_{hero}_s1_cast", tail(reverb(s1, 0.5, 0.1, 41), 1.75, 2.0), "cast",
          "霜が集まる → 落ちる氷塊の風 → 0.56 秒の着弾（氷塊・砕け・ひび・低音）→ 雹 5 つの砕け → 霜の床")
    # 命中（隕石・雹）: 氷の塊が体に当たって砕ける + 体の鈍い芯 + 凍りつくひび
    for k, (part, ci, p) in enumerate([("Ice_chunk_heavy_07", 1, 1.0), ("Ice_Impact_Debris_Heavy_Single_Fienup_015", 2, 0.95),
                                        ("BIG CHISEL HIT DEBRIS 06", 1, 1.05)], start=1):
        x = mix([(0, sn(part, 0, p=p, g=0, length=0.5, hit=True, pre=0.005)),
                 (0, sn("punch_general_body_impact_03", p=0.8, g=-8, lp=1800, hit=True, pre=0.005)),
                 (0.03, sn(FREEZE, ci, p=1.0, g=-10, hp=1500, length=0.35))])
        write(f"skill_{hero}_s1_hit_{k}", tail(x, 0.4, 0.55), "hit", "氷の塊が体に当たって砕ける + 体の芯 + 凍りつくひび")

    # S2 氷花のそよ風: 0〜0.2 手で払う霜の音 → 0.2〜0.56 冷たい突風（風の塊・氷の欠片の風・霜のしゅわしゅわ）→ 0.56 扇の先で凍りつく
    # （凍るひび・薄い氷の割れ）→ 0.76 地面が凍る（氷の面を走るひび・割れ）→ 1.4 秒で消える
    s2 = mix([
        (0.0, rise(sn(DRYICE, g=-10, hp=2000, start=1.0, length=0.3), 0.2)),
        (0.15, rise(sn("Airy-Whoosh Wind Gust 11", p=1.15, g=0, hp=250, hit="peak", pre=0.3, length=0.55), 0.2)),
        (0.2, rise(sn("MAGIC ICE Whoosh", p=1.25, g=-8, hp=500, start=0.1, length=0.45), 0.1)),
        (0.25, sn(SIZZLE, g=-14, hp=2500, start=3.0, length=0.6)),
        (0.56, sn(FREEZE, 1, g=4, length=0.6, hit=True, pre=0.005)),
        (0.58, sn("thin ice cracks crunchy 06", 4, g=-6, hp=600, length=0.45)),
        (0.76, sn(FISSURE, g=-9, length=0.65, hit=True, pre=0.005)),
        (0.76, sn("Bluezone_BC0278_ice_crack_break_189", 0, g=-10, length=0.6, hit=True, pre=0.005)),
        (0.56, sn("glacier_huge_shift_01", g=-8, lp=400, start=7.6, length=0.7)),
    ])
    write(f"skill_{hero}_s2_cast", tail(reverb(s2, 0.5, 0.1, 42), 1.15, 1.45), "cast",
          "払う霜 → 冷たい突風 → 0.56 秒に凍りつくひび → 0.76 秒に地面が凍る割れ")
    # 命中（扇・凍った地面）: 体が凍りつく（凍るひび・氷の砕け・体の芯）
    for k, (ci, part, p) in enumerate([(1, "Ice_smash_light_02", 1.0), (2, "Ice_impact_lite_02", 0.94), (0, "Ice_smash_light_02", 0.9)], start=1):
        x = mix([(0, sn(FREEZE, ci, p=p, g=0, length=0.5, hit=True, pre=0.005)),
                 (0, sn(part, 0, p=p, g=-4, length=0.35, hit=True, pre=0.005)),
                 (0, sn("punch_general_body_impact_03", p=0.75, g=-10, lp=1500, hit=True, pre=0.005))])
        write(f"skill_{hero}_s2_hit_{k}", tail(x, 0.4, 0.55), "hit", "体が凍りつく（凍るひび・氷の砕け・体の芯）")

    # 奥義 凍てつく氷結: 0〜0.26 霜が集まる → 0.26 霜の道（氷の面を走るひび）→ 0.3〜1.49 氷河が育つ（氷河のきしみ・氷の割れの連なり・
    # 霜のしゅわしゅわがふくらむ）→ 1.49 氷河が砕ける（氷山の割れの低い芯・大きな氷塊・氷の塊を砕く・砕けた氷の飛び散り）→ 2.5 秒まで氷の欠片
    ult = mix([
        (0.0, rise(sn(DRYICE, g=-8, hp=1200, start=0.2, length=0.3), 0.22)),
        (0.26, sn(FISSURE, g=-6, length=0.7, hit=True, pre=0.005)),
        (0.26, sn("Ice_impact_lite_02", 0, p=0.9, g=-6, hit=True, pre=0.005)),
        (0.3, rise(sn("glacier_huge_shift_01", g=-5, start=6.2, length=1.22), 0.9)),
        (0.45, rise(sn("thin ice creaks", 1, p=0.85, g=-4, hp=400, length=1.05), 0.5)),
        (0.6, rise(sn(SIZZLE, g=-10, hp=2000, start=4.0, length=0.89), 0.8)),
        (1.49, sn(BERG, 0, g=0, length=1.1, hit="peak", pre=0.01)),
        (1.49, sn(BIG, g=0, length=1.0, hit=True, pre=0.005)),
        (1.49, sn(BIG, p=0.75, g=-2, hp=100, length=0.8, hit=True, pre=0.005)),
        (1.49, sn("ice, block of ice crushed, heavy", g=0, start=0.2, length=0.8)),
        (1.5, sn("KETTLEBELL SMASH DEBRIS 02", 0, p=0.9, g=-4, length=0.7, hit=True, pre=0.005)),
        (1.6, sn("Bluezone_BC0278_ice_crack_break_002", 1, g=-10, hp=800, length=0.8)),
    ])
    write(f"skill_{hero}_ult_cast", tail(reverb(ult, 0.7, 0.12, 43), 2.2, 2.55), "ult",
          "霜が集まる → 0.26 秒の霜の道のひび → 氷河が育つきしみ → 1.49 秒に氷河が砕ける（氷山・氷塊・砕け）", target=-16.0, cap=2.6)
    # 命中（霜の道・氷河の砕け）: 大きな氷の塊が体を打つ + 氷の割れ + 体の芯
    for k, (part, ci, p) in enumerate([("Ice_Impact_Debris_Heavy_Single_Fienup_015", 1, 0.9), ("BIG CHISEL HIT DEBRIS 06", 2, 0.95),
                                        ("Ice_chunk_heavy_07", 1, 0.88)], start=1):
        x = mix([(0, sn(part, 0, p=p, g=0, length=0.55, hit=True, pre=0.005)),
                 (0, sn(BIG, p=1.1, g=-8, length=0.4, hit=True, pre=0.005)),
                 (0, sn("punch_general_body_impact_03", p=0.7, g=-8, lp=1500, hit=True, pre=0.005)),
                 (0.03, sn(FREEZE, ci, g=-10, hp=1500, length=0.4))])
        write(f"skill_{hero}_ult_hit_{k}", tail(x, 0.45, 0.6), "hit", "大きな氷の塊が体を打つ + 氷の割れ + 体の芯")

    # パッシブ 氷の誇り（凍りつく）: 凍りつくひび + ドライアイスの霜 + 氷のきしみ
    pas = mix([(0, sn(FREEZE, 2, g=0, length=1.0, hit=True, pre=0.005)),
               (0, rise(sn(DRYICE, g=-8, hp=1500, start=1.4, length=0.9), 0.1)),
               (0.1, sn("thin ice creaks", 2, g=-8, hp=800, length=0.8))])
    write(f"skill_{hero}_passive", tail(pas, 0.85, 1.15), "passive", "凍りつくひび + 霜 + 氷のきしみ", target=-23.0)
    return hero
