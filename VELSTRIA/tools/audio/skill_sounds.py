"""H025〜H034 のスキルの音（tools/audio/build_audio.py の skills から呼ぶ）。

1 つのスキルにつき 2 つ（再使用の段はもう 1 つ）:
- skill_<ヒーロー>_<s1|s2|ult>[_r<段>]_cast.caf: 発動から鳴らす。溜め → 振り → 決まった時刻の着弾 → 余韻を、演出の at: と
  sim の時刻の定数（FX_H0xx.swift の Tune の写し。例: ボルグの奥義の崩落 1.0 秒、ゴルムの S2 の叩きつけ 0.27 秒）に合わせて重ねる。
- skill_<ヒーロー>_<スロット>_hit.caf: そのスキルの命中（damage(.skill)）ごとに、当たった所で鳴らす（間隔は BattleAudioDirector）。
素材は Kenney の CC0 の素材集（impact / rpg / sci-fi / digital / interface）と、ここで作る風切り音・溜めの雑音。
時刻（秒）は FX_H0xx.swift と docs/vfx/H0xx.md の表から。MLBB の音は使わない（画面収録の時刻だけ参照）。
"""

import zlib

B = None


def k(pack, name, p=1.0, g=0.0, lp=None, hp=None):
    x = B.K(pack, name)
    if p != 1.0:
        x = B.pitch(x, p)
    if lp:
        x = B.lowpass(x, lp)
    if hp:
        x = B.highpass(x, hp)
    return B.db(x, g)


def whoosh(d, lo, hi, g=-6, seed=1):
    """風切り音（帯域の雑音。立ち上がりは長さの 4 割）。"""
    return B.db(B.noise_burst(d, lo, hi, attack=d * 0.4, seed=seed), g)


def swell(d, lo, hi, g=-8, seed=2):
    """溜め（帯域の雑音がふくらんで切れる）。"""
    x = B.noise_burst(d, lo, hi, attack=d * 0.92, seed=seed)
    return B.db(B.fade(x, 0.0, 0.03), g)


def crackle(d, g=-6, seed=5):
    """電気のぱちぱち（高い帯域の雑音を細かく刻む）。"""
    import numpy as np
    x = B.noise_burst(d, 2500, 12000, attack=0.005, seed=seed)
    rng = np.random.default_rng(seed)
    n = len(x)
    gate = np.zeros(n, np.float32)
    i = 0
    while i < n:
        w = int(rng.integers(80, 400))
        if rng.random() < 0.55:
            gate[i:i + w] = 1
        i += w + int(rng.integers(40, 600))
    return B.db(x * gate, g)


def slam(p=0.8, g=0.0, rock=0):
    """地面への叩きつけ（重い板 + 岩）。"""
    return B.mix([(0, k("impact", "impactPlate_heavy_00%d" % (rock % 5), p=p, lp=2600, g=g)),
                  (0.01, k("impact", "impactMining_00%d" % ((rock + 1) % 5), p=p + 0.1, g=g - 6))])


def slash(p=0.8, g=0.0, n=0):
    """暗い斬撃（刃 + 重い金属）。"""
    return B.mix([(0, k("rpg", "knifeSlice" if n % 2 == 0 else "knifeSlice2", p=p, g=g)),
                  (0, k("impact", "impactMetal_heavy_00%d" % (n % 5), p=p, g=g - 8))])


def chain():
    """鎖のじゃらつき（金具の音を細かく重ねる）。"""
    return B.mix([(0, k("rpg", "metalClick", p=1.1, g=-4)), (0.05, k("rpg", "handleCoins", p=0.8, g=-8)),
                  (0.1, k("rpg", "metalClick", p=0.9, g=-6)), (0.16, k("rpg", "handleCoins2", p=0.75, g=-10))])


def spec():
    """{(ヒーロー, スロット, 段, "cast"|"hit"): (重ね, 残響の秒, 残響の量)}。"""
    S = {}

    def cast(h, slot, layers, rev=0.5, mix=0.18, stage=0):
        S[(h, slot, stage, "cast")] = (layers, rev, mix)

    def hit(h, slot, layers, rev=0.25, mix=0.1):
        S[(h, slot, 0, "hit")] = (layers, rev, mix)

    # H025 ルミナ（ミヤ）: 月光。光の殻・弓・落ちる光の矢と氷の檻。S1 の連弾は通常攻撃なので hit は無い
    cast("H025", "s1", [(0.04, k("scifi", "forceField_000", p=1.6, g=-8, hp=1500)), (0.04, k("interface", "glass_002", p=1.2, g=-4)),
                        (0.05, whoosh(0.3, 2000, 9000, -12, seed=11))], 0.6, 0.22)
    cast("H025", "s2", [(0.0, k("rpg", "cloth1", p=1.3, g=-10)), (0.30, whoosh(0.22, 1500, 7000, -6, seed=12)),
                        (0.32, k("rpg", "drawKnife2", p=1.5, g=-8)), (0.65, k("impact", "impactGlass_heavy_000", p=1.1, g=-2)),
                        (0.65, k("scifi", "forceField_002", p=0.8, g=-8)), (0.98, k("impact", "impactGlass_light_001", p=1.4, g=-8))],
         0.7, 0.22)
    hit("H025", "s2", [(0, k("impact", "impactGlass_light_002", p=1.2)), (0, k("scifi", "forceField_001", p=1.3, g=-10))])
    cast("H025", "ult", [(0, swell(0.9, 300, 4000, -10, seed=13)), (0.0, k("scifi", "forceField_003", p=0.7, g=-4, lp=4000)),
                         (0.1, k("interface", "glass_005", p=0.9, g=-8))], 1.2, 0.3)

    # H026 エウリア（エウドラ）: 雷。扇の稲妻・雷球・天からの落雷（0.45 秒、外側 +0.14）
    cast("H026", "s1", [(0.03, k("digital", "zap1", p=0.9)), (0.05, k("scifi", "laserLarge_001", p=1.3, g=-4)),
                        (0.05, crackle(0.25, -6, seed=21))], 0.4, 0.15)
    hit("H026", "s1", [(0, k("digital", "zapTwoTone", p=1.2, g=-4)), (0, crackle(0.12, -8, seed=22))])
    cast("H026", "s2", [(0, k("digital", "phaserUp3", p=0.8, g=-6)), (0.02, k("digital", "zap2", g=-4))], 0.4, 0.15)
    hit("H026", "s2", [(0, k("digital", "zap1", p=1.1)), (0.02, crackle(0.2, -6, seed=23))])
    cast("H026", "ult", [(0, k("scifi", "forceField_004", p=1.2, g=-8)), (0.05, crackle(0.4, -10, seed=24)),
                         (0.41, crackle(0.05, -2, seed=25)), (0.45, k("scifi", "explosionCrunch_002", p=1.1)),
                         (0.45, k("scifi", "lowFrequency_explosion_000", p=1.2, g=-3)), (0.45, k("scifi", "laserLarge_004", p=0.7, g=-4)),
                         (0.59, crackle(0.3, -6, seed=26))], 1.0, 0.25)
    hit("H026", "ult", [(0, k("digital", "zapThreeToneDown", g=-6)), (0, crackle(0.1, -6, seed=27))])

    # H027 ジャルド（子龍）: 槍。跳んで叩く（溜め 0.4 + 跳び 0.2）・突き（0.24）・強化の気
    cast("H027", "s1", [(0, k("rpg", "cloth2", g=-8)), (0.05, whoosh(0.35, 300, 2500, -4, seed=31)),
                        (0.40, k("impact", "impactPunch_heavy_001", p=0.9, g=-2)), (0.60, k("impact", "impactSoft_heavy_000", g=-4))])
    hit("H027", "s1", [(0, k("impact", "impactPunch_medium_002")), (0, k("impact", "impactMetal_light_001", p=1.2, g=-8))])
    cast("H027", "s2", [(0, whoosh(0.25, 600, 5000, -6, seed=32)), (0.24, k("rpg", "drawKnife1", p=1.2, g=-4)),
                        (0.24, k("impact", "impactMetal_medium_001", p=1.3, g=-6))])
    hit("H027", "s2", [(0, k("impact", "impactMetal_light_002", p=1.1)), (0, k("rpg", "knifeSlice2", p=1.2, g=-6))])
    cast("H027", "ult", [(0, k("digital", "powerUp5", p=0.6, g=-6, lp=5000)), (0, swell(0.6, 200, 2500, -8, seed=33)),
                         (0.1, k("impact", "impactMetal_heavy_002", p=0.8, g=-6))], 1.0, 0.25)

    # H028 ザイル（セイバー）: 回る剣（0.2 秒で出る）・突進（0.2）・三連の斬り（0.17 に着いてから）
    cast("H028", "s1", [(0, k("rpg", "drawKnife3", p=1.1)), (0.2, k("rpg", "drawKnife2", p=1.3, g=-4)),
                        (0.25, whoosh(0.6, 800, 6000, -10, seed=41)), (0.45, whoosh(0.5, 800, 6000, -12, seed=42))])
    hit("H028", "s1", [(0, k("rpg", "knifeSlice", p=1.25, g=-2)), (0, k("impact", "impactMetal_light_003", p=1.4, g=-10))])
    cast("H028", "s2", [(0, whoosh(0.22, 500, 4500, -4, seed=43)), (0.2, k("rpg", "knifeSlice2", p=1.0, g=-2))])
    hit("H028", "s2", [(0, k("rpg", "knifeSlice", p=0.95)), (0, k("impact", "impactMetal_medium_002", p=1.1, g=-8))])
    cast("H028", "ult", [(0, whoosh(0.18, 600, 6000, -4, seed=44)), (0.17, k("rpg", "knifeSlice2", p=1.1)),
                         (0.5, k("rpg", "knifeSlice", p=1.0)), (0.85, k("rpg", "knifeSlice2", p=0.85)),
                         (0.85, k("impact", "impactMetal_heavy_001", p=1.0, g=-4))], 0.7, 0.2)
    hit("H028", "ult", [(0, k("impact", "impactMetal_heavy_003", p=1.1, g=-2)), (0, k("rpg", "knifeSlice", p=0.9, g=-6))])

    # H029 ボルグ（ティグラル）: 槌と盾。S1 は 3 波（0.25 から 1/3 秒おき）、S2 は突進 0.67 と再使用の打ち上げ（0.2）、
    # 奥義は引き寄せから 1.0 秒で崩落
    cast("H029", "s1", [(0, whoosh(0.25, 200, 1800, -6, seed=51)), (0.25, slam(0.8, 0, 0)), (0.583, slam(0.82, -2, 1)),
                        (0.917, slam(0.85, -3, 2))], 0.6, 0.18)
    hit("H029", "s1", [(0, k("impact", "impactPunch_heavy_002", p=0.9))])
    cast("H029", "s2", [(0, whoosh(0.67, 150, 1500, -6, seed=52)), (0.0, k("impact", "impactSoft_heavy_001", p=0.8, g=-6)),
                        (0.67, k("impact", "impactMetal_heavy_000", p=0.8)), (0.67, k("impact", "impactPlate_heavy_002", p=0.7, g=-4))])
    cast("H029", "s2", [(0, whoosh(0.2, 300, 3000, -4, seed=53)), (0.2, k("impact", "impactMetal_heavy_004", p=0.9)),
                        (0.2, k("scifi", "lowFrequency_explosion_001", p=1.4, g=-8))], 0.6, 0.18, stage=1)
    hit("H029", "s2", [(0, k("impact", "impactPunch_heavy_003", p=0.85))])
    cast("H029", "ult", [(0, swell(1.0, 100, 1500, -6, seed=54)), (0, k("scifi", "forceField_000", p=0.6, g=-8, lp=3000)),
                         (1.0, k("scifi", "lowFrequency_explosion_000", p=0.9)), (1.0, k("impact", "impactPlate_heavy_003", p=0.65, g=-2)),
                         (1.02, k("impact", "impactMining_003", p=0.8, g=-6)), (1.05, k("scifi", "explosionCrunch_000", p=0.8, g=-6))],
         1.2, 0.28)
    hit("H029", "ult", [(0, k("impact", "impactPunch_heavy_004", p=0.8))])

    # H030 ライナ（ライラ）: 砲。S1 の発射 0.1、S2 の光球、奥義は溜め 0.17〜0.47 → ビーム 0.55
    cast("H030", "s1", [(0.1, k("scifi", "laserSmall_002", p=0.8, g=-2)), (0.1, k("scifi", "explosionCrunch_001", p=1.6, g=-10))])
    hit("H030", "s1", [(0, k("scifi", "explosionCrunch_003", p=1.3, g=-2))])
    cast("H030", "s2", [(0.05, k("digital", "phaserUp2", p=0.9, g=-6)), (0.1, k("scifi", "laserRetro_002", p=0.9, g=-4))])
    hit("H030", "s2", [(0, k("scifi", "explosionCrunch_004", p=1.1, g=-2)), (0, k("digital", "zap2", p=0.8, g=-10))])
    cast("H030", "ult", [(0.08, k("scifi", "spaceEngine_002", p=1.4, g=-10, hp=600)), (0.17, swell(0.38, 800, 8000, -10, seed=61)),
                         (0.47, k("digital", "zapThreeToneUp", g=-8)), (0.55, k("scifi", "laserLarge_000", p=0.6)),
                         (0.55, k("scifi", "lowFrequency_explosion_001", p=1.0, g=-2)), (0.55, k("scifi", "thrusterFire_002", g=-6))],
         0.9, 0.22)
    hit("H030", "ult", [(0, k("scifi", "explosionCrunch_002", p=1.0, g=-2))])

    # H031 オーリア（オーロラ）: 氷。S1 の雹（0.47 から 0.15 秒おき、隕石 0.57）、S2 のそよ風（振り 0.2、0.57）、奥義の氷河
    cast("H031", "s1", [(0, swell(0.5, 2000, 9000, -12, seed=71)), (0.47, k("impact", "impactGlass_light_000", p=1.2, g=-6)),
                        (0.57, k("impact", "impactGlass_heavy_001", p=1.0, g=-2)), (0.62, k("impact", "impactGlass_medium_001", p=1.3, g=-8)),
                        (0.77, k("impact", "impactGlass_light_003", p=1.5, g=-10))], 0.6, 0.2)
    hit("H031", "s1", [(0, k("impact", "impactGlass_medium_002", p=1.2, g=-4))])
    cast("H031", "s2", [(0.2, whoosh(0.4, 2500, 10000, -6, seed=72)), (0.57, k("impact", "impactGlass_medium_003", p=1.1, g=-4))],
         0.6, 0.2)
    hit("H031", "s2", [(0, k("impact", "impactGlass_light_004", p=1.3, g=-2))])
    cast("H031", "ult", [(0, swell(1.0, 300, 6000, -8, seed=73)), (0, k("scifi", "forceField_002", p=0.6, g=-8)),
                         (1.0, k("impact", "impactGlass_heavy_003", p=0.8)), (1.0, k("scifi", "lowFrequency_explosion_000", p=1.3, g=-4)),
                         (1.08, k("impact", "impactGlass_heavy_004", p=1.1, g=-6))], 1.2, 0.28)
    hit("H031", "ult", [(0, k("impact", "impactGlass_heavy_002", p=1.2, g=-4))])

    # H032 ディアス（Dyrroth）: 暗い斬撃。S1 の輪（0.26 から 0.2 秒おき）、S2 の踏み込み 0.4 と再使用の致命の一撃 0.16、奥義の溜め 0.76
    cast("H032", "s1", [(0.0, whoosh(0.26, 300, 3000, -6, seed=81)), (0.26, slash(0.72, 0, 0)), (0.46, slash(0.75, -2, 1)),
                        (0.66, slash(0.78, -3, 2))], 0.5, 0.16)
    hit("H032", "s1", [(0, k("impact", "impactPunch_heavy_000", p=0.75, g=-2)), (0, k("rpg", "knifeSlice2", p=0.7, g=-8))])
    cast("H032", "s2", [(0, whoosh(0.4, 200, 2500, -4, seed=82)), (0.0, k("scifi", "forceField_003", p=0.5, g=-10)),
                        (0.4, k("rpg", "knifeSlice", p=0.8))])
    cast("H032", "s2", [(0, whoosh(0.16, 300, 4000, -4, seed=83)), (0.16, k("impact", "impactMetal_heavy_002", p=0.7)),
                        (0.16, k("scifi", "lowFrequency_explosion_001", p=1.5, g=-8))], 0.5, 0.16, stage=1)
    hit("H032", "s2", [(0, k("rpg", "knifeSlice2", p=0.75)), (0, k("impact", "impactPunch_medium_000", p=0.8, g=-6))])
    cast("H032", "ult", [(0, swell(0.76, 100, 2000, -6, seed=84)), (0, k("scifi", "forceField_001", p=0.45, g=-6, lp=2500)),
                         (0.76, k("impact", "impactMetal_heavy_001", p=0.6)), (0.76, k("scifi", "lowFrequency_explosion_000", g=-2)),
                         (0.78, k("rpg", "knifeSlice", p=0.6, g=-4))], 1.0, 0.25)
    hit("H032", "ult", [(0, k("impact", "impactPunch_heavy_001", p=0.7)), (0, k("scifi", "explosionCrunch_000", p=1.3, g=-8))])

    # H033 ヴァルド（アルカード）: 大剣。S1 は跳び込み 0.34 で着地、S2 は旋回（0.06 から）、奥義は強化と再使用の衝撃波（0.16）
    cast("H033", "s1", [(0, whoosh(0.34, 300, 3500, -6, seed=91)), (0.34, k("impact", "impactPlate_heavy_001", p=0.85, g=-2)),
                        (0.34, k("impact", "impactMining_001", p=0.9, g=-6)), (0.36, k("rpg", "knifeSlice2", p=0.9, g=-6))])
    hit("H033", "s1", [(0, k("rpg", "knifeSlice", p=1.05, g=-2))])
    cast("H033", "s2", [(0.06, whoosh(0.18, 700, 6000, -4, seed=92)), (0.22, whoosh(0.18, 700, 6000, -6, seed=93)),
                        (0.06, k("rpg", "knifeSlice2", p=1.15, g=-6))])
    hit("H033", "s2", [(0, k("rpg", "knifeSlice2", p=1.1, g=-2)), (0, k("impact", "impactMetal_light_004", p=1.2, g=-10))])
    cast("H033", "ult", [(0, k("digital", "powerUp9", p=0.6, g=-8, lp=4000)), (0, swell(0.6, 300, 3000, -8, seed=94))], 1.0, 0.25)
    cast("H033", "ult", [(0, whoosh(0.16, 400, 4500, -4, seed=95)), (0.16, k("rpg", "knifeSlice", p=0.85)),
                         (0.16, k("scifi", "forceField_004", p=0.7, g=-6)), (0.2, whoosh(0.5, 300, 3000, -8, seed=96))],
         0.8, 0.22, stage=1)
    hit("H033", "ult", [(0, k("rpg", "knifeSlice", p=0.9, g=-2)), (0, k("impact", "impactMetal_medium_004", g=-8))])

    # H034 ゴルム（フランコ）: 鎖と鉤。S1 は 0.33 で投げる、S2 は 0.27 で叩きつけ、奥義は 0.25 で掴んで 0.32 秒おきに殴る（hit が 1 撃ごと）
    cast("H034", "s1", [(0.0, k("rpg", "metalLatch", p=0.9, g=-6)), (0.30, whoosh(0.25, 300, 3000, -6, seed=101)),
                        (0.33, k("rpg", "metalClick", p=0.8, g=-4)), (0.36, chain())])
    hit("H034", "s1", [(0, k("impact", "impactMetal_medium_003", p=0.8)), (0.02, k("rpg", "handleCoins2", p=0.7, g=-8))])
    cast("H034", "s2", [(0, whoosh(0.27, 150, 2000, -6, seed=102)), (0.27, k("impact", "impactPlate_heavy_004", p=0.7)),
                        (0.27, k("scifi", "lowFrequency_explosion_001", p=1.1, g=-4)), (0.29, k("impact", "impactMining_004", p=0.8, g=-6)),
                        (0.3, k("scifi", "thrusterFire_001", p=1.3, g=-12))], 0.6, 0.18)
    hit("H034", "s2", [(0, k("impact", "impactPunch_heavy_002", p=0.8, g=-2))])
    cast("H034", "ult", [(0, k("rpg", "metalLatch", p=0.7, g=-4)), (0.0, whoosh(0.25, 200, 2500, -6, seed=103)),
                         (0.25, k("impact", "impactMetal_heavy_000", p=0.7, g=-2))])
    hit("H034", "ult", [(0, k("impact", "impactPunch_heavy_003", p=0.8)), (0, k("impact", "impactSoft_heavy_002", p=0.8, g=-6))])
    return S


PACKS = {"impact", "rpg", "scifi", "digital", "interface"}


def build(module):
    global B
    B = module
    print("skills")
    for (h, slot, stage, phase), (layers, rev, mix) in sorted(spec().items()):
        x = B.mix(layers)
        if rev > 0:
            x = B.reverb(x, rev, mix, seed=zlib.crc32(f"{h}{slot}{stage}{phase}".encode()) % 1000)
        # 長い素材の尾（推進音など）で鳴りっぱなしにしない: 発動 2.5 秒（奥義 3.5 秒）・命中 0.8 秒まで、終わりは 0.25 秒で消す
        limit = 0.8 if phase == "hit" else (3.5 if slot == "ult" else 2.5)
        if len(x) > int(limit * B.SR):
            x = B.fade(x[: int(limit * B.SR)], 0.0, 0.25)
        stem = f"skill_{h}_{slot}" + (f"_r{stage}" if stage else "") + f"_{phase}"
        B.write_sfx(stem, x, sorted(PACKS & set(B.SOURCES)), f"{h} {slot}{' 段' + str(stage) if stage else ''} の"
                    + ("発動（溜め・振り・着弾・余韻を演出の時刻に重ねた）" if phase == "cast" else "命中"), keep_head=True)
