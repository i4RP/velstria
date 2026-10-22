# MARK: H030 ライナ（ライラ）— 星の砲。本物の砲・銃の発射音 + 機械の装填の音 + 高圧の放電・電気のうなり（電子音・レーザーは使わない）
# MLBB の録画はまだ無い。物差しはロームの測定（docs/audio/MLBB_H029.md・MLBB_H034.md）: 発動 -20.5、奥義 -17、命中 -23 LUFS。
# sim の時刻（Kit_H030.RainaTuning）: S1 は 0.1 秒で発射（弾は 1950/秒・最大 755 = 0.39 秒飛ぶ）。S2 は 0.1 秒で発射
# （1050/秒・最大 384 = 0.37 秒）、着弾で爆発（命中の音）。奥義は 0.55 秒でビーム（7000/秒。ほぼ即着）、0.55〜0.95 秒に細る。
# 演出（FX_H030）: S1 の電光 0.04・閃光 0.1・電光の帯 0.19。奥義の照準 0.08・溜めの球 0.17・金の芯 0.40・閃光 0.47・ビーム 0.55。
"""H030 ライナ（MLBB: ライラ）のスキル・パッシブの音。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import build_audio as B  # noqa: E402,F401

SURGE = "electricity_surge_discharge_electrical_arc_crackling_002_01"   # 高圧の放電（1.18 秒に体の芯のある大きな弾け）
ARCS = "High Voltage Electric Arcs 2"                                    # 高圧の放電の連なり（9 秒）
SIZZLE = "electricity_texture_sizzling_crackling_006"                    # 細かい放電のぱちぱち


def crack(part, near, i=0, pre=0.005, **kw):
    """長い録音（放電の連なりなど）の near 秒あたりの弾け（2 ms の包絡の最大、その前で最大の半分を越える所）を pre 秒の位置に揃えて切り出す。"""
    x, _ = S.take(part, i, post=0.3)
    win = int(0.002 * SR)
    env = np.sqrt(np.convolve(x ** 2, np.ones(win) / win, mode="same"))
    a, b = int((near - 0.06) * SR), int((near + 0.06) * SR)
    m = a + int(np.argmax(env[a:b]))
    j = m - int(0.03 * SR) + int(np.argmax(env[m - int(0.03 * SR):m + 1] > env[m] * 0.5))
    return sn(part, i, start=max(0.0, j / SR - pre), **kw)


def build():
    hero = "H030"
    # S1 遠星弾: 0 で砲の撃鉄（機械の音）と放電の溜め → 0.1 の発射（機関砲の発射音・放電の弾け・戦車砲の低音）→ 飛ぶ弾の放電のうなり
    s1 = mix([
        (0.0, sn("gun_semi_auto_rifle_cock_02", p=1.1, g=-10, hp=1200, length=0.12, hit=True, pre=0.005)),
        (0.0, rise(sn(SIZZLE, g=-12, hp=2500, start=0.3, length=0.12), 0.1)),
        (0.1, sn("Automatic Cannon - MK44", p=1.15, g=0, hp=130, length=0.6, hit=True, pre=0.005)),
        (0.1, crack("Damp Electric Shock 8", 2.59, g=-4, hp=600, length=0.3)),
        (0.12, sn(ARCS, g=-8, hp=1500, start=1.1, length=0.42)),
        (0.1, sn("Tank Battle Cannon Fire", g=-6, lp=150, length=0.5, hit=True, pre=0.005)),
    ])
    write(f"skill_{hero}_s1_cast", tail(reverb(s1, 0.4, 0.08, 31), 0.6, 0.9), "cast",
          "撃鉄と放電の溜め → 0.1 秒の発射（機関砲・放電の弾け・戦車砲の低音）→ 飛ぶ弾の放電")
    # 命中: 放電の弾け（体の芯のある所）+ 弾が体に当たる音 + 低い拳の芯 + 火花のぱちぱち
    for k, (t0, wi, p) in enumerate([(1.18, 2, 1.0), (2.06, 4, 0.95), (2.34, 6, 1.05)], start=1):
        x = mix([(0, crack(SURGE, t0, p=p, g=0, length=0.35)),
                 (0, sn("PM_BBI_Bullet_Impact_Hit_Body_Flesh_25", p=0.9 * p, g=-4, hit=True, pre=0.005)),
                 (0, sn("Body Hits - Deep Punch 02", p=0.8, g=-6, lp=1500, hit=True, pre=0.005)),
                 (0.03, sn("Arc Weld Electrical Sparks 3", wi, g=-10, hp=2500, length=0.3))])
        write(f"skill_{hero}_s1_hit_{k}", x, "hit", "放電の弾け + 弾が体に当たる音 + 低い芯 + 火花")

    # S2 星爆弾: 0 で砲身の装填（ショットガンの弾込め）→ 0.1 の発射（空気砲の重い発射・榴弾砲の低音）→ 弧を描く球の電気のうなり
    s2 = mix([
        (0.0, sn("Shell Load_Round Eject", 1, p=0.9, g=-8, hp=800, length=0.15, hit=True, pre=0.005)),
        (0.1, sn("Potato Gun Shot Apples Heavy", 0, p=0.9, g=0, length=0.5, hit=True, pre=0.005)),
        (0.1, sn("Howitzer,M101,C1", g=-6, lp=200, length=0.5, hit=True, pre=0.005)),
        (0.12, rise(sn("electric_hum_buzz_01", g=12, start=2.0, length=0.42, hp=150), 0.05)),
        (0.12, sn("53-Ground-Electric-Arc-Machine2", g=-6, hp=500, start=10.7, length=0.42)),
    ])
    write(f"skill_{hero}_s2_cast", tail(reverb(s2, 0.4, 0.08, 32), 0.48, 0.75), "cast",
          "装填 → 0.1 秒の発射（空気砲・榴弾砲の低音）→ 飛ぶ球の電気のうなり")
    # 着弾の爆発（刻印の弾けも同じ音）: 放電の大きな弾け + 実写の爆発 + 砲弾の着弾 + 放電の尾 + 低音
    for k, (t0, a0, p) in enumerate([(1.18, 4.5, 1.0), (2.06, 6.0, 0.94), (2.34, 6.6, 1.06)], start=1):
        x = mix([(0, crack(SURGE, t0, p=p, g=0, length=0.45)),
                 (0, sn("EXPLReal_Medium Realistic Explosion 15", p=1.2 * p, g=-6, length=0.7, hit=True, pre=0.005)),
                 (0, sn("GS cannonball impact 005", p=1.1, g=-8, lp=3500, length=0.5, hit=True, pre=0.005)),
                 (0.04, sn(ARCS, g=-8, hp=2000, start=a0, length=0.4)),
                 (0, sn("Howitzer,M101,C1", g=-8, lp=150, length=0.5, hit=True, pre=0.005))])
        write(f"skill_{hero}_s2_hit_{k}", tail(x, 0.5, 0.75), "hit", "放電の大きな弾け + 爆発 + 砲弾の着弾 + 放電の尾 + 低音")

    # 奥義 星砕の大砲: 0 で砲身を引く（ポンプの重い機械音）→ 0.05〜0.55 で変圧器のうなりと放電がふくらむ（放電の逆再生で吸い込み、
    # 弾けの頭が 0.55 に来る）→ 0.55 の発射（戦車砲の 1 発・放電の大きな弾け・榴弾砲の重い発射と尾）→ 0.95 までビームの放電が続く
    suck = rev(crack(SURGE, 1.18, pre=0.0, g=0, length=0.45))
    ult = mix([
        (0.0, sn("Shotgun_Quick Pump_01", 0, p=0.75, g=-6, lp=6000, hit=True, pre=0.005)),
        (0.05, rise(sn("transformer_hum_low_003", g=-12, hp=90, start=5.0, length=0.5), 0.45)),
        (0.05, rise(sn("15-Electric Arc-Transformer", g=-6, hp=1000, start=4.0, length=0.5), 0.4)),
        (0.1, rise(B.db(suck, -16), 0.35)),
        (0.55, sn("Tank Battle Cannon Fire", g=0, length=0.6, hit=True, pre=0.005)),
        (0.55, crack(SURGE, 1.18, g=-2, length=0.5)),
        (0.55, sn("Howitzer,M101,C1", g=-4, lp=2500, length=1.3, hit=True, pre=0.005)),
        (0.6, sn(ARCS, g=-4, hp=800, start=4.5, length=0.45)),
    ])
    write(f"skill_{hero}_ult_cast", tail(reverb(ult, 0.6, 0.1, 33), 1.45, 1.85), "ult",
          "砲身を引く → 変圧器のうなりと放電の溜め → 0.55 秒の発射（戦車砲・放電・榴弾砲）→ ビームの放電 → 砲の尾", target=-17.0)
    # 命中: ビームが体を貫く（放電の弾け + 体の打撃 + 大きな弾の着弾の低音 + 放電の尾）
    for k, (t0, a0, p) in enumerate([(2.06, 1.1, 0.95), (2.34, 3.15, 1.0), (1.18, 6.0, 1.05)], start=1):
        x = mix([(0, crack(SURGE, t0, p=p, g=0, length=0.4)),
                 (0, sn("PM_BBI_Bullet_Impact_Hit_Body_Flesh_25", p=0.8 * p, g=-4, hit=True, pre=0.005)),
                 (0, sn("GS cannonball impact 005", p=1.0, g=-10, lp=2000, length=0.45, hit=True, pre=0.005)),
                 (0.03, sn(ARCS, g=-8, hp=2000, start=a0, length=0.4))])
        write(f"skill_{hero}_ult_hit_{k}", tail(x, 0.45, 0.7), "hit", "放電の弾け + 体の打撃 + 着弾の低音 + 放電の尾")

    # パッシブ（遠くの的への補正のバッジ）: 砲口の小さな火花（溶接の火花の一粒）+ 細かい放電 + 撃鉄の小さな金属音
    pas = mix([(0, sn("Arc Weld Electrical Sparks 3", 0, g=-2, hp=2000, length=0.1)),
               (0.02, sn(SIZZLE, g=-10, hp=3000, start=1.0, length=0.3)),
               (0.0, sn("gun_semi_auto_rifle_cock_02", p=1.3, g=-12, hp=2500, length=0.1, hit=True, pre=0.005))])
    write(f"skill_{hero}_passive", tail(pas, 0.3, 0.45), "passive", "砲口の小さな火花 + 細かい放電 + 撃鉄の金属音")
    return hero
