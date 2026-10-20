"""H034 ゴルム（MLBB: フランコ）のスキル・通常攻撃・パッシブの音。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403
import build_audio as B  # noqa: E402,F401


def build():
    hero = "H034"
    # 通常攻撃（4 種）: 命中の瞬間（attackReleased）に、斧鉤が肉と鉄に食い込む打撃 + 低い芯 + 鎖の小さな鳴り
    for k, (hi, ci, p) in enumerate([(0, 0, 1.0), (1, 2, 0.96), (2, 4, 1.04), (4, 5, 0.99)], start=1):
        x = mix([(0, sn("Two-Handed Axe Flesh Hit", hi, p=0.92 * p, g=0, post=0.15, hit="peak", pre=0.04)),
                 (0.03, sn("10 Hit Deep Thud", p=1.15 * p, g=-6, lp=180, length=0.3, hit=True)),
                 (0.04, sn("Dog_Chain-Hits", ci, p=0.85, g=-12, hp=1500, length=0.3, hit=True))])
        write(f"skill_{hero}_atk_{k}", x, "atk", "斧鉤の打撃（肉と鉄）+ 低い芯 + 鎖の鳴り")
    # 通常攻撃の命中（3 種）: 肉を打つ鈍い音（控えめ）
    for k, part in enumerate(["PUNCH_SMACK_LETTUCE", "FLOG Leather", "PUNCH_PERCUSSIVE_HEAVY"], start=1):
        x = mix([(0, sn(part, k if part == "FLOG Leather" else 0, p=0.85, g=0, post=0.15, hit=True)),
                 (0.0, sn("IMPACT_LOW_THUD", p=0.9, g=-6, hit=True))])
        write(f"skill_{hero}_atkhit_{k}", x, "atkhit", "肉を打つ鈍い音")

    # S1 鎖鉤: 0〜0.33 の振りかぶり（鎖を回す音がふくらむ）→ 0.33 で投げ（風切り・鎖の放り出し）→ 飛ぶ間の鎖の連なり
    s1 = mix([
        (0.0, rise(sn("Jingle_Chain-Sustained", 0, p=0.8, g=-14, length=0.4), 0.3)),
        (0.12, rise(sn("ROPE WHOOSH Fast Light", 3, p=0.6, g=-10, hp=200), 0.12)),
        (0.33, sn("ROPE WHOOSH Fast Light", 0, p=0.75, g=-2, hp=150, hit="peak", pre=0.03)),
        (0.33, sn("Chains_Metal_Dropping", 0, p=0.9, g=-6, hp=400, length=0.25, hit=True)),
        (0.34, sn("10 Hit Deep Thud", p=1.3, g=-16, lp=200, length=0.25, hit=True)),
        (0.38, sn("Movement_Distant_Short", 1, p=1.05, g=-6, hp=600, length=0.55)),
        (0.4, sn("Rattle, Pass By", p=1.1, g=-14, hp=800, start=0.1, length=0.5)),
        (0.38, sn("Heavy_Chain-Foley_On_Wood", 1, p=1.1, g=-4, lp=2500, length=0.6)),
        (0.4, sn("Jingle_Chain-Sustained", 10, p=1.0, g=-6, hp=2500, length=0.55)),
        (0.36, rise(sn("Sub Drop 2", g=-12, lp=140, length=0.6), 0.1)),
    ])
    write(f"skill_{hero}_s1_cast", tail(reverb(s1, 0.4, 0.08, 7), 0.9, 1.05), "cast", "鎖を回す → 投げ（風切り・鎖の放り出し）→ 飛ぶ鎖の連なり",
          target=-21.0)
    # 命中（引き寄せの 0.45 秒前）: 鉤が肉に刺さる重い打撃 + 鉄の鉤 → 0.45 で鎖を引く（金属の連なり・擦れ・体を引く風）
    for k, (pi, ci) in enumerate([(0, 0), (1, 1), (2, 0)], start=1):
        x = mix([
            (0, sn("PUNCH_SIMPLE_CLEAN_DEEP", p=0.8 + 0.04 * k, g=0, hit=True)),
            (0, sn("Heavy Body Crunch", 1, p=0.9, g=-8, length=0.3, hit=True)),
            (0, sn("IMPACT METAL Scratchy Short Punch", p=0.85 + 0.05 * k, g=-8, lp=7000, length=0.3, hit=True)),
            (0.01, sn("Explosive Hit 10", g=-4, length=0.5, hit=True)),
            (0.05, sn("Trailer Hit Cavernous", g=3, lp=150, length=0.3)),
            (0.45, sn("Chains_Metal_Dropping", ci, p=1.0, g=8, hp=500, length=0.5, hit=True)),
            (0.45, sn("Heavy_Chain-Foley_On_Wood", 0, p=1.0, g=4, length=0.35, hit="peak", pre=0.03)),
            (0.45, sn("GRAB_BLOCK_THROW", p=0.8, g=0, hit=True)),
            (0.45, sn("WHIP Snap Crack", p=0.8, g=0, hp=1500, hit="peak", pre=0.02, length=0.25)),
            (0.47, sn("Movement_Distant_Very-Short", p=1.0, g=2, hp=800, length=0.3)),
        ])
        write(f"skill_{hero}_s1_hit_{k}", tail(x, 0.85, 1.05), "hit", "鉤が刺さる重い打撃 + 鉄 → 0.45 秒後に鎖を引く", target=-20.0,
              cap=1.1)

    # S2 鉄鎖旋: 0〜0.27 の短い振り上げ → 0.27 で斧鉤を地に叩きつける（体の芯・低音・土・鉄）→ 低音が 0.5 秒 → 0.8 で消える
    s2 = mix([
        (0.0, rise(sn("Swing 3 Large", p=0.8, g=-2, hp=1200, hit="peak", pre=0.22, length=0.3), 0.12)),
        (0.27, sn("10 Hit Deep Thud", p=0.95, g=5, lp=600, hp=90, length=0.4, hit=True)),
        (0.27, sn("Explosive Hit 10", g=-12, length=0.4, hit=True)),
        (0.27, sn("RL_bodyfall_Dirt", p=0.8, g=-2, length=0.2, hit=True)),
        (0.27, sn("IMPACT METAL Short Slam", p=0.8, g=-10, lp=5000, length=0.12, hit=True)),
        (0.28, sn("GROUND IMPACT Large", g=-14, hp=2500, length=0.5, hit=True)),
        (0.3, rise(sn("Fire_Spell_Dragon", g=-22, hp=3000, start=0.3, length=0.3), 0.05)),
        (0.3, sn("Trailer Hit Cavernous", g=-7, lp=150, length=0.6)),
    ])
    write(f"skill_{hero}_s2_cast", tail(reverb(s2, 0.4, 0.08, 8), 0.75, 1.05), "cast", "短い振り上げ → 叩きつけ（体の芯・低音・土・鉄）→ 低音の尾",
          target=-19.8)
    for k, part in enumerate(["PUNCH_PERCUSSIVE_HEAVY", "IMPACT_LOW_THUD", "PUNCH_DESIGNED_LIGHT"], start=1):
        x = mix([(0, sn(part, p=0.85, g=0, hit=True)), (0, sn("RL_bodyfall_Dirt", p=0.9 + 0.05 * k, g=-16, length=0.25, hit=True))])
        write(f"skill_{hero}_s2_hit_{k}", x, "hit", "衝撃が体に当たる鈍い音 + 土", target=-25.0)

    # 奥義 狩猟鎖獄: 0.25 で掴みかかる一閃（鞭の擦れ・鎖・掴みの打撃。MLBB で一番大きい）→ 拘束の間の掴み合いの擦れと低いうなり
    ult = mix([
        (0.05, rise(sn("ROPE WHOOSH Fast Light", 1, p=0.7, g=-18, hp=200), 0.12)),
        (0.3, sn("Jingle_Chain-Sustained", 0, p=1.1, g=-6, hp=3000, length=0.45)),
        (0.25, sn("WHIP Snap Crack", p=0.75, g=0, hit="peak", pre=0.02)),
        (0.25, sn("GRAB_BLOCK_THROW", p=0.85, g=-2, hit=True)),
        (0.25, sn("Chains_Metal_Dropping", 0, p=0.85, g=-4, hp=400, length=0.4, hit=True)),
        (0.26, sn("Explosive Hit 10", g=-6, length=0.5, hit=True)),
        (0.3, sn("Choking, Tension", p=0.9, g=-4, hp=150, start=0.2, length=1.75)),
        (0.42, sn("LowSwings31", p=1.0, g=-8, hp=300, hit="peak", pre=0.1, length=0.16)),
        (0.74, sn("DesignedSwings12", p=0.95, g=-8, hp=300, hit="peak", pre=0.1, length=0.16)),
        (1.06, sn("LowSwings31", p=1.05, g=-8, hp=300, hit="peak", pre=0.1, length=0.16)),
        (1.38, sn("DesignedSwings12", p=1.0, g=-8, hp=300, hit="peak", pre=0.1, length=0.16)),
        (1.5, sn("Swing 3 Large", p=0.7, g=-8, hp=300, hit="peak", pre=0.08, length=0.15)),
        (1.68, sn("RL_bodyfall_Dirt", p=0.75, g=-6, length=0.25, hit=True)),
        (1.68, sn("10 Hit Deep Thud", p=1.05, g=-10, lp=500, length=0.3, hit=True)),
        (0.3, sn("Heavy Body Crunch", 1, p=0.9, g=-6, hp=150, length=1.75)),
    ])
    write(f"skill_{hero}_ult_cast", tail(reverb(ult, 0.5, 0.1, 9), 1.75, 2.05), "ult", "掴みかかる一閃（鞭・鎖・掴み）→ 拘束の擦れと低いうなり",
          target=-16.0, cap=2.1)
    # 1 撃ごと（6 撃。1 撃 -13〜-15 LUFS）: 拳と斧鉤の重い打撃・骨に響く砕け・低音の芯・鎖の跳ね
    for k, (pi, ci) in enumerate([(0, 0), (1, 1), (2, 0)], start=1):
        x = mix([
            (0, sn("PUNCH_SIMPLE_CLEAN_DEEP", p=0.72 + 0.05 * k, g=0, hp=90, hit=True)),
            (0, sn("IMPACT DARK Epic Punch", p=0.9 + 0.04 * k, g=-4, hp=110, hit="peak", pre=0.02, length=0.45)),
            (0, sn("Heavy Body Crunch", pi, p=0.85, g=-8, length=0.3, hit=True)),
            (0.01, sn("Smash_Gore_Juicy_Smash", 0, p=0.8 + 0.05 * k, g=-8, length=0.4, hit=True)),
            (0.02, sn("Melee_Deep_Wound", p=0.9, g=-10, length=0.3, hit=True)),
            (0.0, sn("Explosive Hit 10", p=1.0 + 0.05 * k, g=-10, length=0.3, hit=True)),
            (0.02, sn("Dog_Chain-Hits", 3 + k, p=0.8, g=-14, hp=1500, length=0.25, hit=True)),
        ])
        write(f"skill_{hero}_ult_hit_{k}", x, "hit", "拳と斧鉤の重い打撃 + 砕け + 低音の芯 + 鎖の跳ね", target=-14.5)

    # パッシブ（闘気がたまり始める）: 0.5 秒かけて低音がふくらむ（逆再生の低い打撃）+ 手の金の光のきらめき
    pas = mix([(0, rise(rev(sn("Trailer Hit Cavernous", g=8, lp=160, length=0.55)), 0.2)),
               (0.42, sn("Trailer Hit Cavernous", g=2, lp=250, length=0.65)),
               (0.0, rise(sn("Ice_Spell_Ice_Spell_Buff_Positive", p=0.8, g=-16, hp=2000, length=1.1), 0.1)),
               (0.3, sn("energy flow, astral travel", p=0.9, g=-9, hp=1500, start=3.0, length=0.8))])
    write(f"skill_{hero}_passive", tail(pas, 0.95, 1.15), "passive", "闘気（低音のふくらみ + 光のきらめき）", target=-22.0)
    return hero
