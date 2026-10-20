# MARK: H033 ヴァルド（アルカード）— 大剣の剣士。大剣の重い振り（風切り・刃の擦れ）・地を割る叩きつけ（刃・岩・土）・肉を斬る音と血・吸血の吸い込み
# MLBB の録画はまだ無い。物差しはロームの測定（docs/audio/MLBB_H029.md・MLBB_H034.md）: 発動 -20.5、奥義 -16.5〜-18、命中 -23 LUFS。
# sim の時刻（Kit_H033.ValdTuning）: S1 は 1250/秒で最大 420 跳ぶ（0.34 秒）→ 着地で命中。S2 は即時の回転斬り（命中は 0 秒）。
# 奥義の 1 回目は吸収（0〜0.55 秒の演出、ダメージ無し）、再使用は 0.16 秒の振りかぶりの後に 1000/秒で 640 進む衝撃波（命中は当たった所）。
# 演出（FX_H033）: S1 の三日月は着地の 0.04 秒前、着地 0.34。S2 の回転 0.06〜0.3。奥義の吸収の渦 0.02〜0.32、再使用の三日月 0.16。
"""H033 ヴァルド（MLBB: アルカード）のスキル・パッシブの音。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import build_audio as B  # noqa: E402,F401

SCRAPE = "SWING SCRAPE Swift"                 # 長い刃を振り抜く金属の擦れ
RING = "Sword Ring Scrape Gleam 02"           # 刃が鳴る擦れのきらめき
RUMBLE = "Thunder_Rumble_Deep_Fienup_003"     # 遠い雷の深い地鳴り（低音）
SUCK = "Airy,Full,Soft,Shudder,Very Slow"     # ゆっくりした重い風（逆再生で吸い込み）
GUST = "Airy,Full,Forceful,Soft"              # 短く強い風


def build():
    hero = "H033"
    # S1 裂地撃: 0 で跳ぶ風と布の音 → 0.22〜0.32 大剣を頭上から振り下ろす擦れ → 0.34 の着地で叩きつけ
    # （刃が岩を打つ・土と岩の砕け・落ちる岩・刃の金属・低い地響き）→ 1.2 秒で消える
    s1 = mix([
        (0.0, sn(GUST, p=0.9, g=-6, hp=200, hit="peak", pre=0.08, length=0.3)),
        (0.02, sn("CLOTHING_MATERIAL_MOVEMENT_08", p=0.9, g=-12, hp=400, length=0.3)),
        (0.22, sn(SCRAPE, p=0.8, g=-2, hp=300, hit="peak", pre=0.1, length=0.3)),
        (0.34, sn("stone_impact_hammer_015", p=0.8, g=0, length=0.5, hit=True, pre=0.005)),
        (0.34, sn("Smash Rock On Debris_RBD 04", 0, p=0.9, g=-4, length=0.6, hit=True, pre=0.005)),
        (0.36, sn("GROUND IMPACT Large", 0, g=-8, length=0.8)),
        (0.34, sn("SWORD Hit Metal 02", p=0.85, g=-8, length=0.4, hit=True, pre=0.005)),
        (0.34, sn("RL_bodyfall_Dirt", p=0.7, g=-2, lp=400, length=0.4, hit=True, pre=0.005)),
        (0.34, sn(RUMBLE, g=-6, lp=150, start=3.0, length=0.7)),
    ])
    write(f"skill_{hero}_s1_cast", tail(reverb(s1, 0.5, 0.1, 61), 0.95, 1.25), "cast",
          "跳ぶ風 → 大剣の振り下ろし → 0.34 秒の叩きつけ（刃が岩を打つ・土と岩の砕け・刃の金属・地響き）")
    # 命中: 大剣が肉を斬る（斬撃・深い傷・肉の裂け）+ 血しぶき + 体の芯
    for k, (part, bi, p) in enumerate([("Beheading 02", 0, 1.0), ("Melee_Deep_Wound_05", 1, 0.95), ("Attack_Gore_Flesh_Rip_01", 0, 1.05)], start=1):
        x = mix([(0, sn(part, bi if part == "Beheading 02" else 0, p=p, g=0, length=0.4, hit=True, pre=0.005)),
                 (0, sn("Sword Slash Impact V2", p=0.85 * p, g=-6, length=0.35, hit=True, pre=0.005)),
                 (0.01, sn("Punch_Spurt Blood_Fienup_001", p=0.9 + 0.05 * k, g=-8, hit=True, pre=0.005)),
                 (0, sn("RL_bodyfall_Dirt", p=0.8, g=-10, lp=500, length=0.3, hit=True, pre=0.005))])
        write(f"skill_{hero}_s1_hit_{k}", tail(x, 0.35, 0.5), "hit", "大剣が肉を斬る + 血しぶき + 体の芯")

    # S2 旋回斬: 0.06〜0.3 に大剣が 1.6 周する（低い風切り 2 つ・刃の擦れ・刃の鳴り）+ 体をひねる重い振り → 0.6 秒で消える
    s2 = mix([
        (0.0, sn("LowSwings31", 0, p=0.95, g=0, hp=120, hit="peak", pre=0.08, length=0.3)),
        (0.12, sn("LowSwings31", 1, p=1.05, g=-3, hp=120, hit="peak", pre=0.12, length=0.3)),
        (0.04, sn(SCRAPE, p=0.9, g=-4, hp=600, hit="peak", pre=0.05, length=0.3)),
        (0.18, sn(SCRAPE, p=1.0, g=-8, hp=800, hit="peak", pre=0.05, length=0.25)),
        (0.05, sn(RING, g=-4, hp=2000, start=0.2, length=0.45)),
        (0.0, sn("Swing 3 Large", p=0.7, g=-6, lp=900, hit="peak", pre=0.1, length=0.35)),
    ])
    write(f"skill_{hero}_s2_cast", tail(reverb(s2, 0.4, 0.08, 62), 0.45, 0.65), "cast",
          "大剣の回転（低い風切り ×2・刃の擦れ・刃の鳴り）")
    for k, (part, p) in enumerate([("crunchy flesh impact and blood squirt - hard", 1.0), ("SH101_Sword Attack", 0.95),
                                    ("blood squirt wet - hard - 49", 1.05)], start=1):
        x = mix([(0, sn(part, 0, p=p, g=0, length=0.4, hit=True, pre=0.005)),
                 (0, sn("Melee_Deep_Wound_05", p=0.9 * p, g=-6, length=0.3, hit=True, pre=0.005)),
                 (0, sn("RL_bodyfall_Dirt", p=0.85, g=-10, lp=500, length=0.3, hit=True, pre=0.005))])
        write(f"skill_{hero}_s2_hit_{k}", tail(x, 0.35, 0.5), "hit", "回転する大剣が肉を斬る + 深い傷 + 体の芯")

    # 奥義（1 回目）吸収: 0〜0.5 帯の中の力が術者へ吸い込まれる（重い風の逆再生）+ 大剣を掲げる刃の鳴り + 血を吸う湿った音 +
    # ふくらむ地鳴り → 0.5 で吸い込みが体に収まる → 1.0 秒で消える
    suck = rev(sn(SUCK, g=0, start=0.15, length=0.5))
    ult = mix([
        (0.0, rise(suck, 0.3)),
        (0.02, sn(RING, g=-2, hp=1500, length=0.7)),
        (0.08, sn("Just Gore _ Add On/Blood-Squeeze_Drip_045", p=0.9, g=-6, hp=200, length=0.45)),
        (0.0, rise(sn(RUMBLE, g=-2, lp=180, start=3.0, length=0.65), 0.45)),
        (0.48, sn("Body Hits - Deep Punch 02", p=0.7, g=-10, lp=800, hit=True, pre=0.005)),
    ])
    write(f"skill_{hero}_ult_cast", tail(reverb(ult, 0.6, 0.12, 63), 0.75, 1.0), "ult",
          "吸い込み（重い風の逆再生）+ 大剣の鳴り + 血を吸う音 + 地鳴り → 体に収まる", target=-18.5)
    # 再使用（衝撃波）: 0〜0.16 大剣を水平に振りかぶる重い風 → 0.16 振り抜き（刃の擦れ・低い打ち）→ 0.18〜0.8 前へ走る衝撃波の風と地鳴り
    r1 = mix([
        (0.0, sn("Swing 3 Large", p=0.8, g=-2, hp=120, hit="peak", pre=0.14, length=0.3)),
        (0.14, sn(SCRAPE, p=0.75, g=0, hp=200, hit="peak", pre=0.02, length=0.45)),
        (0.16, sn(RING, g=-6, hp=1500, start=0.5, length=0.6)),
        (0.16, sn("RL_bodyfall_Dirt", p=0.6, g=-4, lp=300, length=0.4, hit=True, pre=0.005)),
        (0.18, rise(sn("Airy-Whoosh Wind Gust 11", p=0.85, g=-2, hp=150, start=0.5, length=0.65), 0.05)),
        (0.2, sn(SUCK, p=0.9, g=-6, hp=200, start=0.3, length=0.6)),
        (0.16, sn(RUMBLE, g=-4, lp=180, start=3.5, length=0.8)),
    ])
    write(f"skill_{hero}_ult_r1_cast", tail(reverb(r1, 0.6, 0.12, 64), 0.9, 1.2), "ult",
          "大剣の振りかぶり → 0.16 秒の振り抜き（刃の擦れ・低い打ち）→ 走る衝撃波の風と地鳴り", target=-16.5)
    # 命中（衝撃波）: 大剣の斬撃が肉を裂く + 血しぶき + 体の芯 → 0.05〜0.35 血が術者へ戻る吸い込み（吸血）
    for k, (part, p) in enumerate([("blood squirt wet - hard - 49", 0.9), ("Beheading 02", 0.88), ("crunchy flesh impact and blood squirt - hard", 0.92)], start=1):
        back = rise(rev(sn(GUST, p=1.1, g=-8, hp=600, start=0.2, length=0.3)), 0.2)
        x = mix([(0, sn(part, 1 if part == "Beheading 02" else 0, p=p, g=0, length=0.4, hit=True, pre=0.005)),
                 (0, sn(SCRAPE, p=0.9, g=-8, hp=1000, hit="peak", pre=0.01, length=0.25)),
                 (0, sn("RL_bodyfall_Dirt", p=0.75, g=-8, lp=500, length=0.3, hit=True, pre=0.005)),
                 (0.05, back)])
        write(f"skill_{hero}_ult_hit_{k}", tail(x, 0.4, 0.55), "hit", "大剣の斬撃が肉を裂く + 血しぶき + 体の芯 → 吸血の吸い込み")

    # パッシブ（追撃の準備。スキルの発動のたび）: 大剣の小さな刃の鳴り（スキルの音に重なるので小さく短く）
    pas = mix([(0, sn(RING, g=0, hp=2500, start=0.3, length=0.35)),
               (0, sn("Knife_Sword_Shing", 0, p=1.2, g=-8, hp=2500, length=0.25, hit=True, pre=0.005))])
    write(f"skill_{hero}_passive", tail(pas, 0.25, 0.4), "passive", "大剣の小さな刃の鳴り", target=-27.0)
    return hero
