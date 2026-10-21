"""H027 ジャルド（MLBB: 子龍）のスキル・パッシブ・強化通常攻撃（三連突き）の音（ふつうの通常攻撃の音は武器ごとの組で別に作る）。

竜の槍。長い柄が空を切る風（棒・竿の振り）、穂先の鋼の鳴り、肉と鎧を貫く突き、蹴り出しの土、背後へ叩きつける体の落下、
奥義は渦を巻く風と太鼓の一打。電子音・合成の音は使わない（どの層も、その材質の録音）。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import build_audio as B  # noqa: E402,F401


# sim の時刻（Kit_H027 の Tune・FX_H027・docs/vfx/H027.md）:
#   S1 跳槍撃: 発動と同じ tick に命中（ダメージ = 命中の音、打ち上げ 1.0 秒）。0〜0.4 秒は槍で掲げたまま、0.4 秒（flipHold）で
#              頭上を越えて背後へ放り投げ、0.2 秒（flipFlight）で 0.6 秒に背後へ着地。
#   S2 竜牙突き: 0 秒に蹴り出して毎秒 1520 で突進（最大 450 → 約 0.2〜0.3 秒。動画では 0.23 秒）。到着の tick に命中の音。
#   奥義 至高の武人: 自己強化 7.5 秒。0 秒に白い風の渦、0.03〜0.1 秒に黄緑の渦、0.13〜0.2 秒に胸の光、0.27〜0.5 秒に水色の泡。ダメージは無い。
#   パッシブ 竜の三連突き: 竜気がたまった時（3 秒止んでいた時だけ鳴る）の穂先の小さな閃き。
#   強化通常攻撃（三連突き）: 通常攻撃 1 回が速い 3 突きになる。命中は 0・0.133・0.267 秒（30 Hz の 4 tick おき）。
#              1 撃目の命中に atkx（3 突きの風）を 1 回、3 撃とも命中ごとに atkxhit（刺さり）を鳴らす。
# 音量はロームの測定（docs/audio/MLBB_H029.md・MLBB_H034.md）を物差しに: 発動 -20.5、奥義 -19、命中 -23、パッシブ -25 LUFS。
# 強化通常攻撃は通常攻撃（-23 / 命中 -27）より大きく: atkx -21、atkxhit -24 LUFS。

# 同じ名前のファイルが目録に 2 つある（素材集のフォルダ名の違い）ので、フォルダから指す
ROD = "Just Whoosh 3 _ Whoosh Essentials/Whoosh_Rod_Pole_022"
CLOTH = "Just Whoosh 3 _ Whoosh Essentials/Whoosh_Cloth_Leather_Fight_174"
BROOM = "broom long stick slow and long swings"  # 長い棒（箒の柄）を振る録音（テイク 25 本）


def build():
    hero = "H027"

    # S1 跳槍撃: 0 で槍が足元を低く掬う（柄の風 + 穂先の鋼の鳴り）→ 0.05〜0.4 掲げたまま（柄が擦れる・鎧が鳴る）→
    # 0.4 頭上を越えて放る大きな振り（重い振り・竿の風・体が空を切る風）→ 0.6 背後へ叩きつける（体の落下・鎧・土・低い芯）
    s1 = mix([
        (0.0, sn(ROD, p=0.9, g=-2, hp=150, hit="peak", pre=0.015, length=0.3)),
        (0.0, sn("Sword Ring Scrape Gleam", p=0.9, g=-8, hp=2500, start=0.6, length=0.45)),
        (0.08, sn("STICK-07 - SLIDE", p=0.9, g=-10, hp=300, length=0.3)),
        (0.12, sn("ARMOR Body Drop Chain", 0, p=1.2, g=-16, hp=1500, length=0.25)),
        (0.4, sn("LowSwings31", 0, p=0.95, g=0, hp=120, hit="peak", pre=0.08, length=0.3)),
        (0.4, sn("Fishing Pole_Full", 1, p=0.8, g=-6, hp=600, hit="peak", pre=0.06)),
        (0.42, sn("Whoosh,Organic,Fabric,Glove", p=0.7, g=-8, hp=200, hit="peak", pre=0.04)),
        (0.6, sn("RL_bodyfall_Dirt", p=0.95, g=0, hit=True, length=0.35)),
        (0.6, sn("ARMOR Body Drop Chain", 0, p=0.9, g=-6, hit=True, length=0.3)),
        (0.6, sn("10 Hit Deep Thud", p=1.1, g=-6, lp=220, hit=True, length=0.35)),
    ])
    write(f"skill_{hero}_s1_cast", tail(reverb(s1, 0.35, 0.08, 31), 0.85, 1.05), "cast",
          "槍が足元を掬う（柄の風・穂先の鋼）→ 掲げる（柄の擦れ・鎧）→ 0.4 頭上を越える大きな振り → 0.6 背後へ叩きつける（体の落下・鎧・土・低音）")
    # 命中（0 秒 = 発動と同じ）: 穂先が肉に食い込む + 柄の木の打撃 + 鋼の鳴り + 体への打撃 + 低い芯
    for k, (si, mi) in enumerate([(0, 0), (1, 1), (3, 2)], start=1):
        x = mix([
            (0, sn("slash and remove from flesh - medium - 14", p=0.9 + 0.06 * k, g=0, hit=True, length=0.25)),
            (0, sn("Spear And Stick Impact", si, p=0.95, g=-4, hit=True, length=0.25)),
            (0.005, sn("Machete_Hit_Ring", mi, p=0.8 + 0.05 * k, g=-12, hp=2000, hit=True, length=0.3)),
            (0, sn("Body Hits - Deep Punch 02", p=0.85 + 0.05 * k, g=-4, hit=True)),
            (0, sn("10 Hit Deep Thud", p=1.25, g=-12, lp=220, length=0.25, hit=True)),
        ])
        write(f"skill_{hero}_s1_hit_{k}", x, "hit", "穂先が肉に食い込む + 柄の木の打撃 + 鋼の鳴り + 体への打撃 + 低い芯")

    # S2 竜牙突き: 0 で地を蹴る（土の踏み込み・鎧の揺れ）→ 0〜0.2 槍を構えて駆ける突きの風（速い振り・柄の風）+ 穂先の鋼のきらめき →
    # 到着の打撃は命中の音
    s2 = mix([
        (0.0, sn("PM_SDNG_Single_Step_Footstep_19", p=0.85, g=-2, hit=True)),
        (0.0, sn("ARMOR Body Drop Chain", 0, p=1.1, g=-12, hp=1000, hit=True, length=0.25)),
        (0.02, sn(CLOTH, p=1.1, g=-8, hp=300, hit="peak", pre=0.1)),
        (0.04, sn("NormalSwings39", p=0.9, g=0, hp=200, hit="peak", pre=0.16)),
        (0.1, sn(ROD, p=1.2, g=-6, hp=400, hit="peak", pre=0.1, length=0.3)),
        (0.02, sn("Sword Ring Scrape Gleam", p=1.0, g=-10, hp=3000, start=1.4, length=0.4)),
    ])
    write(f"skill_{hero}_s2_cast", tail(s2, 0.42, 0.6), "cast", "地を蹴る（土・鎧）→ 駆ける突きの風（速い振り・柄の風）+ 穂先の鋼のきらめき")
    # 命中（到着）: 槍が肉と鎧を貫く（刃が深く刺さる・鋼の鳴り・木の柄）+ 体への打撃 + 低い芯
    for k, (stab, mi) in enumerate([("slash and remove from flesh - hard - 1", 0), ("slash and remove from flesh - hard - 4", 1),
                                    ("slash and remove from flesh - medium - 14", 2)], start=1):
        x = mix([
            (0, sn(stab, p=0.92 + 0.04 * k, g=0, hit=True, length=0.35)),
            (0, sn("GORE Impact stab dagger", (0, 2, 0)[k - 1], p=0.8, g=-6, hit=True, length=0.15)),
            (0.003, sn("Machete_Hit_Ring", mi, p=0.75 + 0.05 * k, g=-9, hp=1500, hit=True, length=0.35)),
            (0, sn("Spear And Stick Impact", 3 + (k % 2), p=0.85, g=-8, hit=True, length=0.2)),
            (0, sn("Body Hits - Deep Punch 02", p=0.8, g=-3, hit=True)),
        ])
        write(f"skill_{hero}_s2_hit_{k}", x, "hit", "槍が肉と鎧を貫く（深い刺し・鋼の鳴り・柄）+ 体への打撃・低い芯")

    # 奥義 至高の武人: 0 で太鼓の一打（低音の芯）と白い風が渦を巻く（大きな風の渦）→ 0.05〜0.35 槍を頭上で回す（柄の風 3 回）→
    # 0.13〜0.5 気が膨らむ風（長い突風）+ 穂先の鋼の鳴り → 1.6 秒で消える
    ult = mix([
        (0.0, sn("03 Hit Big Drum", p=0.9, g=-9, hit=True, length=0.7)),
        (0.0, sn("MAGIC AIR Large Whoosh", p=1.0, g=0, hp=150, start=0.3, length=1.4)),
        (0.08, sn(ROD, p=1.0, g=-3, hp=250, hit="peak", pre=0.06, length=0.3)),
        (0.2, sn(ROD, p=1.1, g=-4, hp=300, hit="peak", pre=0.06, length=0.3)),
        (0.32, sn(ROD, p=1.2, g=-5, hp=350, hit="peak", pre=0.06, length=0.3)),
        (0.12, rise(sn("Wind, Rush, Whoosh", p=0.9, g=2, hp=400, length=0.9), 0.2)),
        (0.3, sn("Sword Ring Scrape Gleam", p=0.85, g=-3, hp=2000, start=0.6, length=1.0)),
    ])
    write(f"skill_{hero}_ult_cast", tail(reverb(ult, 0.6, 0.12, 32), 1.25, 1.6), "ult",
          "太鼓の一打 + 白い風の渦 → 槍を頭上で回す柄の風 → 気が膨らむ突風 + 穂先の鋼の鳴り")

    # パッシブ（竜気がたまる）: 穂先の小さな鋼の鳴り + 短い柄の風
    pas = mix([(0, sn("Machete_Hit_Ring", 1, p=1.2, g=-6, hp=3000, hit=True, length=0.4)),
               (0, sn("Sword Ring Scrape Gleam", p=1.1, g=-6, hp=3000, start=1.4, length=0.35)),
               (0.0, sn("HighSwings15", p=1.3, g=-12, hp=800, hit="peak", pre=0.05))])
    write(f"skill_{hero}_passive", tail(pas, 0.35, 0.5), "passive", "穂先の閃き（鋼の小さな鳴り + 短い風）")

    # 強化通常攻撃 竜の三連突き（atkx、2 種）: 1 撃目の命中（0 秒）に 1 回鳴らす。3 突きの風の山を 0・0.133・0.267 秒に置く。
    # 突きごとに: 長い柄が空を切る風（1: 棒の振り、2: 長い棒（箒の柄）の振りの別テイク。どちらも音程を上げて速く）+
    # 速い突きの風切り（カンフー映画の短い風切り）+ 穂先の鋼のきらめき（大きなナイフの短い鳴り）。
    # 山は各撃の時刻 +0.012 秒（ファイルは 0 秒からなので 1 撃目の溜めは 0.012 秒だけ。3 撃とも同じずれにして間隔は 0.133 秒のまま）。
    # 高域通過で山の位置が変わる素材があるので、加工した後の包絡の最大で置き、層ごとの山の大きさもそろえる（dB は最大の山からの比）。
    # 1 撃ごとに強く・高く（+1.5 dB ずつ）。0 で構えた体の風と鎧の揺れ、3 撃目の後に穂先の鋼の鳴りが残る → 0.6 秒で消える。
    # 通常攻撃（竿の風 1 つ + 刺さり）と違う、速い 3 拍の音。刺さる音は命中の音（atkxhit、1 撃ごと）
    pk = 0.012
    shafts = {1: [(ROD, 0, 1.35), (ROD, 0, 1.42), (ROD, 0, 1.5)],
              2: [(BROOM, 12, 1.6), (BROOM, 13, 1.65), (BROOM, 24, 1.7)]}
    quick = ["Seq1.15 whoosh #1", "Seq 2.1 whoosh #1", "HKAP2 Seq2.13 Whoosh 6"]

    def fade_in(x):
        return B.fade(x, 0.003, 0.0)  # 山の手前で切った頭のプツ音を消す

    def at_peak(t, x, db):
        """加工した後の包絡（5 ms）の最大を t 秒に、その大きさを db（dBFS）に。0 秒より前にはみ出す頭は切る。"""
        win = int(0.005 * SR)
        env = np.sqrt(np.convolve(x ** 2, np.ones(win) / win, mode="same"))
        x = x * (10 ** (db / 20) / (env.max() + 1e-9))
        s = t - int(np.argmax(env)) / SR
        if s < 0:
            x, s = x[int(-s * SR):], 0.0
        return (s, fade_in(x))

    for v in (1, 2):
        layers = [at_peak(pk, sn("Whoosh,Organic,Fabric,Glove", p=1.1, hp=300, hit="peak", pre=0.03), -20),
                  (0.0, sn("ARMOR Body Drop Chain", 0, p=1.25, g=-20, hp=1500, hit=True, length=0.2))]
        for n in range(3):
            t = 4 * n / 30 + pk
            g = -8.5 + 1.5 * n  # 山の大きさ（dBFS、5 ms の包絡）。仕上げで LUFS をそろえるので層どうしの比だけが効く
            part, i, p = shafts[v][n]
            qp = (1.0 + 0.05 * n) * (1.0 if v == 1 else 0.94)
            layers += [at_peak(t, sn(part, i, p=p, hp=250, hit="peak", pre=0.09, length=0.28), g),
                       at_peak(t, sn(quick[(n + v - 1) % 3], p=qp, hp=400, hit="peak", pre=0.06), g - 3),
                       at_peak(t + 0.003, sn("large metal knife muted ring - 13", p=(1.15 if v == 1 else 1.05) + 0.05 * n, hp=3500,
                                             length=0.12), g - 9)]
        layers.append((0.27, sn("Sword Ring Scrape Gleam", p=1.05 if v == 1 else 0.95, g=-14, hp=3000, start=1.4, length=0.35)))
        write(f"skill_{hero}_atkx_{v}", tail(mix(layers), 0.42, 0.62), "atkx",
              "三連突きの風 ×3（0・0.133・0.267 秒。柄の風・速い突きの風切り・穂先の鋼のきらめき、だんだん強く）+ 構えた体と鎧 → 鋼の鳴りの尾")

    # 強化通常攻撃の命中（atkxhit、3 種を 1 撃ごとに順に）: 穂先が鋭く刺さる（短い刺し）+ 刃先の点（短剣の刺さり）+
    # 体を打つ短い打撃（カンフー映画の打撃）+ 鋼の明るい鳴り（大きなナイフの鳴り。S1・S2 のマチェーテとは別の録音）+ 鎧の鎖 +
    # 小さな低い芯。0.133 秒おきに重なっても濁らないよう 0.24 秒までに消す
    for k, (core, cp, di, body, rp) in enumerate([("PM_BB_CLEAN_STABS_20", 1.0, 0, "Seq1.15 Hit #1 96", 1.15),
                                                  ("stab_medium_10", 0.95, 2, "Seq 2.27 Hit #1 96", 1.25),
                                                  ("PM_BB_CLEAN_STABS_20", 1.12, 8, "Seq1.15 Hit #2 96", 1.05)], start=1):
        x = mix([(0, sn(core, p=cp, g=-4, hit=True, pre=0.003, length=0.22)),
                 (0, sn("GORE Impact stab dagger", di, p=1.0, g=-8, hit=True, pre=0.003)),
                 (0, sn(body, p=0.9, g=-10, hit=True, pre=0.003, length=0.2)),
                 (0.003, sn("large metal knife ring - 8", p=rp, g=-12, hp=2500, hit=True, pre=0.003, length=0.25)),
                 (0, sn("Chainmail_Impact_Hard_03", p=1.1, g=-16, hp=1200, hit=True, pre=0.003, length=0.15)),
                 (0, sn("10 Hit Deep Thud", p=1.4, g=-18, lp=200, hit=True, length=0.15))])
        write(f"skill_{hero}_atkxhit_{k}", tail(x, 0.13, 0.24), "atkxhit",
              "穂先が鋭く刺さる + 刃先の点 + 体を打つ短い打撃 + 鋼の明るい鳴り + 鎧の鎖 + 小さな低い芯")
    return hero
