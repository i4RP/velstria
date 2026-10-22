"""H026 エウリア（MLBB: エウドラ）のスキル・パッシブの音（通常攻撃の音は武器ごとの組で別に作る）。

雷の魔導士。本物の雷鳴（間近の落雷の裂ける音・遠くへ転がる雷鳴）と、高電圧の放電（アークの弾け・ぱちぱち・うなり）だけで作る。
電子音・SF の光線・合成の「ビリビリ」は使わない。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import build_audio as B  # noqa: E402,F401


# sim の時刻（Kit_H026 の Tune・FX_H026・docs/vfx/H026.md）:
#   S1 分岐雷: 0 秒に発動、0.05 秒に杖の先から扇へ 7 本の稲妻（扇の初撃のダメージ = 命中の音）。超伝導の敵には雷の鎖:
#              0.12 / 0.39 / 0.66 / 0.93 秒の継続ダメージと 1.0 秒の終わりの一撃（どれも命中の音。0.27 秒おき）。
#   S2 雷球: 0 秒に手元で溜めて投げる（毎秒 1150・射程 505 → 最大 0.44 秒飛ぶ）。当たった時に命中の音（広がった敵にも）。
#   奥義 九天雷鳴: 0〜0.43 秒に足元を電弧が巡る、0.41 秒に縦の大雷、0.45 秒（ultDelay）に落雷（ダメージ = 命中の音）、
#                 +0.14 秒に外側の雷、0.6 秒の余韻。超伝導の敵は 0.83 秒後に炸裂（奥義の命中の音がもう一度）。
#   パッシブ 超伝導: 印の合図（実演用の演出だけ）。
# 音量はロームの測定（docs/audio/MLBB_H029.md・MLBB_H034.md）を物差しに: 発動 -20.5、命中 -23。奥義は画面を白く飛ばす落雷なので
# ゴルムの奥義（MLBB -13.8）寄りの -17。

def burst(part, a, length, p=1.0, g=0.0, lp=None, hp=None, pre=0.01):
    """長い放電の録音の a 秒から length 秒を切り、その中の立ち上がりを pre 秒に揃える（放電の弾けを時刻に置く）。"""
    return onset_align(sn(part, p=p, g=g, lp=lp, hp=hp, start=a, length=length), pre)


def build():
    hero = "H026"

    # S1 分岐雷: 0 で杖の先に火花が弾ける → 0.05 稲妻が扇へ裂ける（間近の雷の裂け + 高電圧の放電の弾け + 低い雷の芯）→
    # 0.13〜0.55 扇の中を電弧が這う（ぱちぱち）→ 雷鳴の尾が 1 秒で消える
    s1 = mix([
        (0.0, sn("Arc Weld Electrical Sparks 3", 0, p=1.0, g=-8, hp=1500, hit=True, length=0.1)),
        (0.05, sn("Arc Weld Electrical Sparks 3", 0, p=0.9, g=0, hp=800, hit=True, length=0.1)),
        (0.05, sn("High Voltage Electric Arcs 2", p=1.0, g=2, start=0.95, length=0.3)),
        (0.05, sn("thunder_mountainous_big_crack_02", 0, p=1.15, g=-2, hp=300, hit=True, length=0.95)),
        (0.05, burst("surge_discharge_electrical_arc", 1.0, 0.45, g=-7, hp=500)),
        (0.13, sn("texture_sizzling_crackling_006", p=1.0, g=-5, start=0.1, length=0.45)),
        (0.05, sn("Thunder_Extremely-Close_03", 0, p=1.1, g=-8, lp=160, hit=True, length=0.8)),
    ])
    write(f"skill_{hero}_s1_cast", tail(s1, 0.75, 1.05), "cast",
          "杖の火花 → 0.05 稲妻が裂ける（間近の雷鳴・放電の弾け・低い雷の芯）→ 電弧のぱちぱち → 雷鳴の尾")
    # 命中（扇の初撃・鎖の継続 0.27 秒おき・終わりの一撃）: 体に走る放電の弾け + ぱちぱち + 短い雷の裂け + 体が跳ねる低い芯
    for k, a in enumerate([1.0, 1.95, 1.05], start=1):
        x = mix([
            (0, sn("Arc Weld Electrical Sparks 3", 0, p=0.85 + 0.1 * k, g=3, hp=800, hit=True, length=0.1)),
            (0, sn("Bug zapper", p=0.8 + 0.08 * k, g=-4, hit=True, length=0.2)),
            (0, sn("High Voltage Electric Arcs 2", p=1.0, g=0, start=0.9 + 0.6 * k, length=0.15)),
            (0, burst("surge_discharge_electrical_arc", a, 0.3, p=1.0 + 0.05 * k, g=-8, hp=500)),
            (0.01, sn("Damp Electric Shock 8", p=1.0, g=-14, start=0.4 * k, length=0.3)),
            (0, sn("Thunder_Crack_Fienup_016", 0, p=1.3 + 0.1 * k, g=-6, hp=1000, hit=True, length=0.2)),
            (0, sn("10 Hit Deep Thud", p=1.3, g=-12, lp=220, length=0.2, hit=True)),
        ])
        write(f"skill_{hero}_s1_hit_{k}", tail(x, 0.25, 0.38), "hit", "体に走る放電の弾け + ぱちぱち + 短い雷の裂け + 低い芯")

    # S2 雷球: 0〜0.06 手元に放電が集まる（ぱちぱちが膨らむ）→ 0.02 投げる（腕と袖の風 + 放電の弾け）→ 飛ぶ間の球のうなりと電弧
    # （高電圧のアーク + 変圧器のうなり）→ 0.7 秒で消える（着弾は命中の音）
    s2 = mix([
        (0.0, rise(sn("texture_sizzling_crackling_006", p=1.1, g=-6, start=1.2, length=0.1), 0.06)),
        (0.02, sn("Just Whoosh 3 _ Whoosh Essentials/Whoosh_Cloth_Leather_Fight_174", p=1.0, g=-4, hp=250, hit="peak", pre=0.05)),
        (0.02, burst("surge_discharge_electrical_arc", 2.0, 0.35, g=-6, hp=400)),
        (0.05, sn("High Voltage Electric Arcs 2", p=1.0, g=-2, start=0.9, length=0.6)),
        (0.05, sn("electricity_transformer_hum_low_003", p=1.0, g=-12, lp=900, start=1.0, length=0.6)),
    ])
    write(f"skill_{hero}_s2_cast", tail(s2, 0.5, 0.72), "cast", "放電が集まる → 投げる（袖の風・放電の弾け）→ 飛ぶ球のアークとうなり")
    # 命中: 雷球が弾ける（放電の弾け + 雷の裂け）→ スタンの間の体のぱちぱち → 低い雷の芯
    for k, (a, ci) in enumerate([(1.05, 0), (2.0, 0), (1.12, 0)], start=1):
        x = mix([
            (0, burst("surge_discharge_electrical_arc", a, 0.4, p=0.9 + 0.05 * k, g=-6, hp=500)),
            (0, sn("Thunder_Crack_Fienup_016", ci, p=1.0 + 0.1 * k, g=-4, hp=300, hit=True, length=0.5)),
            (0.0, sn("Arc Weld Electrical Sparks 3", 0, p=0.8 + 0.08 * k, g=2, hp=800, hit=True, length=0.1)),
            (0.0, sn("High Voltage Electric Arcs 2", p=0.95, g=0, start=3.0 + 0.5 * k, length=0.2)),
            (0.06, sn("Damp Electric Shock 8", p=1.0, g=-14, start=1.5 + 0.5 * k, length=0.45)),
            (0, sn("thunder_strike_03", 0, p=1.1, g=-6, lp=200, hit=True, length=0.45)),
        ])
        write(f"skill_{hero}_s2_hit_{k}", tail(x, 0.4, 0.55), "hit", "雷球が弾ける（放電・雷の裂け）+ スタンのぱちぱち + 低い雷の芯")

    # 奥義 九天雷鳴: 0〜0.43 足元を電弧が巡る（地を這うアーク・変圧器のアークが膨らむ）+ 遠い雷鳴が逆さに吸い込まれる →
    # 0.41 予兆の閃き（火花の弾け）→ 0.45 落雷（間近の落雷の裂け・大きな雷の裂け・放電の弾け・深い雷の低音）→
    # 0.59 外側の雷（雷の裂け 2 つ）→ 雷鳴が転がって 1.9 秒で消える（残るぱちぱち）
    pull = rev(sn("thunder_clap_04", 0, p=1.0, g=-4, start=0.3, length=0.5))
    ult = mix([
        (0.0, rise(sn("53-Ground-Electric-Arc-Machine2", p=1.0, g=-8, start=2.0, length=0.48), 0.35)),
        (0.0, rise(sn("15-Electric Arc-Transformer", p=0.9, g=-10, start=1.2, length=0.46), 0.3)),
        (0.0, rise(pull, 0.25)),
        (0.41, sn("Arc Weld Electrical Sparks 3", 0, p=0.85, g=-6, hp=1200, hit=True, length=0.1)),
        (0.45, sn("Thunder_Extremely-Close_03", 0, p=1.0, g=0, hit=True, length=1.45)),
        (0.45, sn("thunder_mountainous_big_crack_02", 0, p=1.0, g=-3, hp=800, hit=True, length=0.7)),
        (0.45, burst("surge_discharge_electrical_arc", 1.0, 0.5, g=-8, hp=500)),
        (0.45, sn("Arc Weld Electrical Sparks 3", 0, p=0.8, g=0, hp=800, hit=True, length=0.1)),
        (0.45, sn("High Voltage Electric Arcs 2", p=0.95, g=-2, start=4.0, length=0.35)),
        (0.59, sn("Arc Weld Electrical Sparks 3", 0, p=0.9, g=-3, hp=800, hit=True, length=0.1)),
        (0.59, sn("High Voltage Electric Arcs 2", p=1.05, g=-6, start=5.0, length=0.3)),
        (0.47, sn("Thunder_Rumble_Deep_Fienup_003", 0, p=1.0, g=-4, lp=140, start=0.75, length=1.3)),
        (0.59, sn("Thunder_Crack_Fienup_016", 0, p=1.05, g=-5, hp=300, hit=True, length=0.9)),
        (0.62, sn("thunder_strike_03", 0, p=1.15, g=-8, hp=500, hit=True, length=0.8)),
        (0.7, sn("texture_sizzling_crackling_006", p=0.9, g=-10, start=1.7, length=0.8)),
    ])
    write(f"skill_{hero}_ult_cast", tail(ult, 1.55, 1.95), "ult",
          "電弧が巡る・遠い雷鳴が吸い込まれる → 0.45 落雷（間近の雷鳴・放電・深い雷の低音）→ 0.59 外側の雷 → 転がる雷鳴", target=-17.0,
          cap=2.0)
    # 命中（落雷が当たった敵・超伝導の炸裂）: 体を打つ雷（雷の裂け + 放電の弾け）+ ぱちぱち + 低い雷の芯
    for k, a in enumerate([1.1, 2.05, 2.25], start=1):
        x = mix([
            (0, sn("thunder_mountainous_big_crack_02", 0, p=1.25 + 0.08 * k, g=-2, hp=250, hit=True, length=0.5)),
            (0, burst("surge_discharge_electrical_arc", a, 0.4, p=1.0, g=-7, hp=500)),
            (0, sn("Bug zapper", p=0.7 + 0.06 * k, g=-6, hit=True, length=0.2)),
            (0, sn("Arc Weld Electrical Sparks 3", 0, p=0.75 + 0.08 * k, g=2, hp=800, hit=True, length=0.1)),
            (0, sn("High Voltage Electric Arcs 2", p=0.9, g=0, start=6.0 + 0.5 * k, length=0.2)),
            (0.05, sn("Damp Electric Shock 8", p=0.95, g=-12, start=3.0 + 0.4 * k, length=0.4)),
            (0, sn("Thunder_Extremely-Close_03", 0, p=1.2, g=-6, lp=180, hit=True, length=0.5)),
        ])
        write(f"skill_{hero}_ult_hit_{k}", tail(x, 0.45, 0.6), "hit", "体を打つ雷（裂け・放電）+ ぱちぱち + 低い雷の芯", target=-21.0)

    # パッシブ（超伝導の印）: 小さな放電の弾け + 短いぱちぱち
    pas = mix([(0, sn("Bug zapper", p=1.0, g=-2, hit=True, length=0.25)),
               (0.02, sn("High Voltage Electric Arcs 2", p=1.1, g=-10, start=2.0, length=0.35)),
               (0, burst("surge_discharge_electrical_arc", 2.6, 0.25, p=1.2, g=-8, hp=1000))])
    write(f"skill_{hero}_passive", tail(pas, 0.3, 0.45), "passive", "超伝導の印（小さな放電の弾け + ぱちぱち）")
    return hero
