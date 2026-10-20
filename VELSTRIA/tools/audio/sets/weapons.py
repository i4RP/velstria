"""武器ごとの通常攻撃の音の組（34 体に HeroBlueprints の武器から割り当てる。割り当ては App/Battle/HUD/HeroWeaponSounds.swift）。

1 つの組 = 通常攻撃 4 種（wpn_<組>_atk_1..4）・命中 3 種（wpn_<組>_hit_1..3）・会心 2 種（wpn_<組>_crit_1..2）。鳴らすたびに順に替える。
- 近接（剣・大剣・双剣・槍・拳・鎚・鎖）: 通常攻撃の音は sim の命中（attackReleased）の瞬間に鳴る = 振りの終わり（0.04 秒前から）→
  刃・打撃の芯。命中の音は同じ瞬間に、当たった側（肉・鎧）の鳴り。会心は命中の代わりに、重い打撃 + 金属の鳴り。
- 遠隔（弓・弩・銃・砲・魔法）: 通常攻撃の音は発射（弦の鳴り・銃声・砲声・詠唱の放ち）、命中は弾・矢・魔法の着弾（damage の時刻）。
- 素材はすべて実音の録音（Sonniss GDC。刃の風切り・鋼の鳴り・肉や鎧への命中、弦の鳴り・矢の風切り・刺さり、銃・砲の発射と残響、
  拳の打撃、鎖、水・炎・雷・氷・鐘・低いうねり）。電子音・SF のレーザー・合成は使わない。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403

# 音量（LUFS）: MLBB（ティグラル）の通常攻撃 -20〜-26。命中は自分の命中で 0.8 倍で鳴るので少し下、会心は命中より大きい
ATK, HIT, CRIT = -23.0, -26.0, -22.0
PITCH = [1.0, 0.96, 1.04, 0.98]


def atk(name, layers, note):
    for k, p in enumerate(PITCH, start=1):
        write(f"wpn_{name}_atk_{k}", layers(k - 1, p), "atk", note, target=ATK)


def hit(name, layers, note, n=3):
    for k in range(1, n + 1):
        write(f"wpn_{name}_hit_{k}", layers(k - 1, [1.0, 0.95, 1.06][k - 1]), "atkhit", note, target=HIT)


def crit(name, layers, note):
    for k in range(1, 3):
        write(f"wpn_{name}_crit_{k}", layers(k - 1, [1.0, 0.94][k - 1]), "crit", note, target=CRIT)


# MARK: 近接

def sword():
    slashes = ["Sword Slash Impact V2 Assorted 18", "Melee_Sword_Attack_04", "SH101_Sword Attack_Hollywood", "SWORD Hit Metal 02"]
    atk("sword", lambda i, p: mix([
        (0.0, sn("whoosh_weapon_knife_swing_04", p=0.85 * p, g=-8, hp=500, hit="peak", pre=0.04, length=0.12)),
        (0.0, sn(slashes[i], p=p, g=0, hit="peak", pre=0.04, length=0.45)),
        (0.03, sn("Knife_Sword_Shing", i % 2, p=1.05 * p, g=-16, hp=2500, length=0.3, hit=True)),
    ]), "剣: 刃の風切り → 斬りの芯（鋼）→ 刃の鳴り")
    hit("sword", lambda i, p: mix([
        (0.0, sn("medium metal blade wet impact", p=p, g=-2, hit=True, length=0.3)),
        (0.0, sn("punch_general_body_impact_03", p=0.9 * p, g=-12, lp=2500, hit=True)),
    ]), "剣の命中: 刃が肉に入る音 + 体への鈍い衝撃")
    crit("sword", lambda i, p: mix([
        (0.0, sn("Machete_Hit_Ring", i, p=0.92 * p, g=0, hit=True, length=0.5)),
        (0.0, sn("large metal blade wet stab slash and remove from flesh - medium - 14", p=p, g=-4, hit=True, length=0.3)),
        (0.0, sn("10 Hit Deep Thud", p=1.2, g=-10, lp=200, length=0.3, hit=True)),
    ]), "剣の会心: 刃の鋭い鳴り + 深い斬り + 低い芯")


def greatsword():
    atk("greatsword", lambda i, p: mix([
        (0.0, sn("SWING IMPACTS Quick Heavy", [0, 3, 6, 9][i], p=0.92 * p, g=-2, hp=100, hit="peak", pre=0.05, length=0.4)),
        (0.0, sn("Two-Handed Axe Flesh Hit", i, p=0.9 * p, g=-4, hit="peak", pre=0.04, length=0.4)),
        (0.02, sn("10 Hit Deep Thud", p=1.05 * p, g=-8, lp=220, length=0.3, hit=True)),
    ]), "大剣: 重い刃の振り → 鈍い斬りの芯 → 低い芯")
    hit("greatsword", lambda i, p: mix([
        (0.0, sn("large metal blade wet stab slash and remove from flesh - medium - 14", p=0.85 * p, g=-2, hit=True, length=0.3)),
        (0.0, sn("Heavy Body Crunch", 1, p=0.9 * p, g=-12, length=0.2, hit=True)),
    ]), "大剣の命中: 重い刃が肉に入る音 + 骨の砕け")
    crit("greatsword", lambda i, p: mix([
        (0.0, sn("Two-Handed Axe Flesh Hit", 2 + i, p=0.85 * p, g=0, hit="peak", pre=0.02, length=0.45)),
        (0.0, sn("Machete_Hit_Ring", 2, p=0.8 * p, g=-6, hit=True, length=0.5)),
        (0.0, sn("Explosive Hit 10", g=-8, length=0.4, hit=True)),
    ]), "大剣の会心: 深い斬り + 低い刃の鳴り + 低音")


def dual():
    atk("dual", lambda i, p: mix([
        (0.0, sn("gore - metal knife swing - " + ["4", "5", "17", "4"][i], p=1.1 * p, g=-4, hp=300, hit="peak", pre=0.04, length=0.12)),
        (0.0, sn("Knife_Sword_Hit_Multiple", i % 3, p=1.05 * p, g=-2, hit=True, length=0.2)),
        (0.02, sn("Knife_Sword_Shing", i % 2, p=1.2 * p, g=-18, hp=3000, length=0.25, hit=True)),
    ]), "双剣: 短い刃の風切り → 軽い斬り → 刃の鳴り")
    hit("dual", lambda i, p: mix([
        (0.0, sn("small metal blade flesh movement", p=1.1 * p, g=-2, length=0.2, hit=True)),
        (0.0, sn("PUNCH_DESIGNED_LIGHT", p=1.1 * p, g=-12, hit=True)),
    ]), "双剣の命中: 刃が肉を裂く短い音")
    crit("dual", lambda i, p: mix([
        (0.0, sn("Knife_Sword_Hit_Multiple", 0, p=1.0 * p, g=-2, hit=True, length=0.15)),
        (0.07, sn("Knife_Sword_Hit_Multiple", 1, p=0.95 * p, g=-2, hit=True, length=0.15)),
        (0.07, sn("medium metal blade wet impact", p=1.05 * p, g=-6, hit=True, length=0.3)),
        (0.08, sn("Machete_Hit_Ring", 1, p=1.1 * p, g=-12, hit=True, length=0.4)),
    ]), "双剣の会心: 二連の斬り + 深い刃 + 鳴り")


def spear():
    atk("spear", lambda i, p: mix([
        (0.0, sn("Whoosh_Swing_Fishing Pole", i % 2, p=0.9 * p, g=-4, hp=300, hit="peak", pre=0.06, length=0.16)),
        (0.0, sn("large metal blade wet stab slash and remove from flesh - medium - 14", p=1.05 * p, g=-4, hit=True, length=0.25)),
        (0.0, sn("STICK HIT-07", 0, p=0.85 * p, g=-12, hit=True, length=0.15)),
    ]), "槍: 柄のうなる突きの風切り → 穂先の刺さり → 柄の木の鳴り")
    hit("spear", lambda i, p: mix([
        (0.0, sn("Just Gore _ Add On/Stab_Punch_Hit_136", p=p, g=-2, hit=True)),
        (0.0, sn("punch_general_body_impact_03", p=0.85 * p, g=-12, lp=2500, hit=True)),
    ]), "槍の命中: 刺さる音 + 体への衝撃")
    crit("spear", lambda i, p: mix([
        (0.0, sn("large metal blade wet stab slash and remove from flesh - hard - 1", p=p, g=0, hit=True, length=0.4)),
        (0.0, sn("Machete_Hit_Ring", 0, p=0.95 * p, g=-10, hit=True, length=0.4)),
        (0.0, sn("10 Hit Deep Thud", p=1.2, g=-10, lp=200, length=0.3, hit=True)),
    ]), "槍の会心: 深い刺突 + 穂先の鳴り + 低い芯")


def fist():
    atk("fist", lambda i, p: mix([
        (0.0, sn("Glove,Airy,Breathy,Punchy", p=0.9 * p, g=-6, hit="peak", pre=0.05, length=0.12)),
        (0.0, sn("Deep Punch 02", p=0.9 * p, g=0, hit=True)),
        (0.0, sn("punch_general_body_impact_03", p=p, g=-6, hit=True)),
        (0.0, sn("Hit Rock Debris_RBD 02", p=1.1 * p, g=-18, hp=1500, length=0.2, hit=True)),
    ]), "拳: 拳の風切り → 拳の打撃 → 体への衝撃（岩の拳の小さな擦れ）")
    hit("fist", lambda i, p: mix([
        (0.0, sn(["PUNCH_PERCUSSIVE_HEAVY", "IMPACT_LOW_THUD", "PUNCH_SMACK_LETTUCE"][i], p=0.9 * p, g=0, hit=True)),
    ]), "拳の命中: 体を打つ鈍い音")
    crit("fist", lambda i, p: mix([
        (0.0, sn("IMPACT DARK Epic Punch", p=0.95 * p, g=0, hit="peak", pre=0.02, length=0.4)),
        (0.0, sn("Heavy Body Crunch", 1, p=0.9 * p, g=-8, length=0.25, hit=True)),
    ]), "拳の会心: 重い打撃 + 骨の砕け")


def hammer():
    atk("hammer", lambda i, p: mix([
        (0.0, sn("SWING IMPACTS Quick Heavy", [1, 4, 7, 10][i], p=0.88 * p, g=0, hp=90, hit="peak", pre=0.05, length=0.45)),
        (0.02, sn("Iron - Thick - HIT - Hammer", i + 1, p=0.8 * p, g=-8, hp=500, hit=True, post=0.25)),
        (0.02, sn("stone_impact_hammer", p=0.85 * p, g=-8, lp=4000, hit=True)),
        (0.02, sn("10 Hit Deep Thud", p=1.0 * p, g=-6, lp=200, length=0.3, hit=True)),
    ]), "鎚: 重い振り → 鈍い打撃（鉄・石）→ 低い芯")
    hit("hammer", lambda i, p: mix([
        (0.0, sn("Hit Rock Debris_RBD 02", p=p, g=-6, length=0.3, hit=True)),
        (0.0, sn("punch_general_body_impact_03", p=0.8 * p, g=-4, hit=True)),
    ]), "鎚の命中: 体への重い衝撃 + 砕け")
    crit("hammer", lambda i, p: mix([
        (0.0, sn("HORROR - Hammer Impact, huge", i, p=0.95 * p, g=0, hit=True, length=0.5)),
        (0.0, sn("Smash B", p=0.9 * p, g=-6, lp=2500, length=0.5, hit=True)),
    ]), "鎚の会心: 巨大な打撃 + 重い一撃の残響")


def chain():
    atk("chain", lambda i, p: mix([
        (0.0, sn("ROPE WHOOSH Fast Light", i, p=0.75 * p, g=-6, hp=200, hit="peak", pre=0.05, length=0.15)),
        (0.0, sn("Two-Handed Axe Flesh Hit", i, p=0.95 * p, g=-2, hit="peak", pre=0.04, length=0.35)),
        (0.02, sn("Dog_Chain-Hits", i, p=0.85, g=-12, hp=1500, length=0.3, hit=True)),
    ]), "鎖鉤: 鎖の風切り → 鉤の打撃 → 鎖の鳴り")
    hit("chain", lambda i, p: mix([
        (0.0, sn("Chainmail_Impact_Hard_03", p=p, g=-2, hit=True, length=0.3)),
        (0.0, sn("punch_general_body_impact_03", p=0.85 * p, g=-10, hit=True)),
    ]), "鎖鉤の命中: 鎧に当たる鎖 + 体への衝撃")
    crit("chain", lambda i, p: mix([
        (0.0, sn("Metal_Chain_Hit_10", p=0.9 * p, g=0, hit=True, length=0.45)),
        (0.0, sn("Two-Handed Axe Flesh Hit", 3, p=0.85 * p, g=-4, hit="peak", pre=0.02, length=0.35)),
    ]), "鎖鉤の会心: 鎖の重い打撃 + 深い鉤")


# MARK: 遠隔（発射の音 = 通常攻撃、着弾 = 命中）

def bow():
    atk("bow", lambda i, p: mix([
        (0.0, sn("crossbow1,carbonbolt,atbow,snap", p=0.75 * p, g=-2, hit=True, length=0.25)),
        (0.0, sn("Hawk's Arrow Flies", p=1.0 * p, g=-6, hit=True, length=0.45)),
        (0.03, sn("PARTICLES_WHOOSH_Arrow", p=1.1 * p, g=-10, hp=1000, hit="peak", pre=0.08, length=0.25)),
    ]), "弓: 弦の鳴り → 矢の風切り")
    hit("bow", lambda i, p: mix([
        (0.0, sn("BOW Arrow Hit 05", p=p, g=0, hit=True, length=0.4)),
        (0.0, sn("Just Gore _ Add On/Stab_Punch_Hit_136", p=1.1 * p, g=-12, hit=True)),
    ]), "弓の命中: 矢の刺さり + 肉の鈍い音")
    crit("bow", lambda i, p: mix([
        (0.0, sn("BOW Arrow Hit 05", p=0.9 * p, g=0, hit=True, length=0.45)),
        (0.0, sn("large metal blade wet stab slash and remove from flesh - medium - 14", p=1.15 * p, g=-6, hit=True, length=0.25)),
        (0.0, sn("Machete_Hit_Ring", 1, p=1.2 * p, g=-14, hit=True, length=0.35)),
    ]), "弓の会心: 深い刺さり + 鏃の鳴り")


def crossbow():
    atk("crossbow", lambda i, p: mix([
        (0.0, sn("crossbow1,carbonbolt,atbow,snap", p=0.95 * p, g=0, hit=True, length=0.25)),
        (0.0, sn("gun_semi_auto_rifle_cock_02", p=1.1 * p, g=-14, hit=True, length=0.15)),
        (0.02, sn("PARTICLES_WHOOSH_Arrow", p=1.25 * p, g=-12, hp=1500, hit="peak", pre=0.06, length=0.2)),
    ]), "弩: 弦の弾け + 機構の金属音 → 矢の風切り")
    hit("crossbow", lambda i, p: mix([
        (0.0, sn("BOW Arrow Hit 05", p=1.15 * p, g=0, hit=True, length=0.35)),
        (0.0, sn("Hit Impact Metal Scrap Debris_UC 06", p=p, g=-14, hit=True, length=0.2)),
    ]), "弩の命中: 太矢の刺さり + 金属の跳ね")
    crit("crossbow", lambda i, p: mix([
        (0.0, sn("BOW Arrow Hit 05", p=1.0 * p, g=0, hit=True, length=0.4)),
        (0.0, sn("Just Gore _ Add On/Stab_Punch_Hit_136", p=0.95 * p, g=-6, hit=True)),
        (0.0, sn("Machete_Hit_Ring", 0, p=1.15 * p, g=-14, hit=True, length=0.35)),
    ]), "弩の会心: 深い刺さり + 鏃の鳴り")


def gun():
    shots = ["gun_rifle_sniper_shot_01", "gun_revolver_pistol_shot_04", "Shotgun_Fire_Slug_01", "gun_rifle_sniper_shot_01"]
    atk("gun", lambda i, p: mix([
        (0.0, sn(shots[i], p=[1.0, 0.9, 1.0, 1.06][i] * p, g=0, hit=True, length=0.55)),
        (0.0, sn("gun_semi_auto_rifle_cock_02", p=1.2, g=-20, hp=2000, hit=True, length=0.1)),
    ]), "銃: 実銃の発射と残響（狙撃銃・回転式・散弾）")
    hit("gun", lambda i, p: mix([
        (0.0, sn("Bullet_Impact_Hit_Body_Flesh_25", p=p, g=0, hit=True, length=0.3)),
        (0.0, sn("Hit Impact Metal Scrap Debris_UC 06", p=1.1 * p, g=-16, hit=True, length=0.15)),
    ]), "銃の命中: 弾が肉に当たる音 + 金属の跳ね")
    crit("gun", lambda i, p: mix([
        (0.0, sn("Bullet_Impact_Hit_Body_Flesh_25", p=0.9 * p, g=0, hit=True, length=0.35)),
        (0.0, sn("Smash B", p=1.1 * p, g=-8, lp=3000, length=0.35, hit=True)),
    ]), "銃の会心: 重い着弾 + 衝撃")


def cannon():
    atk("cannon", lambda i, p: mix([
        (0.0, sn("Automatic Cannon - MK44", 0, p=[1.0, 1.05, 0.95, 1.02][i] * p, g=0, hit=True, length=0.6)),
        (0.0, sn("tank_artillery_cannon_shot_012", p=1.15 * p, g=-8, lp=3000, hit=True, length=0.5)),
        (0.0, sn("Arc Weld Electrical Sparks 3", 1, p=p, g=-16, hp=2000, start=0.5, length=0.25)),
    ]), "砲: 砲の発射と残響 + 電気の弾け（星の砲）")
    hit("cannon", lambda i, p: mix([
        (0.0, sn("GS cannonball impact 005", p=1.1 * p, g=0, hit=True, length=0.45)),
        (0.0, sn("Damp Electric Shock 8", p=p, g=-14, hp=1500, start=0.2, length=0.2)),
    ]), "砲の命中: 砲弾の着弾 + 電気の弾け")
    crit("cannon", lambda i, p: mix([
        (0.0, sn("GS cannonball impact 005", p=0.95 * p, g=0, hit=True, length=0.6)),
        (0.0, sn("Explosive Hit 10", g=-4, length=0.5, hit=True)),
        (0.0, sn("High Voltage Electric Arcs 2", p=p, g=-14, hp=1500, start=0.3, length=0.3)),
    ]), "砲の会心: 大きな着弾 + 低音 + 放電")


# MARK: 魔法（詠唱の放ち = 通常攻撃、着弾 = 命中）。属性ごとに本物の録音

def magic_water():
    atk("magic_water", lambda i, p: mix([
        (0.0, sn("water_splash_small_008", p=1.1 * p, g=-4, hit=True, length=0.35)),
        (0.0, sn("Whoosh,Sound Design,Airy,Full,Soft,Buffet,Medium", p=1.2 * p, g=-12, hp=600, hit="peak", pre=0.08, length=0.25)),
    ]), "水の魔法: 水の弾け + 柔らかい風切り")
    hit("magic_water", lambda i, p: mix([
        (0.0, sn(["water_splash_drop_006", "LIQUID HIT Lake, Branch, Splash", "water_splash_small_008"][i], p=p, g=0, hit=True, length=0.4)),
    ]), "水の魔法の命中: 水の当たり")
    crit("magic_water", lambda i, p: mix([
        (0.0, sn("Bluezone_BC0256_water_splash_008", p=1.05 * p, g=0, hit=True, length=0.6)),
        (0.0, sn("10 Hit Deep Thud", p=1.2, g=-10, lp=200, length=0.3, hit=True)),
    ]), "水の魔法の会心: 大きな水しぶき + 低い芯")


def magic_fire():
    atk("magic_fire", lambda i, p: mix([
        (0.0, sn("torch_whoosh_20", p=1.05 * p, g=0, hit="peak", pre=0.08, length=0.4)),
        (0.02, sn("Fire_Spell_Dragon", p=1.1 * p, g=-12, hp=1500, length=0.3)),
    ]), "炎の魔法: 松明の炎の風切り + 炎の弾け")
    hit("magic_fire", lambda i, p: mix([
        (0.0, sn("Designed Fire - Impacts - Large, ignition 03", p=1.1 * p, g=0, hit=True, length=0.5)),
        (0.0, sn("Firecracker, Medium Distance 07", p=0.8 * p, g=-14, hit=True, length=0.2)),
    ]), "炎の魔法の命中: 火の着火の弾け")
    crit("magic_fire", lambda i, p: mix([
        (0.0, sn("Designed Fire - Impacts - Large, ignition 03", p=0.95 * p, g=0, hit=True, length=0.7)),
        (0.0, sn("Explosive Hit 10", g=-6, length=0.4, hit=True)),
    ]), "炎の魔法の会心: 大きな火の弾け + 低音")


def magic_lightning():
    atk("magic_lightning", lambda i, p: mix([
        (0.0, sn("ELECZap_Bug zapper zapping", p=p, g=0, hit=True, length=0.3)),
        (0.0, sn("Arc Weld Electrical Sparks 3", 1, p=1.05 * p, g=-6, hp=1000, start=0.3 + 0.4 * i, length=0.25)),
    ]), "雷の魔法: 放電の弾け + 火花")
    hit("magic_lightning", lambda i, p: mix([
        (0.0, sn("High Voltage Electric Arcs 2", p=p, g=0, start=0.2 + 0.5 * i, length=0.3)),
        (0.0, sn("Damp Electric Shock 8", p=1.1 * p, g=-6, start=0.1 + 0.3 * i, length=0.25)),
    ]), "雷の魔法の命中: 高電圧の放電")
    crit("magic_lightning", lambda i, p: mix([
        (0.0, sn("Thunder_Crack_Fienup_016", p=1.0 * p, g=0, start=0.05 * i, length=0.9)),
        (0.0, sn("High Voltage Electric Arcs 2", p=0.95 * p, g=-4, start=1.0, length=0.35)),
    ]), "雷の魔法の会心: 本物の雷鳴の割れ + 放電")


def magic_light():
    atk("magic_light", lambda i, p: mix([
        (0.0, sn("Impact,Sound Design,Hit,Chime,Resonant Hit", p=1.1 * p, g=-4, hit=True, length=0.5)),
        (0.0, sn("Whoosh,Sound Design,Airy,Full,Soft,Buffet,Medium", p=1.3 * p, g=-12, hp=1500, hit="peak", pre=0.06, length=0.2)),
    ]), "聖の魔法: 鐘の澄んだ鳴り + 柔らかい風切り")
    hit("magic_light", lambda i, p: mix([
        (0.0, sn("Bell_Waiter_Fienup_001", p=[0.8, 0.9, 0.75][i] * p, g=-4, hit=True, length=0.6)),
        (0.0, sn("punch_general_body_impact_03", p=0.8 * p, g=-10, hit=True)),
    ]), "聖の魔法の命中: 鐘の打音 + 鈍い衝撃")
    crit("magic_light", lambda i, p: mix([
        (0.0, sn("80,TheGong", p=1.2 * p, g=0, hit=True, length=0.9)),
        (0.0, sn("Smash B", p=1.0 * p, g=-8, lp=2000, length=0.4, hit=True)),
    ]), "聖の魔法の会心: 銅鑼の一撃 + 重い衝撃")


def magic_dark():
    atk("magic_dark", lambda i, p: mix([
        (0.0, sn("MAGEvil_Dark Spell Dark Energy Attack", p=p, g=0, hit=True, length=0.45)),
        (0.0, sn("dark_portal_wind_effect_04", p=1.2 * p, g=-8, start=0.5 + 0.8 * i, length=0.35)),
    ]), "闇の魔法: 暗い気の放ち + 低いうねりの風")
    hit("magic_dark", lambda i, p: mix([
        (0.0, sn("med_dark_001", p=1.0 * p, g=0, hit=True, length=0.6)),
        (0.0, sn("IMPACT DARK Epic Punch", p=1.05 * p, g=-8, hit="peak", pre=0.02, length=0.3)),
    ]), "闇の魔法の命中: 低く重い衝撃")
    crit("magic_dark", lambda i, p: mix([
        (0.0, sn("Bluezone_BC0250_impact_metal_01", p=0.9 * p, g=0, hit=True, length=0.7)),
        (0.0, sn("Haunted Metal Vol 1_02", p=1.0 * p, g=-6, lp=600, length=0.6, hit=True)),
    ]), "闇の魔法の会心: 暗い金属の衝撃 + 低いうねり")


def magic_ice():
    atk("magic_ice", lambda i, p: mix([
        (0.0, sn("Ice_impact_lite_02", p=1.1 * p, g=-2, hit=True, length=0.25)),
        (0.0, sn("dry ice sizzle - serrated", p=1.0 * p, g=-10, start=0.3 + 0.4 * i, length=0.3)),
    ]), "氷の魔法: 氷の澄んだ打音 + 冷気の擦れ")
    hit("magic_ice", lambda i, p: mix([
        (0.0, sn(["Ice_smash_light_02", "Ice_chunk_heavy_07", "thick ice hits impacts debris bright 03"][i], p=p, g=0, hit=True, length=0.45)),
    ]), "氷の魔法の命中: 氷が砕ける音")
    crit("magic_ice", lambda i, p: mix([
        (0.0, sn("Iceberg,Designed,Impact,Crack,Shatter,Huge_08", p=1.1 * p, g=0, hit=True, length=0.9)),
        (0.0, sn("Ice_chunk_heavy_07", p=0.9 * p, g=-6, hit=True, length=0.4)),
    ]), "氷の魔法の会心: 大きな氷の割れと砕け")


SETS = [sword, greatsword, dual, spear, fist, hammer, chain, bow, crossbow, gun, cannon,
        magic_water, magic_fire, magic_lightning, magic_light, magic_dark, magic_ice]


def build():
    for f in SETS:
        f()
