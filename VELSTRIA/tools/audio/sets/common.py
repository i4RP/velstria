"""戦闘の共通の音（SFX の戦闘の分。AudioFiles.sfx の名前）。すべて実音の録音から（合成・電子音は使わない）。

- 汎用の通常攻撃・命中・会心（武器の組が無いユニットの保険。34 体は武器の組 sets/weapons.py を使う）
- 汎用のスキル・奥義の発動（スキルの音が無いヒーローの保険）
- 回復・シールド・死亡・キル・連続キル・塔の破壊・目標（ドラゴン等）・ゴールド・リコール・復活・レベルアップ・告知
- 塔・Star Core（立ち上がり・ロック・亀裂・倒壊・着地・結晶の消失。StructureFXDirector が画面付近の構造物だけ鳴らす）
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403


def build():
    # 汎用の通常攻撃・命中・会心（剣と弓）
    for k, p in enumerate([1.0, 0.96], start=1):
        write(f"sfx_attack_melee_{k}", mix([
            (0.0, sn("whoosh_weapon_knife_swing_04", p=0.85 * p, g=-8, hp=500, hit="peak", pre=0.04, length=0.12)),
            (0.0, sn("Sword Slash Impact V2 Assorted 18", p=p, g=0, hit="peak", pre=0.04, length=0.45))]),
            "atk", "汎用の近接攻撃: 刃の風切り → 斬り", target=-23.0)
        write(f"sfx_attack_ranged_{k}", mix([
            (0.0, sn("crossbow1,carbonbolt,atbow,snap", p=0.75 * p, g=-2, hit=True, length=0.25)),
            (0.03, sn("PARTICLES_WHOOSH_Arrow", p=1.1 * p, g=-8, hp=1000, hit="peak", pre=0.08, length=0.25))]),
            "atk", "汎用の遠隔攻撃: 弦の鳴り → 矢の風切り", target=-23.0)
        write(f"sfx_crit_{k}", mix([
            (0.0, sn("Machete_Hit_Ring", k - 1, p=0.92 * p, g=0, hit=True, length=0.5)),
            (0.0, sn("10 Hit Deep Thud", p=1.2, g=-10, lp=200, length=0.3, hit=True))]),
            "crit", "汎用の会心: 刃の鋭い鳴り + 低い芯", target=-22.0)
    for k, p in enumerate([1.0, 0.95, 1.06], start=1):
        write(f"sfx_hit_{k}", mix([
            (0.0, sn("medium metal blade wet impact", p=p, g=-2, hit=True, length=0.3)),
            (0.0, sn("punch_general_body_impact_03", p=0.9 * p, g=-10, lp=2500, hit=True))]),
            "atkhit", "汎用の命中: 体への衝撃", target=-26.0)

    # 汎用のスキル・奥義の発動（スキルの音が無いヒーローの保険）
    write("sfx_skill_cast", mix([
        (0.0, rise(sn("MAGIC AIR Large Whoosh", p=1.1, g=-2, hp=200, length=0.45), 0.2)),
        (0.3, sn("Smash B", p=1.1, g=-8, lp=3000, length=0.45, hit=True))]), "cast", "汎用のスキル: 渦の風 → 衝撃", target=-21.0)
    write("sfx_ultimate_cast", mix([
        (0.0, rise(sn("Titan D", p=0.9, g=-2, length=0.7), 0.5)),
        (0.55, sn("Smash B", p=0.95, g=0, length=0.7, hit=True)),
        (0.55, sn("Haunted Metal Vol 1_02", g=-8, lp=400, length=0.8, hit=True))]), "ult", "汎用の奥義: 大きな溜めの風 → 重い一撃 + 金属の低音", target=-19.0)

    # 回復: 風鈴（磁器）と柔らかい風
    write("sfx_heal", mix([
        (0.0, sn("windbell,Japanese,porcelain", p=1.0, g=0, length=1.0)),
        (0.0, rise(sn("Whoosh,Sound Design,Airy,Full,Soft,Shudder,Very Slow,Aftershock", p=1.3, g=-10, hp=800, length=0.8), 0.3))]),
        "event", "回復: 磁器の風鈴 + 柔らかい風", target=-25.0, cap=1.2)
    # シールド: 盾の金属の鳴り（回る盾の響き）+ 盾の受け
    write("sfx_shield", mix([
        (0.0, sn("Metal Shield Block Hits", 3, p=1.05, g=0, hit=True, length=0.4)),
        (0.02, sn("Metal Shield Spin On Floor", 1, p=1.1, g=-6, length=0.6))]),
        "event", "シールド: 盾の受けの金属 + 盾の響き", target=-24.0, cap=0.9)
    # 死亡: 体が倒れる音 + 低いブーム + 暗い金属の尾
    write("sfx_death", tail(mix([
        (0.0, sn("RL_bodyfall_Dirt", p=0.85, g=0, hit=True)),
        (0.0, sn("Boom 040", p=0.9, g=-2, length=1.0, hit=True)),
        (0.05, sn("Haunted Metal Vol 1_18", g=-8, lp=1500, length=1.4, hit=True))]), 1.2, 1.7),
        "event", "死亡: 体が倒れる音 + 低いブーム + 暗い金属の尾", target=-19.0)
    # キル: 抜き身の刃の鳴り + 鋭い一撃
    write("sfx_kill", mix([
        (0.0, sn("Machete_Hit_Ring", 0, p=0.85, g=0, hit=True, length=0.6)),
        (0.0, sn("Smash B", p=1.15, g=-6, lp=4000, length=0.4, hit=True)),
        (0.05, sn("HERO - DESIGNED - SWORD Unsheathe", 1, p=1.0, g=-10, length=0.8))]),
        "event", "キル: 刃の鋭い鳴り + 一撃 + 抜き身の刃", target=-20.0, cap=1.2)
    # 連続キル: 銅鑼 + 一撃 + 刃
    write("sfx_multi_kill", mix([
        (0.0, sn("80,TheGong", p=1.1, g=0, hit=True, length=1.8)),
        (0.0, sn("Smash B", p=1.0, g=-4, length=0.6, hit=True)),
        (0.02, sn("Machete_Hit_Ring", 1, p=0.8, g=-8, hit=True, length=0.6))]),
        "event", "連続キル: 銅鑼 + 重い一撃 + 刃の鳴り", target=-18.0, cap=2.2)
    # 塔の破壊（告知）: 石の崩落 + 爆発 + 低いブーム
    write("sfx_tower_destroyed", tail(mix([
        (0.0, sn("EXPLReal_Medium Realistic Explosion 15", p=0.85, g=0, hit=True, length=1.5)),
        (0.05, sn("building_collapse_debris_falling_rock_rubble_008", p=0.95, g=-4, length=2.0)),
        (0.0, sn("Boom 040", p=0.85, g=-2, length=1.2, hit=True))]), 1.8, 2.4),
        "event", "塔の破壊: 爆発 + 石の崩落 + 低いブーム", target=-18.0)
    # 目標（ドラゴン等）: 角笛のブラーム + 銅鑼
    write("sfx_objective", tail(mix([
        (0.0, sn("Cinematic Horn Braam, Epic, Cinematic, Dark, Instrument, Huge-32", p=1.0, g=0, length=2.2)),
        (0.0, sn("PotGong", p=1.0, g=-6, hit=True, length=2.0))]), 1.8, 2.4),
        "stinger", "目標: 角笛のブラーム + 銅鑼", target=-18.0)
    # ゴールド: 硬貨（短く）
    coins = [("Coins_Hand_Jingle_Movement_Takes_6", 0), ("Coins_Hand_Jingle_Movement_Takes_6", 1), ("Money,Coins,Handle", 0)]
    for k, (part, take) in enumerate(coins, start=1):
        write(f"sfx_gold_{k}", sn(part, take, p=1.05, g=0, hit=True, length=0.3), "ui", "ゴールド: 硬貨の鳴り", target=-28.0)
    # リコール: 長く柔らかい風 + 風鈴（始まりと終わりで鳴る）
    write("sfx_recall", mix([
        (0.0, rise(sn("Whoosh,Sound Design,Airy,Full,Soft,Shudder,Very Slow,Aftershock", p=1.0, g=0, length=1.4), 0.6)),
        (0.3, sn("windchimes,mixed,paper,aluminum", p=1.1, g=4, length=1.4))]),
        "event", "リコール: 柔らかい風 + 風鈴", target=-24.0, cap=1.8)
    # 復活: 鉢（シンギングボウル）の一打 + 風
    write("sfx_respawn", tail(mix([
        (0.0, sn("SINGING_BOWL_Strike_Sustain_D_02", p=1.2, g=0, hit=True, length=1.8)),
        (0.0, rise(sn("Whoosh,Sound Design,Airy,Full,Soft,Buffet,Medium", p=0.9, g=-8, length=0.6), 0.3))]), 1.4, 1.9),
        "event", "復活: 鉢の一打 + 風", target=-22.0)
    # レベルアップ: ベルツリーの上がり + 鉢の高い鳴り
    write("sfx_level_up", tail(mix([
        (0.0, sn("BELL TREE UP DOWN", 0, p=1.0, g=0, length=1.2)),
        (0.15, sn("SINGING_BOWL_Strike_Sustain_D_02", p=1.6, g=-8, hit=True, length=1.0))]), 1.0, 1.4),
        "event", "レベルアップ: ベルツリー + 鉢", target=-23.0)
    # 告知: 銅鑼の短い一打
    write("sfx_announcement", tail(sn("PotGong", p=1.1, g=0, hit=True, length=1.6), 1.0, 1.6), "event", "告知: 銅鑼の一打", target=-22.0)

    # 塔・Star Core
    write("sfx_tower_rise", tail(mix([
        (0.0, rise(sn("earthquake_rumble_large_005", p=0.9, g=0, length=1.8), 0.6)),
        (0.2, sn("building_collapse_debris_falling_rock_rubble_008", p=0.8, g=-10, lp=3000, length=1.4))]), 1.6, 2.0),
        "world", "塔の立ち上がり: 地鳴り + 石の擦れ", target=-24.0)
    write("sfx_tower_lock", mix([
        (0.0, sn("Iron - Thick - HIT - Hammer", 2, p=0.7, g=0, hit=True, post=0.4)),
        (0.0, sn("Metal_Barrel_Bolt_Lock", p=0.8, g=-8, length=0.5))]), "world", "塔のロック: 重い鉄の打撃 + ボルトの音", target=-24.0, cap=1.0)
    write("sfx_tower_crack", mix([
        (0.0, sn("Bluezone_BC0297_stone_impact_041", p=0.85, g=0, hit=True)),
        (0.0, sn("Ice,Block,Crack,Distant,Medium_03", p=0.7, g=-6, lp=2500, length=0.8))]), "world", "塔の亀裂: 石の打撃 + 割れ", target=-23.0, cap=1.0)
    write("sfx_tower_collapse", tail(mix([
        (0.0, sn("building_collapse_debris_falling_rock_rubble_008", p=0.9, g=0, length=2.5)),
        (0.0, sn("Boom 040", p=0.8, g=-4, length=1.2, hit=True))]), 2.2, 3.0), "world", "塔の倒壊: 石の崩落 + 低いブーム", target=-20.0)
    write("sfx_tower_impact", mix([
        (0.0, sn("GROUND IMPACT Large", p=0.85, g=0, hit=True, length=1.2)),
        (0.0, sn("Explosive Hit 10", g=-4, length=0.8, hit=True))]), "world", "塔の着地: 地面への重い衝撃 + 低音", target=-21.0, cap=1.5)
    write("sfx_crystal_fade", tail(mix([
        (0.0, sn("Tall Narrow, Tone, Rubbing, Musical_01", p=1.0, g=0, length=1.8)),
        (0.0, sn("GLASMisc_Reverse Glass Effect", p=1.0, g=-8, length=0.8))]), 1.4, 2.0), "world", "結晶の消失: 水晶のグラスの鳴り + ガラスの逆再生", target=-25.0)
